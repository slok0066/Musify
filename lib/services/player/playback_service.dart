import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../../data/models/track.dart';
import '../media_cache.dart';
import '../mp4_aac.dart';
import '../settings_service.dart';

/// What the engine needs in order to start a track.
class PlayableSource {
  const PlayableSource({
    required this.path,
    required this.isLocalFile,
    required this.bitrate,
  });

  /// A filesystem path, or an http(s) URL when nothing could be staged.
  final String path;
  final bool isLocalFile;
  final int bitrate;
}

/// Resolves a track to something playable and reports transfer progress.
typedef SourceResolver = Future<PlayableSource?> Function(
  Track track, {
  ValueChanged<double?>? onProgress,
  bool prefetch,
});

/// Resolves a track to a source that can be read *while it downloads*.
typedef StreamOpener = Future<StreamSource?> Function(Track track);

/// The completed local file for a track, or `null` when it is not whole yet.
typedef CompletedPathLookup = String? Function(Track track);

/// The Musify audio engine.
///
/// This is the single source of truth for playback state. It owns the SoLoud
/// instance, the queue, the 8D spatial DSP chain, the parametric equalizer, the
/// sleep timer and the crossfader. It has **no** platform dependencies, so the
/// exact same engine runs on Android (wrapped by `audio_service` for the lock
/// screen) and on desktop (driven directly), which is what makes it testable.
///
/// ## The three-stage 8D pipeline (PRD §4.1)
/// 1. **Orbit** — a 60 fps LFO moves the voice around the listener:
///    `x = 2·sin(θ)`, `z = 2·cos(θ)`, reinforced with a constant-power pan of
///    `0.85·sin(θ)`.
/// 2. **Rear shadowing** — the biquad low-pass cutoff tracks the voice's `z`:
///    16 kHz in front of the head down to 3.2 kHz behind it.
/// 3. **Hall** — a freeverb with `roomSize = 0.72`, `damping = 0.50`, wet mixed
///    in over 350 ms.
///
/// ## Safety
/// Every FFI touch goes through [_live], which asserts that the engine is
/// initialised *and* that the voice handle is still valid. Nothing in this file
/// can throw into the widget tree; failures surface as [errorText] and the
/// engine resets to a known state.
class PlaybackService {
  PlaybackService({
    required SourceResolver resolveSource,
    required SettingsService settings,
    StreamOpener? openStream,
    CompletedPathLookup? completedPath,
  })  : _resolveSource = resolveSource,
        _openStream = openStream,
        _completedPath = completedPath,
        _settings = settings {
    _settings.addListener(_onSettingsChanged);
  }

  final SourceResolver _resolveSource;

  /// Resolves a track to a read-while-writing source (the instant-play path).
  /// `null` in tests and on platforms without a repository.
  final StreamOpener? _openStream;

  /// Where a *complete* local copy of a track lives, if it exists. The
  /// crossfader needs a file it can hand to the engine immediately.
  final CompletedPathLookup? _completedPath;

  final SettingsService _settings;

  /// Read-only settings access for the platform adapter.
  SettingsService get settings => _settings;

  final SoLoud _soloud = SoLoud.instance;

  // ------------------------------------------------------------------ state

  final ValueNotifier<Track?> currentTrack = ValueNotifier<Track?>(null);
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isBuffering = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> buffered = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<String?> errorText = ValueNotifier<String?>(null);
  final ValueNotifier<double?> bufferFraction = ValueNotifier<double?>(null);

  final ValueNotifier<bool> is8DEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> shuffleEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<RepeatMode> repeatMode = ValueNotifier<RepeatMode>(RepeatMode.off);
  final ValueNotifier<Duration?> sleepRemaining = ValueNotifier<Duration?>(null);
  final ValueNotifier<bool> headphonesConnected = ValueNotifier<bool>(false);

  final ValueNotifier<List<Track>> queue = ValueNotifier<List<Track>>(const []);
  final ValueNotifier<int> queueIndex = ValueNotifier<int>(0);

  /// Increments whenever the user-visible playback state changes, so the
  /// lock-screen adapter can mirror it without polling.
  final ValueNotifier<int> stateRevision = ValueNotifier<int>(0);

  final StreamController<Float32List> _fftController =
      StreamController<Float32List>.broadcast();

  Stream<Float32List> get fftStream => _fftController.stream;

  // ----------------------------------------------------------------- engine

  AudioSource? _source;
  SoundHandle? _handle;
  AudioSource? _incomingSource;
  SoundHandle? _incomingHandle;
  Timer? _positionTimer;
  DateTime? _seekSuppressedUntil;
  Timer? _crossfadeTimer;
  Timer? _sleepTimer;
  Timer? _orbitTimer;
  final Stopwatch _orbitClock = Stopwatch();
  StreamSubscription<void>? _finishSub;
  StreamSubscription<AudioVisualizationData>? _vizSub;

  int _queueIndex = 0;
  List<int> _shuffleOrder = const [];
  int _shufflePosition = 0;

  bool _engineReady = false;
  bool _switching = false;
  bool _crossfading = false;
  bool _visualizerOn = false;
  bool _disposed = false;

  /// Track id -> already-staged local path, used for gapless transitions.
  final Map<String, String> _staged = {};

  // ------------------------------------------------------- instant playback
  //
  // The progressive path: instead of downloading an MP4 and letting the engine
  // decode all of it before the first sample, Musify reads the MP4's sample
  // table and hands the engine ADTS-wrapped AAC frames as it asks for them.
  // See `mp4_aac.dart` for the container work and `MediaCache.openStream` for
  // the read-while-writing transfer.

  /// The live byte source behind the current voice, when streaming.
  StreamSession? _streamSession;

  /// The parsed sample table of the current stream.
  Mp4AacIndex? _streamIndex;

  /// True while [_source] is a pull-buffer stream rather than a loaded file.
  bool _streaming = false;
  int _streamByteOffset = 0;
  Duration _streamTimeOffset = Duration.zero;

  /// The engine has produced sound from the stream (so a feed failure should be
  /// reported rather than answered with a restart).
  bool _streamStarted = false;

  /// Feeds that are already in flight, keyed by ADTS offset. Two requests for
  /// the same offset must not buy the same bytes twice.
  final Set<int> _feedsInFlight = {};

  /// Tracks whose stream did not work, so they are never retried in a loop.
  final Set<String> _streamFailed = {};

  int _streamStumbles = 0;
  Timer? _streamWatchdog;

  /// True while a streaming voice is being handed over to the download route
  /// (a seek the engine's decoded window cannot answer). Seeks arriving during
  /// the handoff are coalesced into [_pendingSeekTarget] instead of dropped.
  bool _handoffToDownload = false;

  /// The newest seek requested while [_handoffToDownload] was in flight.
  Duration? _pendingSeekTarget;

  /// True while the pull stream is being rebuilt at a new position. The
  /// rebuild is sequential (old voice retired, then the new one built), and
  /// only one may be in flight at a time.
  bool _restartingStream = false;

  /// Forces the next [_startCurrent] down the proven download route. A seek
  /// handoff sets it so the restart cannot re-enter live streaming and undo
  /// the position the user picked.
  bool _forceClassicNextStart = false;

  /// True while a stream is migrating to a finished disk file, so the
  /// completion poll cannot start the same migration twice.
  bool _switchingToLocal = false;

  /// Bumped whenever the pull stream's byte window is replaced (start, seek,
  /// teardown) and whenever the voice migrates to a disk file. Feeds capture
  /// it on entry and abort when it changes, so a read that was in flight
  /// during a seek can never write into the wrong source.
  int _streamEpoch = 0;

  /// After a re-seek the engine must produce sound before [_seekDeadline];
  /// [_seekTarget] remembers where the user asked to be so the download
  /// route can take over at that position instead of leaving silence.
  Duration? _seekTarget;
  DateTime? _seekDeadline;

  /// Transfer coverage seen at the previous watchdog check, and how many times
  /// a slow-but-alive seek has been given more time. A stream whose bytes are
  /// still arriving is not a lost cause: forcing the whole-file route on it
  /// would be slower than letting the rebuilt stream finish.
  int? _seekProgress;
  int _seekExtensions = 0;

  /// The newest scrub position already handed to the transfer, and when. While
  /// the finger is still on the slider those hints are throttled so one drag
  /// repositions the connection at most a few times.
  Duration? _hintTarget;
  DateTime? _hintAt;

  /// The current track has already been reported as finished, so a second
  /// signal (finish callback, end-of-buffer detection) cannot advance the queue
  /// twice.
  bool _endNotified = false;

  /// How much ADTS stream one feed carries. ~190 KB is about four and a half
  /// seconds of 320 kbps AAC: long enough that the engine is never starved,
  /// short enough that a seek is not waiting on a quarter-megabyte read.
  static const int _feedWindowBytes = 192 * 1024;

  /// The engine's decoded circular buffer for a progressive stream. 10 MB of
  /// stereo float32 is about 30 seconds of audio, so a seek inside that window
  /// is a native, instant move — the old 4 MB held only ~12 s. This is also
  /// the plugin's own default, so no engine ever meets a size it dislikes.
  static const int _streamBufferBytes = 10 * 1024 * 1024;

  /// How far behind its target a disk seek may land and still count as a real
  /// move: MP3 frames snap to ~26 ms, while a seek that failed outright sits
  /// at zero — the one outcome that must never be adopted.
  static const Duration _localSeekSlack = Duration(milliseconds: 1200);

  bool get engineReady => _engineReady;

  /// True while a voice handle can safely be dereferenced.
  bool _live(SoundHandle? handle) =>
      handle != null && _soloud.isInitialized && _soloud.getIsValidVoiceHandle(handle);

  // ------------------------------------------------------------------- setup

  /// Boots the C++ engine. Time-boxed by the caller so a stuck audio device can
  /// never block the first frame.
  Future<void> initEngine() async {
    if (_engineReady || _disposed) return;
    try {
      if (!_soloud.isInitialized) {
        await _soloud.init(
          sampleRate: 44100,
          bufferSize: 2048,
          channels: Channels.stereo,
        );
      }

      // Listener sits at the origin, facing +Z, with +Y up.
      _soloud.set3dListenerParameters(
        0, 0, 0,
        0, 0, 1,
        0, 1, 0,
        0, 0, 0,
      );
      _soloud.set3dSoundSpeed(343);
      _soloud.setFftSmoothing(0.75);
      _soloud.setFftDecibelRange(-90, 0);

      _engineReady = true;
      _applyEqualizer();
      _applyBassBoost();
      _apply8DParameters();
    } catch (e) {
      debugPrint('SoLoud init failed: $e');
      _engineReady = false;
      errorText.value = 'AUDIO ENGINE UNAVAILABLE';
    }
  }

  // ------------------------------------------------------------------- queue

  /// Starts [tracks] as the queue, at [startIndex].
  Future<void> playCollection(
    List<Track> tracks, {
    int startIndex = 0,
    bool? shuffle,
  }) async {
    final playable = tracks.where((t) => t.id.isNotEmpty).toList();
    if (playable.isEmpty) return;

    if (shuffle != null) shuffleEnabled.value = shuffle;

    queue.value = playable;
    final isShuffle = shuffle ?? shuffleEnabled.value;
    final initialIndex = (isShuffle && startIndex == 0 && playable.length > 1)
        ? math.Random().nextInt(playable.length)
        : startIndex.clamp(0, playable.length - 1);
    _queueIndex = initialIndex;
    queueIndex.value = _queueIndex;
    _rebuildShuffleOrder(seedWith: _queueIndex);
    _staged.clear();

    await _startCurrent(prefetchAhead: true);
  }

  Future<void> playTrack(Track track, {List<Track>? context}) async {
    final rest = context?.where((t) => t.id != track.id).toList() ?? const <Track>[];
    queue.value = [track, ...rest];
    _queueIndex = 0;
    queueIndex.value = 0;
    _rebuildShuffleOrder(seedWith: 0);
    _staged.clear();
    await _startCurrent(prefetchAhead: true);
  }

  /// Inserts directly after the current track.
  Future<void> playNext(Track track) async {
    final list = [...queue.value];
    if (list.isEmpty) {
      await playTrack(track);
      return;
    }
    list.insert(_queueIndex + 1, track);
    queue.value = list;
    _rebuildShuffleOrder(seedWith: _queueIndex);
  }

  /// Appends to the end of the queue.
  Future<void> addToQueue(Track track) async {
    final list = [...queue.value];
    if (list.isEmpty) {
      await playTrack(track);
      return;
    }
    list.add(track);
    queue.value = list;
    _rebuildShuffleOrder(seedWith: _queueIndex);
  }

  Future<void> addAllToQueue(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    if (queue.value.isEmpty) {
      await playCollection(tracks);
      return;
    }
    queue.value = [...queue.value, ...tracks];
    _rebuildShuffleOrder(seedWith: _queueIndex);
  }

  Future<void> removeFromQueue(int index) async {
    final list = [...queue.value];
    if (index < 0 || index >= list.length) return;
    final removingCurrent = index == _queueIndex;
    list.removeAt(index);
    queue.value = list;

    if (list.isEmpty) {
      await _teardownVoice();
      currentTrack.value = null;
      duration.value = Duration.zero;
      position.value = Duration.zero;
      isPlaying.value = false;
      _bump();
      return;
    }

    if (index < _queueIndex) _queueIndex--;
    if (removingCurrent) {
      _queueIndex = _queueIndex.clamp(0, list.length - 1);
      queueIndex.value = _queueIndex;
      await _startCurrent();
      return;
    }
    _queueIndex = _queueIndex.clamp(0, list.length - 1);
    queueIndex.value = _queueIndex;
    _rebuildShuffleOrder(seedWith: _queueIndex);
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final list = [...queue.value];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    var target = newIndex;
    if (target < 0) target = 0;
    if (target >= list.length) target = list.length - 1;

    final playing = list[_queueIndex];
    final moved = list.removeAt(oldIndex);
    list.insert(target, moved);
    queue.value = list;
    _queueIndex = list.indexWhere((t) => t.id == playing.id);
    if (_queueIndex < 0) _queueIndex = 0;
    queueIndex.value = _queueIndex;
    _rebuildShuffleOrder(seedWith: _queueIndex);
  }

  Future<void> clearQueue() async {
    final current = currentTrack.value;
    if (current == null) {
      queue.value = const [];
      return;
    }
    queue.value = [current];
    _queueIndex = 0;
    queueIndex.value = 0;
    _rebuildShuffleOrder(seedWith: 0);
  }

  /// Jumps to a specific queue position.
  Future<void> jumpTo(int index) async {
    final list = queue.value;
    if (index < 0 || index >= list.length) return;
    _queueIndex = index;
    queueIndex.value = index;
    final pos = _shuffleOrder.indexOf(index);
    if (pos >= 0) _shufflePosition = pos;
    await _startCurrent(prefetchAhead: true);
  }

  void _rebuildShuffleOrder({required int seedWith}) {
    if (queue.value.isEmpty) {
      _shuffleOrder = const [];
      _shufflePosition = 0;
      return;
    }
    final indices = List<int>.generate(queue.value.length, (i) => i);
    if (shuffleEnabled.value) {
      indices.shuffle(math.Random());
      // Keep the currently playing track at the head so toggling shuffle never
      // yanks the listener to a different song.
      indices.remove(seedWith);
      indices.insert(0, seedWith);
      _shufflePosition = 0;
    }
    _shuffleOrder = indices;
  }

  // --------------------------------------------------------------- transport

  Future<void> togglePlayPause() async =>
      isPlaying.value ? await pause() : await resume();

  Future<void> pause() async {
    if (_crossfading) _abortCrossfade();
    final handle = _handle;
    if (_live(handle)) {
      _soloud.setPause(handle!, true);
      _orbitClock.stop();
      isPlaying.value = false;
      _bump();
    }
  }

  Future<void> resume() async {
    if (!_engineReady) await initEngine();
    if (_live(_handle)) {
      _soloud.setPause(_handle!, false);
      isPlaying.value = true;
      if (is8DEnabled.value) {
        if (!_orbitClock.isRunning) _orbitClock.start();
        _startOrbitIfNeeded();
      }
      // A paused stream can resume onto a dead connection (a stall in the
      // background, or a seek made while paused), so give it the same
      // "sound shortly or the download route takes over" deadline a live
      // seek gets. A healthy stream clears it within a second.
      if (_streaming && _streamStarted && position.value > Duration.zero) {
        _seekTarget = position.value;
        _seekDeadline = DateTime.now().add(const Duration(seconds: 8));
        _seekProgress = _streamSession?.bytesAvailable;
        _seekExtensions = 0;
      }
      _bump();
      return;
    }
    // Nothing loaded (fresh launch) — start whatever the queue holds.
    if (queue.value.isNotEmpty) await _startCurrent();
  }

  /// A drag tick on the scrubber: starts fetching the bytes around [target]
  /// while the finger is still down. By the time the finger lifts, the seek's
  /// first read is served from disk — the connection is no longer opened after
  /// release, which is what makes a drag feel like it fetches nothing.
  ///
  /// Safe on every tick: it never touches the engine, never runs while the
  /// stream is already starved, and repositions at most once per 300 ms and
  /// 1.5 s of audio. The transfer itself refuses to move to bytes it already
  /// holds, and refuses to move at all once the file is complete (that seek is
  /// a plain disk read already).
  void hintSeek(Duration target) {
    if (_disposed || !_streaming) return;
    final session = _streamSession;
    if (session == null || session.isComplete) return;
    if (!_live(_handle)) return;
    // A starved stream must never be diverted further.
    if (isBuffering.value) return;

    // The live playback keeps look-ahead priority: only divert the connection
    // while the decoded buffer is comfortably ahead, so the gesture can never
    // make playing audio stutter.
    if (isPlaying.value &&
        buffered.value - position.value < const Duration(seconds: 5)) {
      return;
    }

    // One reposition per 300 ms, and only when the target actually moved.
    final last = _hintTarget;
    if (last != null &&
        (target - last).inMilliseconds.abs() < 1500) {
      return;
    }
    final now = DateTime.now();
    if (_hintAt != null &&
        now.difference(_hintAt!) < const Duration(milliseconds: 300)) {
      return;
    }
    _hintTarget = target;
    _hintAt = now;

    final index = _streamIndex;
    if (index != null) {
      final byte = index.adtsOffsetAtTime(target);
      session.jumpTo(index.windowAt(byte, _feedWindowBytes).fileStart);
      return;
    }
    final total = session.total ?? 0;
    final totalMs = duration.value.inMilliseconds;
    if (total <= 0 || totalMs <= 0) return;
    final fraction = (target.inMilliseconds / totalMs).clamp(0.0, 1.0);
    session.jumpTo((total * fraction).round());
  }

  Future<void> seek(Duration target) async {
    if (_crossfading) _abortCrossfade();
    final total = duration.value;
    var clamped = target;
    if (total > Duration.zero && clamped > total) clamped = total;
    if (clamped < Duration.zero) clamped = Duration.zero;

    _seekSuppressedUntil = DateTime.now().add(const Duration(milliseconds: 300));
    position.value = clamped;
    _bump();

    // Any pending re-seek watchdog belongs to the previous gesture.
    _seekDeadline = null;
    _seekTarget = null;

    // A handoff, a rebuild or a migration to disk is already running: keep
    // only the newest intent. It is applied before that operation returns, so
    // no drag is lost.
    if (_handoffToDownload || _restartingStream || _switchingToLocal) {
      _pendingSeekTarget = clamped;
      return;
    }

    final track = currentTrack.value;
    if (track == null) return;

    if (_streaming) {
      // 1. A target inside the engine's decoded window is a native,
      //    allocation-free re-anchor of the SAME voice — it can neither
      //    restart the song nor leave the player silent. It is tried first
      //    whatever else is on disk, because a live session and a complete
      //    one share the same window machinery.
      if (_seekInBuffer(clamped)) {
        if (is8DEnabled.value) {
          _orbitClock
            ..stop()
            ..reset()
            ..start();
        }
        return;
      }

      // 2. Outside the window a complete copy on disk is the honest answer:
      //    one silent swap to a native file voice, and every later seek is a
      //    direct disk move. When the swap cannot be trusted the live stream
      //    is left untouched and the rebuild below takes over.
      final localPath = _streamSession?.path ?? _completedPath?.call(track);
      if (localPath != null &&
          localPath.isNotEmpty &&
          await _switchToLocalFile(localPath, seekTo: clamped)) {
        return;
      }
      if (_disposed) return;

      // 3. A live transfer rebuilds the stream at the target — sequentially,
      //    the way a track change builds a voice, so it is just as safe — and
      //    only if that fails does the download route take over. Every branch
      //    ends with sound.
      if (await _restartStreamAt(track, clamped)) {
        final queued = _pendingSeekTarget;
        _pendingSeekTarget = null;
        if (queued != null && queued != clamped) await seek(queued);
        return;
      }
      if (_disposed) return;
      await _handoffStreamToDownload(track, clamped);
      return;
    }

    // 4. A loaded file voice seeks natively.
    final handle = _handle;
    if (_live(handle)) {
      try {
        _soloud.seek(handle!, clamped);
        if (is8DEnabled.value) {
          _orbitClock
            ..stop()
            ..reset()
            ..start();
        }
      } catch (e) {
        debugPrint('seek failed: $e');
      }
    }
  }

  /// Repositions the play head inside the engine's already-decoded window.
  ///
  /// The pull buffer holds a few seconds of decoded PCM, and a target inside
  /// that window is a native, allocation-free seek: no source is rebuilt, no
  /// feed is disturbed, so it can neither leave the player silent nor restart
  /// the song. Returns false when the target is outside the window — the
  /// caller then migrates to the complete file, rebuilds the stream, or hands
  /// off to the download route.
  bool _seekInBuffer(Duration target) {
    final handle = _handle;
    final source = _source;
    if (!_streaming || !_live(handle) || source == null) return false;
    try {
      final range = _soloud.getPullBufferTimeRange(source);
      final windowStart = _streamTimeOffset + range.startTime;
      final windowEnd = _streamTimeOffset + range.endTime;
      const margin = Duration(seconds: 1);
      // Refuse a window too shallow to land inside without falling off an edge.
      if (windowEnd - windowStart < margin * 3) return false;
      if (target <= windowStart + margin) return false;
      if (target >= windowEnd - margin) return false;
      _soloud.seek(handle!, target - _streamTimeOffset);
      _streamStumbles = 0;
      return true;
    } catch (e) {
      debugPrint('in-buffer seek unavailable: $e');
      return false;
    }
  }

  /// Rebuilds the pull stream around [target], sequentially.
  ///
  /// The decoded window is re-anchored at the target frame and the feeds
  /// continue from the matching byte offset, so playback picks up a second or
  /// so after the drag instead of waiting for the whole download. The old
  /// voice is stopped and disposed *before* the next stream is created — the
  /// same order every track change uses — so nothing native is ever churned
  /// under a live voice. Returns false when no new voice came up; the caller
  /// then owns the fallback.
  Future<bool> _restartStreamAt(Track track, Duration target) async {
    if (_restartingStream) return false;
    _restartingStream = true;
    try {
      final session = _streamSession;
      final index = _streamIndex;
      if (session == null) return false;

      final int startByteOffset;
      final Duration actualStartTime;
      final int remainingAudioBytes;
      if (index != null) {
        startByteOffset = index.adtsOffsetAtTime(target);
        actualStartTime = index.timeAtAdtsOffset(startByteOffset);
        remainingAudioBytes = (index.totalAdtsBytes - startByteOffset)
            .clamp(1024, index.totalAdtsBytes);
      } else {
        final total = session.total ?? 1;
        final totalMs = duration.value.inMilliseconds <= 0
            ? 1
            : duration.value.inMilliseconds;
        final fraction = (target.inMilliseconds / totalMs).clamp(0.0, 1.0);
        startByteOffset = (total * fraction).round();
        actualStartTime = target;
        remainingAudioBytes = (total - startByteOffset).clamp(1024, total);
      }

      final wasPlaying = isPlaying.value;

      // The old voice's start-up watchdog belongs to the retired stream; the
      // rebuilt one gets the seek deadline below instead.
      _streamWatchdog?.cancel();
      _streamWatchdog = null;

      // Retire the old voice completely first: cancel its finish listener,
      // stop it, dispose its source. Only then is its successor built.
      await _finishSub?.cancel();
      _finishSub = null;
      final oldHandle = _handle;
      _handle = null;
      if (_live(oldHandle)) {
        try {
          await _soloud.stop(oldHandle!);
        } catch (e) {
          debugPrint('stream stop failed: $e');
        }
      }
      final oldSource = _source;
      _source = null;
      if (oldSource != null) {
        try {
          await _soloud.disposeSource(oldSource);
        } catch (e) {
          debugPrint('stream dispose failed: $e');
        }
      }
      if (_disposed || !_streaming) return false;

      // Commit the new window; the epoch bump retires feeds from the previous
      // incarnation that were still in flight.
      _streamEpoch++;
      _streamByteOffset = startByteOffset;
      _streamTimeOffset = actualStartTime;
      _feedsInFlight.clear();
      _streamStumbles = 0;
      _streamStarted = false;

      // Reposition the transfer so the first read returns the target frame
      // without waiting for the pump to walk there.
      if (index != null) {
        final window = index.windowAt(startByteOffset, _feedWindowBytes);
        session.jumpTo(window.fileStart);
      } else {
        session.jumpTo(startByteOffset);
      }

      AudioSource? built;
      SoundHandle? handle;
      try {
        built = _soloud.setPullBufferStream(
          audioSizeBytes: remainingAudioBytes,
          format: BufferType.auto,
          bufferSizeBytes: _streamBufferBytes,
          bufferTriggerPosition: 0.75,
          sampleRate: index?.sampleRate ?? 44100,
          channels: (index?.channels ?? 2) == 1
              ? Channels.mono
              : Channels.stereo,
          onMoreDataIsNeeded: (offset) => unawaited(_feedStream(offset)),
          onBuffering: (buffering, handle, time) {
            if (_disposed || !_streaming) return;
            isBuffering.value = buffering;
            if (!buffering) _streamStarted = true;
            _bump();
          },
          onAudioDuration: (seconds) {},
        );
        handle = _soloud.play3d(built, 0, 0, 1, volume: 1);
      } catch (e) {
        debugPrint('stream rebuild failed: $e');
      }

      if (built == null || handle == null || !_live(handle)) {
        if (built != null) {
          try {
            await _soloud.disposeSource(built);
          } catch (_) {}
        }
        return false;
      }

      _source = built;
      _handle = handle;
      _finishSub = built.allInstancesFinished.listen((_) => _notifyEnd());
      _soloud.set3dSourceMinMaxDistance(handle, 1, 8);
      _soloud.set3dSourceAttenuation(handle, 1, 1);
      if (!wasPlaying) _soloud.setPause(handle, true);
      if (is8DEnabled.value) _apply8DToActiveVoice();

      position.value = actualStartTime;
      _seekSuppressedUntil =
          DateTime.now().add(const Duration(milliseconds: 300));
      isBuffering.value = true;
      _bump();

      // Silent until the deadline means the rebuilt stream is not coming:
      // the watchdog hands the position to the download route instead.
      if (wasPlaying) {
        _seekTarget = actualStartTime;
        _seekDeadline = DateTime.now().add(const Duration(seconds: 6));
        _seekProgress = session.bytesAvailable;
        _seekExtensions = 0;
      }
      return true;
    } finally {
      _restartingStream = false;
    }
  }

  /// The honest answer to a streaming seek the decoded window cannot serve:
  /// retire the pull stream cleanly and let the proven download route take the
  /// track over at [target]. The transfer the user already started keeps
  /// running, so the wait is usually just the remainder of one download — and
  /// unlike a rebuilt stream, this path can never come up silent.
  Future<void> _handoffStreamToDownload(Track track, Duration target) async {
    if (_switching) return; // the queue is changing; this seek is moot
    _handoffToDownload = true;
    final wasPlaying = isPlaying.value;
    debugPrint('progressive: seek outside the decoded window → download route '
        'at ${target.inSeconds}s');
    try {
      // The restart must land on the file, never re-enter live streaming.
      _forceClassicNextStart = true;
      isBuffering.value = true;
      _bump();

      await _teardownVoice();
      if (_disposed) return;
      buffered.value = Duration.zero;
      bufferFraction.value = null;
      await _startCurrent();
      if (_disposed) return;
      if (currentTrack.value?.id != track.id) return;

      // The download route is live: ordinary seeks work again, and the newest
      // intent (a queued drag beats the one this handoff started with) lands
      // on the disk file natively.
      _handoffToDownload = false;
      final queued = _pendingSeekTarget;
      _pendingSeekTarget = null;
      await seek(queued ?? target);
      // A scrub while paused must not turn into playback behind the user.
      if (!wasPlaying && isPlaying.value) await pause();
    } finally {
      _handoffToDownload = false;
    }
  }

  /// Replaces a live pull stream with the complete file at [path], landing on
  /// the newest requested position *silently*.
  ///
  /// The new voice is born paused, so position zero is never audible, and only
  /// a voice that really landed at the target is adopted — a disk seek that
  /// stayed at zero would otherwise restart the song from its first second the
  /// moment the stream is retired. When anything fails the live stream is left
  /// exactly as it was, so the caller keeps its whole fallback chain (ninth
  /// law). Re-entrant calls are ignored. Returns true when the file voice took
  /// over.
  Future<bool> _switchToLocalFile(String path, {required Duration seekTo}) async {
    if (_switchingToLocal) return false;
    _switchingToLocal = true;
    // The old stream keeps playing while the file loads, and its position is
    // not where the user asked to be: the readout stays parked on the target
    // instead of drifting with the outgoing playhead.
    _seekSuppressedUntil = DateTime.now().add(const Duration(seconds: 30));
    var adoptedVoice = false;
    AudioSource? loaded;
    SoundHandle? loadedHandle;
    try {
      final epoch = _streamEpoch;
      final trackId = currentTrack.value?.id;
      final wasPlaying = isPlaying.value;

      loaded = await _soloud.loadFile(path, mode: LoadMode.disk);
      // The voice may have been retired while the file was loading — a track
      // change, a rebuild, a teardown. Adopting now would clobber a newer one.
      if (_disposed ||
          !_streaming ||
          _streamEpoch != epoch ||
          currentTrack.value?.id != trackId) {
        return false;
      }

      // The newest intent wins: a drag released while the file was loading is
      // answered by this one silent seek instead of being overwritten by it.
      var target = _pendingSeekTarget ?? seekTo;
      _pendingSeekTarget = null;
      final length = _soloud.getLength(loaded);
      if (length > Duration.zero && target > length) target = length;

      // Paused from its first frame: the seek lands while nothing can hear the
      // voice, so a slow disk walk can never play the song from the top.
      final handle = _soloud.play3d(loaded, 0, 0, 1, volume: 1, paused: true);
      if (!_live(handle)) return false;
      loadedHandle = handle;

      _soloud.seek(handle, target);
      // A seek that silently stayed at zero would restart the song once the
      // stream is retired. Trust only a real move.
      final landed = _soloud.getPosition(handle);
      if (landed + _localSeekSlack < target) {
        debugPrint('_switchToLocalFile: seek stayed at '
            '${landed.inMilliseconds}ms (wanted ${target.inMilliseconds}ms) '
            '— keeping the stream');
        return false;
      }

      // Point of no return: adopt the positioned voice, then retire the stream
      // in the same turn so no feed can write into a half-migrated player.
      final oldHandle = _handle;
      final oldSource = _source;
      final oldSession = _streamSession;
      final oldSub = _finishSub;
      final adopted = loaded;
      adoptedVoice = true;

      _streamEpoch++;
      _streamSession = null;
      _streamIndex = null;
      _streaming = false;
      _streamByteOffset = 0;
      _streamTimeOffset = Duration.zero;
      _streamWatchdog?.cancel();
      _streamWatchdog = null;
      _seekDeadline = null;
      _seekTarget = null;
      _feedsInFlight.clear();

      _source = adopted;
      _handle = handle;
      loaded = null; // ownership moved: the cleanup must not dispose it
      _soloud.set3dSourceMinMaxDistance(handle, 1, 8);
      _soloud.set3dSourceAttenuation(handle, 1, 1);
      _finishSub = adopted.allInstancesFinished.listen((_) => _onNaturalFinish());

      position.value = target;
      if (length > Duration.zero) duration.value = length;
      buffered.value = duration.value;
      bufferFraction.value = 1.0;

      // Retire the stream first, then unpause the positioned voice: the swap
      // is one handshake, not an overlap of two playheads.
      unawaited(oldSub?.cancel());
      if (_live(oldHandle)) {
        try {
          _soloud.stop(oldHandle!);
        } catch (_) {}
      }
      if (wasPlaying) {
        try {
          _soloud.setPause(handle, false);
        } catch (e) {
          debugPrint('_switchToLocalFile: unpause failed: $e');
        }
      }

      if (is8DEnabled.value) {
        _apply8DToActiveVoice();
        _orbitClock
          ..stop()
          ..reset()
          ..start();
      }

      if (oldSource != null) {
        try {
          await _soloud.disposeSource(oldSource);
        } catch (_) {}
      }
      oldSession?.release();

      _seekSuppressedUntil = DateTime.now().add(const Duration(milliseconds: 300));
      _bump();
      return true;
    } catch (e) {
      debugPrint('_switchToLocalFile failed: $e');
      return false;
    } finally {
      // Nothing was adopted: the orphan voice and source go away, and the live
      // stream keeps playing as if this never happened.
      if (!adoptedVoice) {
        final orphan = loaded;
        if (orphan != null) {
          final handle = loadedHandle;
          if (handle != null && _live(handle)) {
            try {
              _soloud.stop(handle);
            } catch (_) {}
          }
          try {
            await _soloud.disposeSource(orphan);
          } catch (_) {}
        }
        _seekSuppressedUntil = null;
      }
      _switchingToLocal = false;
    }
  }

  Future<void> skipToNext() async {
    if (queue.value.isEmpty) return;
    final next = _peekNextIndex();
    if (next == null) {
      await pause();
      await seek(Duration.zero);
      return;
    }
    _queueIndex = next;
    queueIndex.value = next;
    await _startCurrent(prefetchAhead: true);
  }

  Future<void> skipToPrevious() async {
    if (queue.value.isEmpty) return;

    // Standard player behaviour: restarts the song unless you are near the top.
    if (position.value.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    final previous = _peekPreviousIndex();
    if (previous == null) {
      await seek(Duration.zero);
      return;
    }
    _queueIndex = previous;
    queueIndex.value = previous;
    await _startCurrent();
  }

  int? _peekNextIndex() {
    if (queue.value.isEmpty) return null;

    if (shuffleEnabled.value && queue.value.length > 1) {
      if (_shuffleOrder.length != queue.value.length) {
        _rebuildShuffleOrder(seedWith: _queueIndex);
      }
      if (_shufflePosition + 1 < _shuffleOrder.length) {
        return _shuffleOrder[_shufflePosition + 1];
      }
      // Reached the end of the shuffled run: pick another random track from the
      // playlist so after the song is over it randomly selects another track continuously!
      final candidates = List<int>.generate(queue.value.length, (i) => i)..remove(_queueIndex);
      if (candidates.isNotEmpty) {
        return candidates[math.Random().nextInt(candidates.length)];
      }
      return _shuffleOrder.isNotEmpty ? _shuffleOrder.first : 0;
    }

    if (_queueIndex + 1 < queue.value.length) return _queueIndex + 1;
    if (repeatMode.value == RepeatMode.all) return 0;
    return null;
  }

  int? _peekPreviousIndex() {
    if (queue.value.isEmpty) return null;

    if (shuffleEnabled.value && queue.value.length > 1) {
      if (_shuffleOrder.length != queue.value.length) {
        _rebuildShuffleOrder(seedWith: _queueIndex);
      }
      if (_shufflePosition - 1 >= 0) return _shuffleOrder[_shufflePosition - 1];
      return _shuffleOrder.isNotEmpty ? _shuffleOrder.last : 0;
    }

    if (_queueIndex - 1 >= 0) return _queueIndex - 1;
    if (repeatMode.value == RepeatMode.all) return queue.value.length - 1;
    return null;
  }

  void _advanceShuffleCursor() {
    if (!shuffleEnabled.value) return;
    final pos = _shuffleOrder.indexOf(_queueIndex);
    if (pos >= 0) _shufflePosition = pos;
  }

  // ------------------------------------------------------------------ cycle

  // ------------------------------------------------------------ instant play

  /// Starts [track] from a live byte source: the container is indexed (MP4) or
  /// passed through raw (MP3/FLAC/Ogg/WAV), the engine gets a pull-buffer
  /// stream, and bytes are fed as it asks for them. Returns `false` when the
  /// classic route must be used instead.
  ///
  /// Every failure path here is a *fall back*, never an error: a container the
  /// demuxer does not understand, a server without a length header, a codec
  /// that is not AAC-LC. The listener hears the song either way — it just takes
  /// the download route.
  Future<bool> _startProgressive(Track track) async {
    final open = _openStream;
    if (open == null) return false;
    if (!_settings.value.instantStart) return false;
    if (_streamFailed.contains(track.id)) return false;

    StreamSource? resolved;
    try {
      resolved = await open(track);
    } catch (e) {
      debugPrint('stream open failed for ${track.id}: $e');
      return false;
    }
    if (resolved == null) return false;
    if (_disposed) {
      resolved.session.release();
      return false;
    }

    final session = resolved.session;
    final total = session.total;
    if (total == null || total <= 0) {
      session.release();
      return false;
    }

    // Two shapes of stream are supported. An **MP4** is indexed here and its
    // AAC frames are repacked into ADTS by Musify, because the engine cannot
    // read an MP4 container incrementally. A **raw elementary stream** (the
    // catalogue's older `_96.mp3` rungs, or any file already in the vault that
    // the engine decodes natively) needs no repacking at all: its bytes go to
    // the engine exactly as they arrive.
    final headEnd = math.min(96 * 1024, total);
    final head = await session.read(0, headEnd);
    var index = head == null ? null : Mp4AacIndex.parse(head, fileLength: total);
    if (index == null && head != null && total > headEnd) {
      // `moov` written last: the sample table is in the tail instead.
      final tail = await session.read(math.max(0, total - 256 * 1024), total);
      if (tail != null) {
        index = Mp4AacIndex.parseAnywhere(tail, fileLength: total);
      }
    }
    final raw = index == null && head != null && _isRawDecodable(head);
    if (index == null && !raw) {
      debugPrint('progressive: ${track.id} has no usable sample table');
      session.release();
      return false;
    }

    // From here on the progressive path owns the voice.
    _streamSession = session;
    _streamIndex = index;
    _streamByteOffset = 0;
    _streamTimeOffset = Duration.zero;
    _streamStumbles = 0;
    _streamStarted = false;
    _feedsInFlight.clear();
    _streamEpoch++;
    _endNotified = false;
    if (index != null) duration.value = index.duration;
    buffered.value = Duration.zero;
    bufferFraction.value = null;

    final source = _soloud.setPullBufferStream(
      audioSizeBytes: index?.totalAdtsBytes ?? total,
      format: BufferType.auto,
      bufferSizeBytes: _streamBufferBytes,
      bufferTriggerPosition: 0.75,
      sampleRate: index?.sampleRate ?? 44100,
      channels: (index?.channels ?? 2) == 1
          ? Channels.mono
          : Channels.stereo,
      onMoreDataIsNeeded: (offset) => unawaited(_feedStream(offset)),
      onBuffering: (buffering, handle, time) {
        if (_disposed || !_streaming) return;
        isBuffering.value = buffering;
        if (!buffering) _streamStarted = true;
        _bump();
      },
      onAudioDuration: (seconds) {
        if (_disposed || !_streaming || seconds <= 0) return;
        // The sample table is authoritative, but if the engine disagrees by
        // more than a second its own measurement wins: it is what seeks.
        final measured = Duration(microseconds: (seconds * 1000000).round());
        if ((measured - duration.value).inMilliseconds.abs() > 1200) {
          duration.value = measured;
        }
      },
    );

    _source = source;
    _streaming = true;

    final handle = _soloud.play3d(source, 0, 0, 1, volume: 1);
    _handle = handle;
    if (!_live(handle)) {
      _streaming = false;
      _streamSession = null;
      _streamIndex = null;
      _source = null;
      session.release();
      await _soloud.disposeSource(source);
      return false;
    }

    _soloud.set3dSourceMinMaxDistance(handle, 1, 8);
    _soloud.set3dSourceAttenuation(handle, 1, 1);
    if (is8DEnabled.value) _apply8DToActiveVoice();

    _finishSub = source.allInstancesFinished.listen((_) => _notifyEnd());

    isPlaying.value = true;
    isBuffering.value = true;
    _startPositionTimer();
    _startOrbitIfNeeded();
    _advanceShuffleCursor();
    _bump();

    // The first frames should be audible within a second or two. Still silent
    // after this long means the source is not going to work: take the download
    // route rather than leave a spinning player.
    _streamWatchdog?.cancel();
    _streamWatchdog = Timer(const Duration(seconds: 7), () {
      if (_disposed || !_streaming || _streamStarted) return;
      if (currentTrack.value?.id != track.id) return;
      unawaited(_fallBackFromStream(track));
    });

    debugPrint(
      'progressive: ${track.id} '
      '${index == null ? 'raw' : '${index.sampleRate}Hz'} '
      '${(index?.duration ?? track.duration).inSeconds}s '
      '${index?.totalAdtsBytes ?? total}B '
      'from ${resolved.url.isEmpty ? 'disk' : 'network'}',
    );
    return true;
  }

  /// Routes an engine byte request: an MP4 is repacked into ADTS on the way,
  /// a raw elementary stream is handed over exactly as it arrived.
  Future<void> _feedStream(int offset) =>
      _streamIndex == null ? _feedRaw(offset) : _feedFrames(offset);

  /// True when the engine's own decoder can read these bytes frame-for-frame —
  /// MP3, FLAC, Ogg or WAV. An MP4 is excluded: the demuxer already refused it,
  /// and the engine cannot index an MP4 either, so the classic route is the
  /// honest answer for it.
  bool _isRawDecodable(Uint8List head) {
    if (!MediaCache.looksLikeAudio(head: head)) return false;
    if (head.length >= 8) {
      // 'f' 't' 'y' 'p' at bytes 4..7: an MP4 whose table could not be read.
      if (head[4] == 0x66 &&
          head[5] == 0x74 &&
          head[6] == 0x79 &&
          head[7] == 0x70) {
        return false;
      }
    }
    return true;
  }

  /// Feeds the engine raw bytes that begin at file offset [offset].
  Future<void> _feedRaw(int offset) async {
    final session = _streamSession;
    final source = _source;
    final epoch = _streamEpoch;
    if (!_streaming || _disposed) return;
    if (session == null || source == null) return;
    final total = session.total;
    if (total == null || offset < 0) return;
    final fileOffset = _streamByteOffset + offset;
    if (fileOffset >= total) {
      // The engine has read everything there is — say so, so the queue can
      // advance instead of waiting for bytes that do not exist.
      _reportStreamProgress(session);
      return;
    }
    if (!_feedsInFlight.add(fileOffset)) return;

    try {
      final end = math.min(fileOffset + _feedWindowBytes, total);
      final bytes = await session.read(fileOffset, end);
      // The window may have been replaced while this read was in flight
      // (a seek, a migration to disk): the bytes are stale, drop them.
      if (_disposed || !_streaming || epoch != _streamEpoch) return;
      if (bytes == null || bytes.isEmpty) {
        _onFeedFailed(fileOffset, 'no bytes');
        return;
      }
      _soloud.addPullBufferDataStream(source, bytes, offset: offset);
      _streamStumbles = 0;
      _reportStreamProgress(session);
    } catch (e) {
      _onFeedFailed(fileOffset, '$e');
    } finally {
      _feedsInFlight.remove(fileOffset);
    }
  }

  /// Feeds the engine the frames that begin at [offset].
  Future<void> _feedFrames(int offset) async {
    final session = _streamSession;
    final index = _streamIndex;
    final source = _source;
    final epoch = _streamEpoch;
    if (!_streaming || _disposed) return;
    if (session == null || index == null || source == null) return;
    final targetAdtsOffset = _streamByteOffset + offset;
    if (targetAdtsOffset < 0 || targetAdtsOffset >= index.totalAdtsBytes) return;
    if (!_feedsInFlight.add(targetAdtsOffset)) return;

    try {
      final window = index.windowAt(targetAdtsOffset, _feedWindowBytes);
      // Mapped against the window that was committed *now*: a seek during the
      // read must not re-base this chunk into the new stream.
      final bufferOffset = window.adtsOffset - _streamByteOffset;
      final bytes = await session.read(window.fileStart, window.fileEnd);
      // The voice may have been torn down while this read was in flight; a
      // `null` then means "the session was released", not "the stream broke".
      if (_disposed || !_streaming || epoch != _streamEpoch) return;
      if (bytes == null) {
        _onFeedFailed(targetAdtsOffset, 'no bytes');
        return;
      }
      final adts = index.assemble(window, bytes);
      if (adts.isEmpty) {
        _onFeedFailed(targetAdtsOffset, 'empty window');
        return;
      }
      if (bufferOffset >= 0) {
        _soloud.addPullBufferDataStream(source, adts, offset: bufferOffset);
      }
      _streamStumbles = 0;
      _reportStreamProgress(session);
    } catch (e) {
      _onFeedFailed(targetAdtsOffset, '$e');
    } finally {
      _feedsInFlight.remove(targetAdtsOffset);
    }
  }

  void _onFeedFailed(int offset, String reason) {
    _streamStumbles++;
    debugPrint('stream feed failed at $offset ($reason)');
    if (_streamStarted) {
      // Mid-song: the queue keeps its place and the engine retries; say so
      // instead of pretending everything is fine.
      if (_streamStumbles == 3) {
        errorText.value = 'STREAM INTERRUPTED';
        _bump();
      }
      return;
    }
    if (_streamStumbles >= 3) {
      final track = currentTrack.value;
      if (track != null) unawaited(_fallBackFromStream(track));
    }
  }

  /// Shows transfer progress in the same readout the download path used.
  void _reportStreamProgress(StreamSession session) {
    if (_streamStarted) return;
    final total = session.total;
    if (total == null || total <= 0) return;
    final fraction = (session.bytesAvailable / total).clamp(0.0, 1.0);
    bufferFraction.value = fraction;
    final length = duration.value;
    if (length > Duration.zero) buffered.value = length * fraction;
  }

  /// The stream never produced sound: remember that, drop the voice and load
  /// the track the classic way, landing back on [startAt] when it is known.
  Future<void> _fallBackFromStream(
    Track track, {
    Duration startAt = Duration.zero,
  }) async {
    if (_disposed) return;
    if (currentTrack.value?.id != track.id) return;
    _streamFailed.add(track.id);
    _streamWatchdog?.cancel();
    _streamWatchdog = null;
    _seekDeadline = null;
    _seekTarget = null;
    debugPrint('progressive: falling back to the download route for ${track.id}');
    await _teardownVoice();
    if (_disposed) return;
    buffered.value = Duration.zero;
    bufferFraction.value = null;
    await _startCurrent();
    if (_disposed) return;
    if (currentTrack.value?.id != track.id) return;
    if (startAt > Duration.zero) await seek(startAt);
  }

  /// Loads and plays [queue.value][_queueIndex].
  Future<void> _startCurrent({bool prefetchAhead = false}) async {
    // Consumed on entry — before any guard — so the flag can never leak into
    // an unrelated start.
    final forceClassic = _forceClassicNextStart;
    _forceClassicNextStart = false;

    final list = queue.value;
    if (list.isEmpty) return;
    if (_switching) return;

    _switching = true;
    try {
      final track = list[_queueIndex.clamp(0, list.length - 1)];
      await initEngine();
      if (!_engineReady) {
        errorText.value = 'AUDIO ENGINE UNAVAILABLE';
        return;
      }

      await _teardownVoice();

      currentTrack.value = track;
      position.value = Duration.zero;
      duration.value = track.duration;
      buffered.value = Duration.zero;
      bufferFraction.value = null;
      errorText.value = null;
      isBuffering.value = true;
      _bump();

      // Instant play first: index the MP4 and stream its AAC frames. A `false`
      // here means the track could not be streamed (and nothing was changed),
      // so the staged download below takes over. A pending seek handoff forces
      // the download route: restarting the live stream at byte zero would undo
      // the position the user picked.
      if (!forceClassic && await _startProgressive(track)) {
        if (prefetchAhead && _settings.value.prefetchNext) {
          unawaited(_prefetchNext());
        }
        return;
      }

      final source = await _resolveFor(track);
      if (source == null) {
        errorText.value = 'TRACK UNAVAILABLE — SKIPPING';
        isBuffering.value = false;
        _bump();
        _switching = false;
        // A dead catalogue entry must not stall the queue.
        await _autoSkipAfterFailure();
        return;
      }

      final loaded = source.isLocalFile
          ? await _soloud.loadFile(source.path, mode: LoadMode.disk)
          : await _soloud.loadUrl(source.path, mode: LoadMode.disk);

      if (_disposed) {
        await _soloud.disposeSource(loaded);
        return;
      }

      _source = loaded;

      final length = _soloud.getLength(loaded);
      if (length > Duration.zero) duration.value = length;

      _finishSub = loaded.allInstancesFinished.listen((_) => _onNaturalFinish());

      final handle = _soloud.play3d(loaded, 0, 0, 1, volume: 1);
      _handle = handle;

      if (!_live(handle)) {
        // Non-blocking playback failure: reported, not thrown.
        errorText.value = 'PLAYBACK FAILED';
        isBuffering.value = false;
        _bump();
        return;
      }

      _soloud.set3dSourceMinMaxDistance(handle, 1, 8);
      _soloud.set3dSourceAttenuation(handle, 1, 1);

      if (is8DEnabled.value) _apply8DToActiveVoice();

      isPlaying.value = true;
      isBuffering.value = false;
      buffered.value = length;
      _startPositionTimer();
      _startOrbitIfNeeded();
      _advanceShuffleCursor();
      _bump();

      if (prefetchAhead && _settings.value.prefetchNext) {
        unawaited(_prefetchNext());
      }
    } catch (e, stack) {
      debugPrint('playback failed: $e\n$stack');
      errorText.value = 'PLAYBACK ERROR';
      isBuffering.value = false;
      isPlaying.value = false;
      _bump();
    } finally {
      _switching = false;
    }
  }

  Future<void> _autoSkipAfterFailure() async {
    if (queue.value.length <= 1) return;
    final next = _peekNextIndex();
    if (next == null) return;
    _queueIndex = next;
    queueIndex.value = next;
    // One retry only: a whole dead album should stop, not spin.
    await _startCurrent();
  }

  /// Resolves a playable source, keeping the user informed while bytes move.
  Future<PlayableSource?> _resolveFor(Track track) async {
    try {
      final source = await _resolveSource(
        track,
        onProgress: (fraction) {
          if (_disposed) return;
          bufferFraction.value = fraction;
          final total = duration.value;
          if (fraction != null && total > Duration.zero) {
            buffered.value = total * fraction;
          }
        },
        prefetch: false,
      );
      bufferFraction.value = null;
      return source;
    } catch (e) {
      debugPrint('resolve failed for ${track.id}: $e');
      return null;
    }
  }

  /// Warms the next queue entry so transitions are instant.
  ///
  /// With instant play on, the useful prefetch is a *live transfer*: it warms
  /// the bytes on the wire, and when the transfer is released it keeps running
  /// to completion so the file lands in the cache — no second download, no
  /// doubled bandwidth.
  Future<void> _prefetchNext() async {
    final nextIndex = _peekNextIndex();
    if (nextIndex == null) return;
    final list = queue.value;
    if (nextIndex < 0 || nextIndex >= list.length) return;
    final next = list[nextIndex];
    if (_staged.containsKey(next.id) || next.isDownloaded) return;

    try {
      final open = _openStream;
      if (open != null && _settings.value.instantStart) {
        final stream = await open(next);
        if (stream != null) {
          if (stream.session.isComplete) {
            final path = stream.session.path ?? _completedPath?.call(next);
            if (path != null && path.isNotEmpty) _staged[next.id] = path;
          }
          stream.session.release();
          return;
        }
      }

      final source = await _resolveSource(next, prefetch: true);
      if (source != null) _staged[next.id] = source.path;
    } catch (e) {
      debugPrint('prefetch failed for ${next.id}: $e');
    }
  }

  void _onNaturalFinish() {
    if (_disposed || _switching || _crossfading) return;

    if (repeatMode.value == RepeatMode.one) {
      unawaited(_replayCurrent());
      return;
    }
    unawaited(skipToNext());
  }

  /// Ends the current track exactly once, whoever noticed first — the finish
  /// callback or the position loop that saw the buffer run dry.
  void _notifyEnd() {
    if (_endNotified || _disposed) return;
    _endNotified = true;
    _onNaturalFinish();
  }

  Future<void> _replayCurrent() async {
    final handle = _handle;
    if (_live(handle)) {
      _soloud.seek(handle!, Duration.zero);
      _soloud.setPause(handle!, false);
      position.value = Duration.zero;
      isPlaying.value = true;
      _bump();
      return;
    }
    await _startCurrent();
  }

  /// Stops and releases the current voice and source.
  Future<void> _teardownVoice() async {
    _positionTimer?.cancel();
    await _finishSub?.cancel();
    _finishSub = null;

    // Streaming state belongs to the voice: drop it before the source goes.
    _streamWatchdog?.cancel();
    _streamWatchdog = null;
    _streaming = false;
    _streamStarted = false;
    _streamIndex = null;
    _streamByteOffset = 0;
    _streamTimeOffset = Duration.zero;
    _streamStumbles = 0;
    _streamEpoch++;
    _seekDeadline = null;
    _seekTarget = null;
    _feedsInFlight.clear();
    final session = _streamSession;
    _streamSession = null;
    session?.release();

    final handle = _handle;
    _handle = null;
    if (_live(handle)) {
      try {
        await _soloud.stop(handle!);
      } catch (e) {
        debugPrint('stop failed: $e');
      }
    }

    final source = _source;
    _source = null;
    if (source != null && _soloud.isInitialized) {
      try {
        await _soloud.disposeSource(source);
      } catch (e) {
        debugPrint('dispose failed: $e');
      }
    }

    _incomingHandle = null;
    _incomingSource = null;
    _hintTarget = null;
    _hintAt = null;
  }

  Future<void> stop() async {
    await _teardownVoice();
    isPlaying.value = false;
    position.value = Duration.zero;
    _bump();
  }

  // ------------------------------------------------------------ position loop

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_disposed) return;
      if (_seekSuppressedUntil != null && DateTime.now().isBefore(_seekSuppressedUntil!)) {
        return;
      }
      final handle = _handle;
      if (!_live(handle)) return;
      try {
        final current = _soloud.getPosition(handle!);
        final actualPos = _streaming ? (_streamTimeOffset + current) : current;
        position.value = actualPos;
        _checkSeekWatchdog(actualPos);
        final playing = !_soloud.getPause(handle);
        if (playing != isPlaying.value) {
          isPlaying.value = playing;
          if (playing && is8DEnabled.value) {
            if (!_orbitClock.isRunning) _orbitClock.start();
            _startOrbitIfNeeded();
          } else if (!playing) {
            _orbitClock.stop();
          }
          _bump();
        }
        if (playing && current > const Duration(milliseconds: 200) && isBuffering.value) {
          isBuffering.value = false;
          _streamStarted = true;
          _bump();
        }
        if (_streaming) _pollStreamBuffer();
        _maybeCrossfade(actualPos);
      } catch (e) {
        debugPrint('position poll failed: $e');
      }
    });
  }

  /// A re-seek that produced no audio before its deadline hands the position
  /// to the download route at the exact spot the scrubber was dropped — slow,
  /// but the listener always ends up where they asked to be.
  void _checkSeekWatchdog(Duration actualPos) {
    final deadline = _seekDeadline;
    if (deadline == null) return;
    final target = _seekTarget ?? Duration.zero;
    if (actualPos > target + const Duration(milliseconds: 700)) {
      // Sound is flowing — the stream caught up to the target.
      _seekDeadline = null;
      _seekTarget = null;
      _seekProgress = null;
      _seekExtensions = 0;
      return;
    }
    if (DateTime.now().isBefore(deadline)) return;

    // Bytes still arriving means the seek is slow, not lost: the first window
    // is on its way over a live connection, and abandoning it for the
    // whole-file route would wait longer still. Two extensions, then the
    // guarantee takes over.
    final covered = _streamSession?.bytesAvailable;
    if (covered != null &&
        _seekProgress != null &&
        covered > _seekProgress! &&
        _seekExtensions < 2) {
      _seekExtensions++;
      _seekProgress = covered;
      _seekDeadline = DateTime.now().add(const Duration(seconds: 5));
      return;
    }

    _seekDeadline = null;
    _seekTarget = null;
    _seekProgress = null;
    _seekExtensions = 0;
    if (!isPlaying.value) return;
    final track = currentTrack.value;
    // The handoff retires the silent stream and lands on the download route at
    // the target — without blacklisting the track's streaming for the session.
    if (track != null) unawaited(_handoffStreamToDownload(track, target));
  }

  /// Mirrors the engine's decoded-buffer window into the progress readout, and
  /// notices a pull stream that ran to its end without a finish callback.
  void _pollStreamBuffer() {
    final source = _source;
    if (source == null) return;
    final total = duration.value;
    try {
      final session = _streamSession;
      if (session != null && session.isComplete && total > Duration.zero) {
        // The whole file is on disk, so every remaining read is a plain disk
        // read on the SAME pull voice. Swapping that voice out mid-play used
        // to restart the song from the top — right after a fresh play for
        // anything already cached, since a complete session reports complete
        // on the very first tick. That swap now waits for the first seek
        // outside the decoded window, where it is silent; here only the
        // readout is refreshed.
        buffered.value = total;
        bufferFraction.value = 1.0;
      } else {
        final range = _soloud.getPullBufferTimeRange(source);
        buffered.value = _streaming ? (_streamTimeOffset + range.endTime) : range.endTime;
        if (total > Duration.zero) {
          bufferFraction.value =
              (buffered.value.inMilliseconds / total.inMilliseconds)
                  .clamp(0.0, 1.0);
        }
      }
    } catch (e) {
      // The source may have just been disposed: the next tick recovers.
    }
    if (isPlaying.value &&
        total > Duration.zero &&
        position.value >= total - const Duration(milliseconds: 400)) {
      // `allInstancesFinished` is not guaranteed for pull streams, so the end
      // of the timeline is treated as the end of the track too.
      _notifyEnd();
    }
  }

  // -------------------------------------------------------------- crossfade

  void _maybeCrossfade(Duration current) {
    final fadeSeconds = _settings.value.crossfadeSeconds;
    if (fadeSeconds <= 0) return;
    if (_crossfading || _switching || _disposed) return;
    if (!isPlaying.value) return;

    final total = duration.value;
    if (total <= Duration.zero) return;

    final remaining = total - current;
    if (remaining > Duration(seconds: fadeSeconds)) return;
    if (remaining < Duration.zero) return;

    final nextIndex = _peekNextIndex();
    if (nextIndex == null) return;
    final list = queue.value;
    if (nextIndex < 0 || nextIndex >= list.length) return;

    final next = list[nextIndex];
    final staged = _staged[next.id] ??
        _completedPath?.call(next) ??
        next.localPath;
    // Crossfading needs the next file *already on disk*; if the prefetch has
    // not landed we let the track end normally rather than stalling the audio.
    if (staged == null || staged.isEmpty) return;

    _crossfading = true;
    unawaited(_runCrossfade(next, nextIndex, staged, Duration(seconds: fadeSeconds)));
  }

  Future<void> _runCrossfade(
    Track next,
    int nextIndex,
    String stagedPath,
    Duration fade,
  ) async {
    try {
      final incoming = await _soloud.loadFile(stagedPath, mode: LoadMode.disk);
      if (_disposed || !_crossfading) {
        await _soloud.disposeSource(incoming);
        return;
      }

      final handle = _soloud.play3d(incoming, 0, 0, 1, volume: 0);
      if (!_live(handle)) {
        await _soloud.disposeSource(incoming);
        _crossfading = false;
        return;
      }

      final outgoingHandle = _handle;
      final outgoingSource = _source;

      _incomingSource = incoming;
      _incomingHandle = handle;

      _soloud.fadeVolume(handle, 1.0, fade);
      if (_live(outgoingHandle)) {
        _soloud.fadeVolume(outgoingHandle!, 0.0, fade);
      }

      // Adopt the incoming track as "now playing" immediately so every surface
      // (mini-player, lyrics, 8D orbit, lock screen) converges at once.
      _handle = handle;
      _source = incoming;
      _incomingHandle = null;
      _incomingSource = null;
      _queueIndex = nextIndex;
      queueIndex.value = nextIndex;
      currentTrack.value = next;
      position.value = Duration.zero;
      duration.value = _soloud.getLength(incoming);
      buffered.value = duration.value;
      _advanceShuffleCursor();
      _bump();

      await _finishSub?.cancel();
      _finishSub = incoming.allInstancesFinished.listen((_) => _onNaturalFinish());

      _soloud.set3dSourceMinMaxDistance(handle, 1, 8);
      if (is8DEnabled.value) _apply8DToActiveVoice();

      _crossfadeTimer?.cancel();
      _crossfadeTimer = Timer(fade + const Duration(milliseconds: 80), () async {
        _crossfading = false;
        if (_live(outgoingHandle)) {
          try {
            await _soloud.stop(outgoingHandle!);
          } catch (_) {}
        }
        if (outgoingSource != null && _soloud.isInitialized) {
          try {
            await _soloud.disposeSource(outgoingSource);
          } catch (_) {}
        }
        if (_settings.value.prefetchNext) unawaited(_prefetchNext());
      });
    } catch (e) {
      debugPrint('crossfade failed, falling back to hard cut: $e');
      _crossfading = false;
      _incomingHandle = null;
      _incomingSource = null;
      _queueIndex = nextIndex;
      queueIndex.value = nextIndex;
      await _startCurrent(prefetchAhead: true);
    }
  }

  /// Aborts an in-flight crossfade (user paused, seeked or skipped).
  void _abortCrossfade() {
    _crossfadeTimer?.cancel();
    _crossfading = false;
    final incomingHandle = _incomingHandle;
    final incomingSource = _incomingSource;
    _incomingHandle = null;
    _incomingSource = null;
    if (_live(incomingHandle)) {
      unawaited(_soloud.stop(incomingHandle!));
    }
    if (incomingSource != null && _soloud.isInitialized) {
      unawaited(_soloud.disposeSource(incomingSource));
    }
  }

  // ---------------------------------------------------------------- 8D audio

  /// The 1-tap hardware toggle.
  Future<void> set8DEnabled(bool enabled) async {
    if (is8DEnabled.value == enabled) return;
    is8DEnabled.value = enabled;
    _bump();

    if (!_engineReady) {
      if (enabled) await initEngine();
    }
    if (enabled) {
      _apply8DParameters();
      _apply8DToActiveVoice();
      _startOrbitIfNeeded();
    } else {
      _stopOrbit();
      _resetSpatialToStereo();
    }
  }

  Future<void> toggle8D() => set8DEnabled(!is8DEnabled.value);

  /// Live calibration from Settings or the Now Playing calibration sheet.
  void update8DParameters({
    double? orbitSeconds,
    double? reverbMix,
    bool? rearLowPass,
  }) {
    final next = _settings.value.copyWith(
      orbitSeconds: orbitSeconds,
      reverbMix: reverbMix,
      rearLowPassEnabled: rearLowPass,
    );
    _settings.update(next);
  }

  void _onSettingsChanged() {
    if (_disposed) return;
    _apply8DParameters();
    _applyEqualizer();
    _applyBassBoost();
    if (!is8DEnabled.value) return;
    _apply8DToActiveVoice();
  }

  /// Configures the global 8D filter chain (stages 2 and 3).
  void _apply8DParameters() {
    if (!_engineReady) return;
    final s = _settings.value;
    try {
      final reverb = _soloud.filters.freeverbFilter;
      if (is8DEnabled.value) {
        if (!reverb.isActive) reverb.activate();
        reverb.roomSize.value = 0.72;
        reverb.damp.value = 0.50;
        reverb.width.value = 1.0;
        reverb.wet.value = 0.0;
        reverb.wet.fadeFilterParameter(
          to: s.reverbMix.clamp(0.0, 0.5),
          time: const Duration(milliseconds: 350),
        );
      }

      final biquad = _soloud.filters.biquadResonantFilter;
      if (is8DEnabled.value && s.rearLowPassEnabled) {
        if (!biquad.isActive) biquad.activate();
        biquad.type.value = 0; // LOWPASS
        biquad.resonance.value = 0.707;
        if (biquad.frequency.value < 100) biquad.frequency.value = 16000;
        biquad.wet.value = 1.0;
      }
    } catch (e) {
      debugPrint('8D parameter application failed: $e');
    }
  }

  /// Re-centres the voice and releases the spatial filters.
  void _resetSpatialToStereo() {
    if (!_engineReady) return;
    try {
      final handle = _handle;
      if (_live(handle)) {
        _soloud.set3dSourcePosition(handle!, 0, 0, 1);
        _soloud.fadePan(handle!, 0.0, const Duration(milliseconds: 300));
      }

      final reverb = _soloud.filters.freeverbFilter;
      if (reverb.isActive) {
        reverb.wet.fadeFilterParameter(to: 0.0, time: const Duration(milliseconds: 300));
        Timer(const Duration(milliseconds: 340), () {
          if (_disposed || is8DEnabled.value) return;
          try {
            if (_soloud.filters.freeverbFilter.isActive) {
              _soloud.filters.freeverbFilter.deactivate();
            }
          } catch (_) {}
        });
      }

      final biquad = _soloud.filters.biquadResonantFilter;
      if (biquad.isActive) biquad.deactivate();
    } catch (e) {
      debugPrint('8D reset failed: $e');
    }
  }

  void _apply8DToActiveVoice() {
    final handle = _handle;
    if (!_live(handle)) return;
    try {
      _soloud.set3dSourcePosition(handle!, 0, 0, 1);
      _soloud.setPan(handle!, 0.0);
      _apply8DParameters();
    } catch (e) {
      debugPrint('8D voice setup failed: $e');
    }
  }

  void _startOrbitIfNeeded() {
    if (!is8DEnabled.value || !isPlaying.value) {
      _orbitTimer?.cancel();
      _orbitTimer = null;
      _orbitClock.stop();
      return;
    }

    if (!_orbitClock.isRunning) {
      _orbitClock.start();
    }

    if (_orbitTimer != null && _orbitTimer!.isActive) return;

    _orbitTimer?.cancel();
    _orbitTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_disposed || !is8DEnabled.value) {
        _stopOrbit();
        return;
      }
      final handle = _handle;
      if (!_live(handle)) return;
      if (!isPlaying.value) {
        if (_orbitClock.isRunning) _orbitClock.stop();
        return;
      }
      if (!_orbitClock.isRunning) {
        _orbitClock.start();
      }

      try {
        final t = _orbitClock.elapsedMilliseconds / 1000.0;
        final period = _settings.value.orbitSeconds.clamp(5.0, 20.0);
        final theta = (2 * math.pi * t) / period;

        final x = 2.0 * math.sin(theta);
        final z = 2.0 * math.cos(theta);

        _soloud.set3dSourcePosition(handle!, x, 0, z);
        _soloud.setPan(handle!, math.sin(theta) * 0.85);

        if (_settings.value.rearLowPassEnabled) {
          final frontFactor = (math.cos(theta) + 1.0) / 2.0;
          final cutoff = 3200.0 + (12800.0 * frontFactor);
          final biquad = _soloud.filters.biquadResonantFilter;
          if (biquad.isActive) biquad.frequency.value = cutoff;
        }
      } catch (_) {
        // A single dropped frame of orbit is not worth surfacing.
      }
    });
  }

  void _stopOrbit() {
    _orbitTimer?.cancel();
    _orbitTimer = null;
    _orbitClock
      ..stop()
      ..reset();
    final handle = _handle;
    if (_live(handle)) {
      try {
        _soloud.set3dSourcePosition(handle!, 0, 0, 1);
        _soloud.setPan(handle!, 0.0);
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------- equaliser

  /// Drives SoLoud's parametric EQ: one band per preset slider.
  void _applyEqualizer() {
    if (!_engineReady) return;
    final s = _settings.value;
    try {
      final eq = _soloud.filters.parametricEqFilter;
      if (!s.eqEnabled) {
        if (eq.isActive) eq.deactivate();
        return;
      }
      if (!eq.isActive) eq.activate();

      eq.numBands.value = EqPreset.bandFrequencies.length.toDouble();
      eq.wet.value = 1.0;

      for (var i = 0; i < EqPreset.bandFrequencies.length; i++) {
        if (i < s.eqGains.length) {
          eq.bandGain(i).value = s.eqGains[i].clamp(0.0, 4.0);
        }
        eq.bandFreq(i).value = EqPreset.bandFrequencies[i];
        eq.bandQ(i).value = 1.0;
      }
    } catch (e) {
      debugPrint('EQ application failed: $e');
    }
  }

  void _applyBassBoost() {
    if (!_engineReady) return;
    final s = _settings.value;
    try {
      final bass = _soloud.filters.bassBoostFilter;
      if (s.bassBoost <= 0.0) {
        if (bass.isActive) bass.deactivate();
        return;
      }
      if (!bass.isActive) bass.activate();
      bass.wet.value = 1.0;
      bass.boost.value = s.bassBoost.clamp(0.0, 4.0);
    } catch (e) {
      debugPrint('Bass boost application failed: $e');
    }
  }

  /// Pushes a preset (or a manual band edit) into both the settings and engine.
  void setEqualizer({
    bool? enabled,
    String? presetName,
    List<double>? gains,
  }) {
    var next = _settings.value;
    if (enabled != null) next = next.copyWith(eqEnabled: enabled);
    if (presetName != null) next = next.copyWith(eqPresetName: presetName);
    if (gains != null && gains.length == EqPreset.bandFrequencies.length) {
      next = next.copyWith(eqGains: gains, eqPresetName: 'Custom');
    }
    _settings.update(next);
  }

  void setBassBoost(double value) {
    _settings.update(_settings.value.copyWith(bassBoost: value.clamp(0.0, 4.0)));
  }

  // ------------------------------------------------------------- visualiser

  /// Enables SoLoud's FFT feed only while something is actually watching it.
  Future<void> setVisualizerActive(bool active) async {
    if (!_engineReady) return;
    if (active == _visualizerOn) return;
    _visualizerOn = active;
    try {
      if (active) {
        _soloud.setVisualizationEnabled(
          true,
          windowSize: 256,
          kind: VisualizationKind.waveAndFft,
        );
        _vizSub = _soloud.audioVisualizationEvents.listen((data) {
          final fft = data.fftData;
          if (fft != null && !_fftController.isClosed) _fftController.add(fft);
        });
      } else {
        await _vizSub?.cancel();
        _vizSub = null;
        _soloud.setVisualizationEnabled(false);
      }
    } catch (e) {
      debugPrint('visualiser toggle failed: $e');
    }
  }

  // ------------------------------------------------------------- sleep timer

  /// `null` cancels. The fade-out is left to the engine so it is sample-accurate.
  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepRemaining.value = duration;
    if (duration == null) return;

    var remaining = duration;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining -= const Duration(seconds: 1);
      sleepRemaining.value = remaining <= Duration.zero ? null : remaining;
      if (remaining > Duration.zero) return;

      timer.cancel();
      _sleepTimer = null;
      unawaited(_fadeOutAndPause());
    });
  }

  Future<void> _fadeOutAndPause() async {
    final handle = _handle;
    if (_live(handle)) {
      try {
        _soloud.fadeVolume(handle!, 0.0, const Duration(seconds: 3));
        await Future<void>.delayed(const Duration(seconds: 3));
        await pause();
        if (_live(handle)) _soloud.setVolume(handle!, 1.0);
        return;
      } catch (e) {
        debugPrint('sleep fade failed: $e');
      }
    }
    await pause();
  }

  // ------------------------------------------------------------------ ducking

  /// Called by the OS integration layer when another app takes audio focus.
  void duck() {
    final handle = _handle;
    if (!_live(handle)) return;
    try {
      _soloud.fadeVolume(handle!, 0.25, const Duration(milliseconds: 200));
    } catch (_) {}
  }

  void unduck() {
    final handle = _handle;
    if (!_live(handle)) return;
    try {
      _soloud.fadeVolume(handle!, 1.0, const Duration(milliseconds: 300));
    } catch (_) {}
  }

  // ------------------------------------------------------------------ volume

  void setVolume(double value) {
    if (!_engineReady) return;
    try {
      _soloud.setGlobalVolume(value.clamp(0.0, 1.0));
    } catch (_) {}
  }

  // ------------------------------------------------------------------ toggles

  void setShuffle(bool enabled) {
    shuffleEnabled.value = enabled;
    _rebuildShuffleOrder(seedWith: _queueIndex);
    _bump();
  }

  void setRepeatMode(RepeatMode mode) {
    repeatMode.value = mode;
    _bump();
  }

  void cycleRepeatMode() {
    final next = switch (repeatMode.value) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    setRepeatMode(next);
  }

  void _bump() => stateRevision.value++;

  // -------------------------------------------------------------- teardown

  Future<void> disposeEngine() async {
    _disposed = true;
    _positionTimer?.cancel();
    _crossfadeTimer?.cancel();
    _sleepTimer?.cancel();
    _stopOrbit();
    await _vizSub?.cancel();
    await _fftController.close();
    await _teardownVoice();
    try {
      if (_soloud.isInitialized) _soloud.deinit();
    } catch (_) {}
  }
}

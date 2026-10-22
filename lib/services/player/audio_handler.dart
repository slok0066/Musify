import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

// AudioDeviceType is still marked @experimental in audio_session, but the
// device stream is the only reliable way to implement "auto 8D on headphones".
// ignore_for_file: experimental_member_use

import '../../data/models/track.dart';
import '../settings_service.dart';
import 'playback_service.dart';

/// Android / iOS bridge between the platform and [PlaybackService].
///
/// This class deliberately owns **no audio state**: the engine is the single
/// source of truth and this adapter only mirrors it into `audio_service`'s
/// streams so the lock screen, notification, Bluetooth controls and Android
/// Auto all agree with the app. Every callback is the platform asking the
/// engine to do something, never the adapter acting on its own.
///
/// It is only instantiated on mobile; desktop builds drive [PlaybackService]
/// directly, which is what makes the engine testable off-device.
/// Writes a like/unlike requested from outside the widget tree (lock screen).
typedef LikeDelegate = Future<void> Function(Track track, bool liked);

class MusifyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  MusifyAudioHandler(this._player, {LikeDelegate? likeDelegate})
      : _likeDelegate = likeDelegate {
    _attach();
  }

  final PlaybackService _player;
  final LikeDelegate? _likeDelegate;

  StreamSubscription<void>? _noisySub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<Set<AudioDevice>>? _devicesSub;
  Timer? _positionTicker;
  bool _disposed = false;

  /// The OS audio session, kept once acquired. Android only delivers focus
  /// callbacks (calls, other apps starting, headphones unplugging) while a
  /// focus request is held, so playback must activate this session when it
  /// starts sounding.
  AudioSession? _session;
  bool _focusRequested = false;

  /// True when the current pause was caused by an audio interruption (a call,
  /// or another app taking focus). Only such a pause is undone when the
  /// interruption ends — a pause the user chose always wins.
  bool _interruptionPaused = false;

  /// Last published position, so a paused player does not spam the platform.
  Duration _lastPosition = Duration.zero;

  // ------------------------------------------------------------------ session

  /// Configures the OS audio session. Safe to call from `main()` inside the
  /// startup timeout: any failure just means the OS keeps its defaults.
  Future<void> configureSession() async {
    try {
      final session = await AudioSession.instance;
      _session = session;
      try {
        await session.configure(const AudioSessionConfiguration.music());
      } catch (e) {
        // A configuration failure must not cost us the interruption wiring.
        debugPrint('AudioSession configure skipped: $e');
      }

      // Unplugging headphones must pause — never blast the speaker. (Android
      // only registers this broadcast once a focus request has been granted,
      // which [_ensureAudioFocus] does on the first play.)
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        if (_player.isPlaying.value) unawaited(_player.pause());
      });

      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.duck();
            case AudioInterruptionType.pause:
              // A transient loss (a call): remember that this pause was not
              // the user's, so the end of the interruption may undo it.
              if (_player.isPlaying.value) _interruptionPaused = true;
              unawaited(_player.pause());
            case AudioInterruptionType.unknown:
              // A permanent loss (another app took focus): Android never
              // returns focus on its own, and the plugin has already given
              // the request up — the next play must request it again.
              _interruptionPaused = false;
              _focusRequested = false;
              unawaited(_player.pause());
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.unduck();
            case AudioInterruptionType.pause:
              if (_interruptionPaused) unawaited(_player.resume());
              _interruptionPaused = false;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      // Route changes feed the "Auto-enable 8D on headphones" setting.
      _devicesSub = session.devicesStream.listen(_onDevicesChanged);

      // Focus is held only while sound is flowing: the first play activates.
      _player.isPlaying.addListener(_onPlayingChanged);
      if (_player.isPlaying.value) unawaited(_ensureAudioFocus());
    } catch (e) {
      debugPrint('AudioSession configuration skipped: $e');
    }
  }

  /// Takes audio focus the moment playback starts sounding. That request is
  /// what makes Android pause Musify when another app (YouTube, a call) asks
  /// for the same focus.
  void _onPlayingChanged() {
    if (_disposed) return;
    if (!_player.isPlaying.value) return;
    // A deliberate resume ends any pending interruption bookkeeping.
    _interruptionPaused = false;
    unawaited(_ensureAudioFocus());
  }

  Future<void> _ensureAudioFocus() async {
    final session = _session;
    if (session == null || _disposed || _focusRequested) return;
    _focusRequested = true;
    try {
      final granted = await session.setActive(true);
      if (!granted) {
        // Denied (some OEMs do this during calls): allow the next play to ask
        // again rather than thinking focus is held.
        _focusRequested = false;
        debugPrint('audio focus request not granted');
      }
    } catch (e) {
      _focusRequested = false;
      debugPrint('audio focus request failed: $e');
    }
  }

  void _onDevicesChanged(Set<AudioDevice> devices) {
    const headphoneTypes = {
      AudioDeviceType.wiredHeadphones,
      AudioDeviceType.wiredHeadset,
      AudioDeviceType.bluetoothA2dp,
      AudioDeviceType.bluetoothLe,
      AudioDeviceType.usbAudio,
      AudioDeviceType.hearingAid,
      AudioDeviceType.carAudio,
      AudioDeviceType.dock,
    };

    final connected = devices.any((d) => headphoneTypes.contains(d.type));
    _player.headphonesConnected.value = connected;

    // Hysteresis: only ever *turn on* automatically. Yanking the user out of 8D
    // when they unplug would be a surprise, and a manual toggle always wins.
    if (connected && _player.settings.value.auto8DOnHeadphones) {
      if (!_player.is8DEnabled.value) unawaited(_player.set8DEnabled(true));
    }
  }

  // ------------------------------------------------------------------ mirror

  void _attach() {
    void listen(ValueListenable<Object?> notifier) {
      notifier.addListener(_onEngineChanged);
    }

    listen(_player.currentTrack);
    listen(_player.isPlaying);
    listen(_player.isBuffering);
    listen(_player.duration);
    listen(_player.buffered);
    listen(_player.errorText);
    listen(_player.is8DEnabled);
    listen(_player.shuffleEnabled);
    listen(_player.repeatMode);
    listen(_player.queue);
    listen(_player.queueIndex);
    listen(_player.stateRevision);

    _positionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final position = _player.position.value;
      if (position == _lastPosition && !_player.isPlaying.value) return;
      _publish();
    });

    _publish();
  }

  void _onEngineChanged() {
    if (_disposed) return;
    _publish();
  }

  void _publish() {
    if (_disposed) return;
    final queue = _player.queue.value;
    final index = _player.queueIndex.value.clamp(
      0,
      queue.isEmpty ? 0 : queue.length - 1,
    );
    final track = _player.currentTrack.value;
    final position = _player.position.value;
    final duration = _player.duration.value;
    final error = _player.errorText.value;
    final buffering = _player.isBuffering.value;
    final playing = _player.isPlaying.value;

    _lastPosition = position;

    this.queue.add(queue.map(_toMediaItem).toList(growable: false));
    mediaItem.add(track == null ? null : _toMediaItem(track));

    final processingState = switch (true) {
      _ when error != null => AudioProcessingState.error,
      _ when track == null => AudioProcessingState.idle,
      _ when buffering => AudioProcessingState.loading,
      _ => AudioProcessingState.ready,
    };

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          const MediaControl(
            androidIcon: 'drawable/ic_launcher_foreground',
            label: '8D Audio',
            action: MediaAction.custom,
          ),
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: playing,
        updatePosition: position > duration && duration > Duration.zero
            ? duration
            : position,
        bufferedPosition: _player.buffered.value,
        speed: 1.0,
        queueIndex: queue.isEmpty ? null : index,
        repeatMode: _repeatMode,
        shuffleMode:
            _player.shuffleEnabled.value ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      ),
    );
  }

  AudioServiceRepeatMode get _repeatMode => switch (_player.repeatMode.value) {
    RepeatMode.off => AudioServiceRepeatMode.none,
    RepeatMode.all => AudioServiceRepeatMode.all,
    RepeatMode.one => AudioServiceRepeatMode.one,
  };

  MediaItem _toMediaItem(Track track) => MediaItem(
    id: track.id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    duration: track.duration > Duration.zero ? track.duration : null,
    artUri: track.imageUrl.isEmpty ? null : Uri.tryParse(track.imageUrl),
    extras: {
      'bitrate': track.bitrate,
      'offline': track.isDownloaded,
      if (track.permaUrl != null) 'permaUrl': track.permaUrl,
    },
  );

  // -------------------------------------------------------------- commands

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _interruptionPaused = false;
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.skipToNext();

  @override
  Future<void> skipToPrevious() => _player.skipToPrevious();

  @override
  Future<void> skipToQueueItem(int index) => _player.jumpTo(index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _player.setRepeatMode(
      switch (repeatMode) {
        AudioServiceRepeatMode.one => RepeatMode.one,
        AudioServiceRepeatMode.all => RepeatMode.all,
        AudioServiceRepeatMode.none => RepeatMode.off,
        // Overrides are not a Musify concept: treat as off.
        AudioServiceRepeatMode.group => RepeatMode.off,
      },
    );
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _player.setShuffle(shuffleMode == AudioServiceShuffleMode.all);
  }

  /// The lock screen's heart button, wired to the same store as the in-app one.
  Future<void> setLiked(bool liked, {required Track track}) async {
    await _likeDelegate?.call(track, liked);
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == '8D Audio' || name == 'toggle8D' || name == 'toggle_8d') {
      _player.toggle8D();
    }
  }

  @override
  Future<void> onTaskRemoved() => stop();

  Future<void> disposeAdapter() async {
    _disposed = true;
    _positionTicker?.cancel();
    _player.isPlaying.removeListener(_onPlayingChanged);
    await _noisySub?.cancel();
    await _interruptionSub?.cancel();
    await _devicesSub?.cancel();
    if (_focusRequested) {
      _focusRequested = false;
      try {
        await _session?.setActive(false);
      } catch (e) {
        debugPrint('audio focus release skipped: $e');
      }
    }
  }
}

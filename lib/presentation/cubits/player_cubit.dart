import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/music_repository.dart';
import '../../data/sources/local_store.dart';
import '../../services/player/playback_service.dart';
import '../../services/settings_service.dart';

/// Everything any screen needs to know about playback, in one immutable value.
///
/// `position` updates four times a second, so widgets subscribe through
/// `buildWhen` selectors rather than rebuilding wholesale.
class PlayerState extends Equatable {
  const PlayerState({
    this.track,
    this.isPlaying = false,
    this.isBuffering = false,
    this.engineReady = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.bufferFraction,
    this.errorText,
    this.is8D = false,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
    this.sleepRemaining,
    this.queue = const <Track>[],
    this.queueIndex = 0,
    this.liked = false,
    this.downloaded = false,
    this.downloadProgress,
    this.headphones = false,
  });

  final Track? track;
  final bool isPlaying;
  final bool isBuffering;
  final bool engineReady;
  final Duration position;
  final Duration duration;
  final Duration buffered;

  /// `null` when the transfer size is unknown, `1.0` when staged.
  final double? bufferFraction;
  final String? errorText;

  final bool is8D;
  final bool shuffle;
  final RepeatMode repeat;
  final Duration? sleepRemaining;
  final List<Track> queue;
  final int queueIndex;

  final bool liked;
  final bool downloaded;

  /// 0.0–1.0 while an offline download is running.
  final double? downloadProgress;
  final bool headphones;

  bool get hasTrack => track != null;

  bool get canSeek => duration > Duration.zero;

  /// Readout for the mini-player's progress hairline.
  double get progress {
    if (duration <= Duration.zero) return 0;
    final value = position.inMilliseconds / duration.inMilliseconds;
    return value.isFinite ? value.clamp(0.0, 1.0) : 0;
  }

  double get bufferedFraction {
    if (duration <= Duration.zero) return 0;
    if (buffered >= duration) return 1;
    final value = buffered.inMilliseconds / duration.inMilliseconds;
    return value.isFinite ? value.clamp(0.0, 1.0) : 0;
  }

  String get sourceLabel =>
      track?.sourceLabel ?? (downloaded ? 'OFFLINE VAULT' : 'MUSIFY');

  PlayerState copyWith({
    Track? track,
    bool clearTrack = false,
    bool? isPlaying,
    bool? isBuffering,
    bool? engineReady,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    double? bufferFraction,
    bool clearBufferFraction = false,
    String? errorText,
    bool clearError = false,
    bool? is8D,
    bool? shuffle,
    RepeatMode? repeat,
    Duration? sleepRemaining,
    bool clearSleep = false,
    List<Track>? queue,
    int? queueIndex,
    bool? liked,
    bool? downloaded,
    double? downloadProgress,
    bool clearDownloadProgress = false,
    bool? headphones,
  }) {
    return PlayerState(
      track: clearTrack ? null : (track ?? this.track),
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      engineReady: engineReady ?? this.engineReady,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffered: buffered ?? this.buffered,
      bufferFraction:
          clearBufferFraction ? null : (bufferFraction ?? this.bufferFraction),
      errorText: clearError ? null : (errorText ?? this.errorText),
      is8D: is8D ?? this.is8D,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      sleepRemaining: clearSleep ? null : (sleepRemaining ?? this.sleepRemaining),
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      liked: liked ?? this.liked,
      downloaded: downloaded ?? this.downloaded,
      downloadProgress: clearDownloadProgress
          ? null
          : (downloadProgress ?? this.downloadProgress),
      headphones: headphones ?? this.headphones,
    );
  }

  @override
  List<Object?> get props => [
    track,
    isPlaying,
    isBuffering,
    engineReady,
    position,
    duration,
    buffered,
    bufferFraction,
    errorText,
    is8D,
    shuffle,
    repeat,
    sleepRemaining,
    queue,
    queueIndex,
    liked,
    downloaded,
    downloadProgress,
    headphones,
  ];
}

/// The UI-facing face of [PlaybackService].
///
/// The engine stays a plain, platform-free object; this cubit is only a
/// translation layer, which is why the same engine can be driven by a widget
/// test with no audio device at all.
class PlayerCubit extends Cubit<PlayerState> {
  PlayerCubit({
    required PlaybackService player,
    required LibraryRepository library,
    required MusicRepository music,
    required LocalStore store,
  })  : _player = player,
        _library = library,
        _music = music,
        _store = store,
        super(const PlayerState()) {
    _attach();
  }

  final PlaybackService _player;
  final LibraryRepository _library;
  final MusicRepository _music;
  final LocalStore _store;

  final Map<String, double?> _downloads = {};
  final List<ValueListenable<Object?>> _watched = [];

  // ------------------------------------------------------------------ wiring

  void _attach() {
    _watch(_player.currentTrack);
    _watch(_player.isPlaying);
    _watch(_player.isBuffering);
    _watch(_player.position);
    _watch(_player.duration);
    _watch(_player.buffered);
    _watch(_player.bufferFraction);
    _watch(_player.errorText);
    _watch(_player.is8DEnabled);
    _watch(_player.shuffleEnabled);
    _watch(_player.repeatMode);
    _watch(_player.sleepRemaining);
    _watch(_player.queue);
    _watch(_player.queueIndex);
    _watch(_player.headphonesConnected);
    _store.revision.addListener(_sync);
    _sync();
  }

  void _watch(ValueListenable<Object?> notifier) {
    notifier.addListener(_sync);
    _watched.add(notifier);
  }

  void _sync() {
    if (isClosed) return;
    final track = _player.currentTrack.value;
    final next = PlayerState(
      track: track,
      isPlaying: _player.isPlaying.value,
      isBuffering: _player.isBuffering.value,
      engineReady: _player.engineReady,
      position: _player.position.value,
      duration: _player.duration.value,
      buffered: _player.buffered.value,
      bufferFraction: _player.bufferFraction.value,
      errorText: _player.errorText.value,
      is8D: _player.is8DEnabled.value,
      shuffle: _player.shuffleEnabled.value,
      repeat: _player.repeatMode.value,
      sleepRemaining: _player.sleepRemaining.value,
      queue: _player.queue.value,
      queueIndex: _player.queueIndex.value,
      liked: track != null && _library.isLiked(track.id, track.dedupeKey),
      downloaded: track != null && _library.isDownloaded(track.id),
      downloadProgress: track == null ? null : _downloads[track.id],
      headphones: _player.headphonesConnected.value,
    );
    if (next == state) return;
    emit(next);
  }

  /// Re-syncs player state with repositories immediately.
  void sync() => _sync();

  // ----------------------------------------------------------------- playback

  /// Starts a collection from [startIndex]. [source] is the label the Now
  /// Playing header shows, e.g. `SEARCH // 320 KBPS AAC`.
  Future<void> playCollection(
    List<Track> tracks, {
    int startIndex = 0,
    bool? shuffle,
    String? source,
  }) async {
    if (tracks.isEmpty) return;
    final labelled = _label(tracks, source);
    await _player.playCollection(labelled, startIndex: startIndex, shuffle: shuffle);
    _recordHistory(labelled, startIndex);
  }

  Future<void> playTrack(Track track, {List<Track>? context, String? source}) async {
    final queue = _label(
      [track, ...?context?.where((t) => t.id != track.id)],
      source,
    );
    await _player.playTrack(queue.first, context: queue.sublist(1));
    _recordHistory(queue, 0);
  }

  Future<void> togglePlayPause() => _player.togglePlayPause();

  Future<void> play() => _player.resume();

  Future<void> pause() => _player.pause();

  Future<void> next() => _player.skipToNext();

  Future<void> previous() => _player.skipToPrevious();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> playNext(Track track) => _player.playNext(track);

  Future<void> addToQueue(Track track) => _player.addToQueue(track);

  Future<void> addAllToQueue(List<Track> tracks) => _player.addAllToQueue(tracks);

  Future<void> removeFromQueue(int index) => _player.removeFromQueue(index);

  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      _player.reorderQueue(oldIndex, newIndex);

  Future<void> clearQueue() => _player.clearQueue();

  Future<void> jumpTo(int index) => _player.jumpTo(index);

  void setVolume(double value) => _player.setVolume(value);

  List<Track> _label(List<Track> tracks, String? source) {
    if (source == null || source.isEmpty) return tracks;
    return tracks.map((t) => t.copyWith(sourceLabel: source)).toList();
  }

  /// Playback counts as a "play" for the Home Continue Listening rail.
  void _recordHistory(List<Track> queue, int index) {
    if (index < 0 || index >= queue.length) return;
    final track = queue[index];
    if (track.id.isEmpty) return;
    unawaited(_library.recordPlay(track));
  }

  // -------------------------------------------------------------------- 8D

  Future<void> toggle8D() => _player.toggle8D();

  Future<void> set8D(bool enabled) => _player.set8DEnabled(enabled);

  void update8DParameters({double? orbitSeconds, double? reverbMix, bool? rearLowPass}) =>
      _player.update8DParameters(
        orbitSeconds: orbitSeconds,
        reverbMix: reverbMix,
        rearLowPass: rearLowPass,
      );

  // ----------------------------------------------------------------- modes

  void toggleShuffle() => _player.setShuffle(!_player.shuffleEnabled.value);

  void setRepeatMode(RepeatMode mode) => _player.setRepeatMode(mode);

  void cycleRepeat() => _player.cycleRepeatMode();

  void setSleepTimer(Duration? duration) => _player.setSleepTimer(duration);

  void cancelSleepTimer() => _player.setSleepTimer(null);

  // ---------------------------------------------------------------- library

  Future<bool> toggleLike(Track track) async {
    final liked = await _library.toggleLike(track);
    _sync();
    return liked;
  }

  Future<void> like(Track track) async {
    await _library.like(track);
    _sync();
  }

  Future<void> unlike(String trackId) async {
    await _library.unlike(trackId);
    _sync();
  }

  /// `[DOWNLOAD]` on the Now Playing dock or the options sheet.
  Future<bool> download(Track track) async {
    if (_downloads.containsKey(track.id)) return false;
    _downloads[track.id] = null;
    _sync();

    try {
      final updated = await _music.downloadTrack(
        track,
        onProgress: (fraction) {
          if (isClosed) return;
          _downloads[track.id] = fraction;
          _sync();
        },
      );
      if (updated == null) return false;
      await _library.recordDownload(updated);
      return true;
    } catch (e) {
      debugPrint('Download failed for ${track.id}: $e');
      return false;
    } finally {
      _downloads.remove(track.id);
      _sync();
    }
  }

  Future<void> deleteDownload(Track track) async {
    await _music.deleteDownload(track);
    await _library.removeDownloadRecord(track.id);
    _sync();
  }

  bool isDownloading(String trackId) => _downloads.containsKey(trackId);

  double? progressFor(String trackId) => _downloads[trackId];

  @override
  Future<void> close() {
    for (final notifier in _watched) {
      notifier.removeListener(_sync);
    }
    _watched.clear();
    _store.revision.removeListener(_sync);
    return super.close();
  }
}

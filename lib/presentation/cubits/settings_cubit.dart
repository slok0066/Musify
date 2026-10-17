import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/tactile_decorations.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/music_repository.dart';
import '../../services/backup_service.dart';
import '../../services/network_monitor.dart';
import '../../services/player/playback_service.dart';
import '../../services/settings_service.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.settings = const MusifySettings(),
    this.cacheBytes = 0,
    this.downloadsBytes = 0,
    this.downloadsCount = 0,
    this.busy = false,
    this.message,
    this.isUnmetered = false,
  });

  final MusifySettings settings;
  final int cacheBytes;
  final int downloadsBytes;
  final int downloadsCount;
  final bool busy;

  /// One-shot message for the snackbar.
  final String? message;
  final bool isUnmetered;

  String get qualityLine => isUnmetered
      ? 'WI-FI · ${settings.wifiQuality.label}'
      : 'MOBILE · ${settings.mobileQuality.label}';

  SettingsState copyWith({
    MusifySettings? settings,
    int? cacheBytes,
    int? downloadsBytes,
    int? downloadsCount,
    bool? busy,
    String? message,
    bool clearMessage = false,
    bool? isUnmetered,
  }) {
    return SettingsState(
      settings: settings ?? this.settings,
      cacheBytes: cacheBytes ?? this.cacheBytes,
      downloadsBytes: downloadsBytes ?? this.downloadsBytes,
      downloadsCount: downloadsCount ?? this.downloadsCount,
      busy: busy ?? this.busy,
      message: clearMessage ? null : (message ?? this.message),
      isUnmetered: isUnmetered ?? this.isUnmetered,
    );
  }

  @override
  List<Object?> get props => [
    settings,
    cacheBytes,
    downloadsBytes,
    downloadsCount,
    busy,
    message,
    isUnmetered,
  ];
}

/// The Audio Engineering Lab's brain.
///
/// Every setter writes straight through [SettingsService], which the engine
/// already listens to — so a slider and its audible effect can never drift.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required SettingsService settings,
    required MusicRepository music,
    required LibraryRepository library,
    required BackupService backup,
    required PlaybackService player,
    required NetworkMonitor network,
  })  : _settings = settings,
        _music = music,
        _library = library,
        _backup = backup,
        _player = player,
        _network = network,
        super(SettingsState(settings: settings.value)) {
    _settings.addListener(_onSettingsChanged);
    _network.isUnmetered.addListener(_onTransportChanged);
    Haptics.enabled = settings.value.hapticsEnabled;
    refreshStorage();
  }

  final SettingsService _settings;
  final MusicRepository _music;
  final LibraryRepository _library;
  final BackupService _backup;
  final PlaybackService _player;
  final NetworkMonitor _network;

  void _onSettingsChanged() {
    if (isClosed) return;
    Haptics.enabled = _settings.value.hapticsEnabled;
    emit(state.copyWith(settings: _settings.value));
  }

  void _onTransportChanged() {
    if (isClosed) return;
    emit(state.copyWith(isUnmetered: _network.isUnmetered.value));
  }

  void _update(MusifySettings next) => _settings.update(next);

  // --------------------------------------------------------------- quality

  void setWifiQuality(AudioQuality quality) =>
      _update(_settings.value.copyWith(wifiQuality: quality));

  void setMobileQuality(AudioQuality quality) =>
      _update(_settings.value.copyWith(mobileQuality: quality));

  void setDownloadQuality(AudioQuality quality) =>
      _update(_settings.value.copyWith(downloadQuality: quality));

  // ------------------------------------------------------------- 8D spatial

  void setOrbitSeconds(double seconds) =>
      _player.update8DParameters(orbitSeconds: seconds.clamp(5.0, 20.0));

  void setReverbMix(double mix) =>
      _player.update8DParameters(reverbMix: mix.clamp(0.0, 0.5));

  void setRearLowPass(bool enabled) =>
      _player.update8DParameters(rearLowPass: enabled);

  void setAuto8DOnHeadphones(bool enabled) =>
      _update(_settings.value.copyWith(auto8DOnHeadphones: enabled));

  void reset8DDefaults() {
    _player.update8DParameters(orbitSeconds: 10.0, reverbMix: 0.24, rearLowPass: true);
    _message('8D CALIBRATION RESET TO FACTORY');
  }

  // -------------------------------------------------------------- equaliser

  void setEqEnabled(bool enabled) => _player.setEqualizer(enabled: enabled);

  void applyEqPreset(String name) {
    final preset = EqPreset.all.firstWhere(
      (p) => p.name.toLowerCase() == name.toLowerCase(),
      orElse: () => EqPreset.flat,
    );
    _player.setEqualizer(presetName: preset.name, gains: preset.gains);
    _message('PRESET // ${preset.name.toUpperCase()}');
  }

  /// [value] is a 0.0–4.0 band gain where `1.0` is unity.
  void setEqGain(int band, double value) {
    final gains = [..._settings.value.eqGains];
    if (band < 0 || band >= gains.length) return;
    gains[band] = value.clamp(0.0, 4.0);
    _player.setEqualizer(gains: gains);
  }

  void setBassBoost(double value) => _player.setBassBoost(value);

  void setCrossfadeSeconds(int seconds) =>
      _update(_settings.value.copyWith(crossfadeSeconds: seconds.clamp(0, 12)));

  void setGaplessPreload(bool enabled) =>
      _update(_settings.value.copyWith(gaplessPreload: enabled));

  void setPrefetchNext(bool enabled) =>
      _update(_settings.value.copyWith(prefetchNext: enabled));

  /// Instant play: stream the AAC frames instead of staging the whole file.
  void setInstantStart(bool enabled) =>
      _update(_settings.value.copyWith(instantStart: enabled));

  // --------------------------------------------------------------- interface

  void setTheme(ChassisTheme theme) => _update(_settings.value.copyWith(theme: theme));

  void setHaptics(bool enabled) {
    _update(_settings.value.copyWith(hapticsEnabled: enabled));
    if (enabled) Haptics.press();
  }

  void setVisualizer(VisualizerMode mode) =>
      _update(_settings.value.copyWith(visualizer: mode));

  // ----------------------------------------------------------------- storage

  Future<void> refreshStorage() async {
    try {
      final cache = await _music.streamCacheSizeBytes();
      final downloads = await _music.downloadsSizeBytes();
      if (isClosed) return;
      emit(
        state.copyWith(
          cacheBytes: cache,
          downloadsBytes: downloads,
          downloadsCount: _library.downloads().length,
        ),
      );
    } catch (e) {
      debugPrint('Storage measurement failed: $e');
    }
  }

  Future<void> clearStreamCache() async {
    emit(state.copyWith(busy: true));
    final freed = await _music.clearStreamCache();
    await refreshStorage();
    if (isClosed) return;
    emit(state.copyWith(busy: false));
    _message(freed <= 0 ? 'CACHE ALREADY EMPTY' : 'CLEARED ${_mb(freed)}');
  }

  Future<void> deleteAllDownloads() async {
    emit(state.copyWith(busy: true));
    final freed = await _music.deleteAllDownloads();
    await _library.removeAllDownloadRecords();
    await refreshStorage();
    if (isClosed) return;
    emit(state.copyWith(busy: false));
    _message(freed <= 0 ? 'NOTHING TO DELETE' : 'FREED ${_mb(freed)}');
  }

  // ------------------------------------------------------------------ backup

  Future<String?> exportBackup() async {
    emit(state.copyWith(busy: true));
    final path = await _backup.exportToFile();
    if (isClosed) return path;
    emit(state.copyWith(busy: false));
    _message(path == null ? 'EXPORT FAILED' : 'BACKUP SAVED');
    return path;
  }

  Future<String?> backupJson() => _backup.exportToJson();

  Future<BackupResult> importBackup(String json) async {
    emit(state.copyWith(busy: true));
    final result = await _backup.importFromJson(json);
    if (isClosed) return result;
    emit(state.copyWith(busy: false, settings: _settings.value));
    await refreshStorage();
    _message(result.message.toUpperCase());
    return result;
  }

  // ------------------------------------------------------------------ helper

  void _message(String message) {
    if (isClosed) return;
    emit(state.copyWith(message: message));
  }

  void consumeMessage() {
    if (isClosed) return;
    emit(state.copyWith(clearMessage: true));
  }

  static String _mb(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return mb < 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.round()} MB';
  }

  @override
  Future<void> close() {
    _settings.removeListener(_onSettingsChanged);
    _network.isUnmetered.removeListener(_onTransportChanged);
    return super.close();
  }
}

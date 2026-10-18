import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chassis themes.
enum ChassisTheme { carbon, alabaster, system }

/// Now Playing visualizer modes.
enum VisualizerMode { fft, wave, off }

/// Stream quality tiers offered by the Settings screen.
enum AudioQuality {
  extreme(320, '320 KBPS', 'EXTREME'),
  high(160, '160 KBPS', 'HIGH'),
  saver(96, '96 KBPS', 'DATA SAVER');

  const AudioQuality(this.kbps, this.label, this.tag);

  final int kbps;
  final String label;
  final String tag;
}

/// An equalizer preset: 10 band gains where `1.0` is unity.
class EqPreset {
  const EqPreset(this.name, this.gains);

  final String name;
  final List<double> gains;

  /// ISO octave centres. The parametric EQ accepts 10 Hz–24 kHz, and Q is held
  /// at 1.0 so neighbouring bands overlap like a graphic EQ.
  static const List<double> bandFrequencies = [
    31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
  ];

  static const EqPreset flat = EqPreset('Flat', [
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  ]);

  static const List<EqPreset> all = [
    flat,
    EqPreset('Bass Boost', [1.9, 1.75, 1.45, 1.2, 1.05, 1, 1, 1, 1, 0.98]),
    EqPreset('Vocal', [0.85, 0.9, 1.0, 1.15, 1.3, 1.35, 1.25, 1.1, 1.0, 0.95]),
    EqPreset('Electronic', [1.55, 1.4, 1.12, 1.0, 0.95, 1.0, 1.12, 1.28, 1.36, 1.3]),
    EqPreset('Phonk', [2.2, 2.0, 1.6, 1.25, 1.0, 0.9, 0.85, 0.9, 1.05, 1.18]),
    EqPreset('Acoustic', [1.05, 1.1, 1.15, 1.12, 1.05, 1.0, 1.05, 1.12, 1.15, 1.1]),
  ];
}

/// Live Badge / waveform decay.
enum RepeatMode { off, all, one }

/// Every user-facing knob in Musify.
///
/// One immutable object, one JSON blob in `SharedPreferences`, one
/// `ValueNotifier` in the service locator. Any change is written immediately
/// and pushed into the audio engine, so a setting and its audible effect can
/// never drift apart.
@immutable
class MusifySettings {
  const MusifySettings({
    this.wifiQuality = AudioQuality.extreme,
    this.mobileQuality = AudioQuality.high,
    this.downloadQuality = AudioQuality.extreme,
    this.orbitSeconds = 10.0,
    this.reverbMix = 0.24,
    this.rearLowPassEnabled = true,
    this.auto8DOnHeadphones = false,
    this.eqEnabled = false,
    this.eqPresetName = 'Flat',
    this.eqGains = flatGains,
    this.bassBoost = 0.0,
    this.crossfadeSeconds = 0,
    this.gaplessPreload = true,
    this.theme = ChassisTheme.carbon,
    this.hapticsEnabled = true,
    this.visualizer = VisualizerMode.fft,
    this.prefetchNext = true,
    this.instantStart = true,
    this.hasSeenCredits = false,
  });

  static const List<double> flatGains = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1];

  final AudioQuality wifiQuality;
  final AudioQuality mobileQuality;
  final AudioQuality downloadQuality;

  /// 8D orbit period in seconds (5 slow-burn → 20 lazy).
  final double orbitSeconds;
  final double reverbMix;
  final bool rearLowPassEnabled;
  final bool auto8DOnHeadphones;

  final bool eqEnabled;
  final String eqPresetName;
  final List<double> eqGains;

  /// 0.0 = off, 4.0 = maximum.
  final double bassBoost;

  /// 0 = off, up to 12 seconds.
  final int crossfadeSeconds;
  final bool gaplessPreload;

  final ChassisTheme theme;
  final bool hapticsEnabled;
  final VisualizerMode visualizer;
  final bool prefetchNext;

  /// **Instant play.** Music starts from the first few hundred kilobytes of a
  /// track instead of after the whole file has arrived: the MP4 sample table is
  /// indexed and the engine decodes AAC frames straight off the wire. Off, the
  /// old "download the whole file, then decode it" route is used — slower to
  /// start, useful for ruling this feature out when something sounds wrong.
  final bool instantStart;

  /// True once the one-time first launch credits page has been dismissed.
  final bool hasSeenCredits;

  AudioQuality get effectiveStreamQuality => wifiQuality;

  bool get is8DCustomised =>
      orbitSeconds != 10.0 || reverbMix != 0.24 || !rearLowPassEnabled;

  MusifySettings copyWith({
    AudioQuality? wifiQuality,
    AudioQuality? mobileQuality,
    AudioQuality? downloadQuality,
    double? orbitSeconds,
    double? reverbMix,
    bool? rearLowPassEnabled,
    bool? auto8DOnHeadphones,
    bool? eqEnabled,
    String? eqPresetName,
    List<double>? eqGains,
    double? bassBoost,
    int? crossfadeSeconds,
    bool? gaplessPreload,
    ChassisTheme? theme,
    bool? hapticsEnabled,
    VisualizerMode? visualizer,
    bool? prefetchNext,
    bool? instantStart,
    bool? hasSeenCredits,
  }) {
    return MusifySettings(
      wifiQuality: wifiQuality ?? this.wifiQuality,
      mobileQuality: mobileQuality ?? this.mobileQuality,
      downloadQuality: downloadQuality ?? this.downloadQuality,
      orbitSeconds: orbitSeconds ?? this.orbitSeconds,
      reverbMix: reverbMix ?? this.reverbMix,
      rearLowPassEnabled: rearLowPassEnabled ?? this.rearLowPassEnabled,
      auto8DOnHeadphones: auto8DOnHeadphones ?? this.auto8DOnHeadphones,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqPresetName: eqPresetName ?? this.eqPresetName,
      eqGains: eqGains ?? this.eqGains,
      bassBoost: bassBoost ?? this.bassBoost,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      gaplessPreload: gaplessPreload ?? this.gaplessPreload,
      theme: theme ?? this.theme,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      visualizer: visualizer ?? this.visualizer,
      prefetchNext: prefetchNext ?? this.prefetchNext,
      instantStart: instantStart ?? this.instantStart,
      hasSeenCredits: hasSeenCredits ?? this.hasSeenCredits,
    );
  }

  Map<String, dynamic> toMap() => {
    'wifiQuality': wifiQuality.name,
    'mobileQuality': mobileQuality.name,
    'downloadQuality': downloadQuality.name,
    'orbitSeconds': orbitSeconds,
    'reverbMix': reverbMix,
    'rearLowPassEnabled': rearLowPassEnabled,
    'auto8DOnHeadphones': auto8DOnHeadphones,
    'eqEnabled': eqEnabled,
    'eqPresetName': eqPresetName,
    'eqGains': eqGains,
    'bassBoost': bassBoost,
    'crossfadeSeconds': crossfadeSeconds,
    'gaplessPreload': gaplessPreload,
    'theme': theme.name,
    'hapticsEnabled': hapticsEnabled,
    'visualizer': visualizer.name,
    'prefetchNext': prefetchNext,
    'instantStart': instantStart,
    'hasSeenCredits': hasSeenCredits,
  };

  static MusifySettings fromMap(Map<String, dynamic> map) {
    T enumAt<T extends Enum>(String key, List<T> values, T fallback) {
      final raw = map[key]?.toString();
      if (raw == null) return fallback;
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return fallback;
    }

    double doubleAt(String key, double fallback) {
      final v = map[key];
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? fallback;
    }

    bool boolAt(String key, bool fallback) {
      final v = map[key];
      if (v is bool) return v;
      return fallback;
    }

    final rawGains = map['eqGains'];
    var gains = flatGains;
    if (rawGains is List && rawGains.length == 10) {
      final parsed = <double>[];
      for (final g in rawGains) {
        if (g is! num) {
          parsed.clear();
          break;
        }
        parsed.add(g.toDouble().clamp(0.0, 4.0));
      }
      if (parsed.length == 10) gains = parsed;
    }

    return MusifySettings(
      wifiQuality: enumAt('wifiQuality', AudioQuality.values, AudioQuality.extreme),
      mobileQuality: enumAt('mobileQuality', AudioQuality.values, AudioQuality.high),
      downloadQuality: enumAt('downloadQuality', AudioQuality.values, AudioQuality.extreme),
      orbitSeconds: doubleAt('orbitSeconds', 10.0).clamp(5.0, 20.0),
      reverbMix: doubleAt('reverbMix', 0.24).clamp(0.0, 0.5),
      rearLowPassEnabled: boolAt('rearLowPassEnabled', true),
      auto8DOnHeadphones: boolAt('auto8DOnHeadphones', false),
      eqEnabled: boolAt('eqEnabled', false),
      eqPresetName: map['eqPresetName']?.toString() ?? 'Flat',
      eqGains: gains,
      bassBoost: doubleAt('bassBoost', 0.0).clamp(0.0, 4.0),
      crossfadeSeconds: (doubleAt('crossfadeSeconds', 0)).round().clamp(0, 12),
      gaplessPreload: boolAt('gaplessPreload', true),
      theme: enumAt('theme', ChassisTheme.values, ChassisTheme.carbon),
      hapticsEnabled: boolAt('hapticsEnabled', true),
      visualizer: enumAt('visualizer', VisualizerMode.values, VisualizerMode.fft),
      prefetchNext: boolAt('prefetchNext', true),
      instantStart: boolAt('instantStart', true),
      hasSeenCredits: boolAt('hasSeenCredits', false),
    );
  }

  String toJson() => jsonEncode(toMap());

  static MusifySettings fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const MusifySettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const MusifySettings();
      return fromMap(decoded.cast<String, dynamic>());
    } catch (e) {
      debugPrint('Settings decode failed, using defaults: $e');
      return const MusifySettings();
    }
  }
}

/// Loads, watches and persists [MusifySettings].
class SettingsService extends ValueNotifier<MusifySettings> {
  SettingsService() : super(const MusifySettings());

  static const String _key = 'musify.settings.v1';

  static const String seenCreditsKey = 'musify_has_seen_credits_installed';

  SharedPreferences? _prefs;

  /// Hydrates from disk. Guarded by the caller's startup timeout, so a missing
  /// or corrupt store simply yields defaults.
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      var loaded = MusifySettings.fromJson(_prefs?.getString(_key));
      final seenFlag = _prefs?.getBool(seenCreditsKey) ?? false;
      if (seenFlag && !loaded.hasSeenCredits) {
        loaded = loaded.copyWith(hasSeenCredits: true);
      }
      value = loaded;
    } catch (e) {
      debugPrint('SettingsService.load failed, using defaults: $e');
      value = const MusifySettings();
    }
  }

  /// Applies [next] immediately and persists it in the background.
  void update(MusifySettings next) {
    value = next;
    _persist();
  }

  void mutate(MusifySettings Function(MusifySettings current) transform) {
    update(transform(value));
  }

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(_key, value.toJson());
      if (value.hasSeenCredits) {
        await _prefs?.setBool(seenCreditsKey, true);
      }
    } catch (e) {
      debugPrint('SettingsService persist failed: $e');
    }
  }

  /// Restores settings from a backup payload.
  Future<void> restoreFrom(MusifySettings settings) async {
    update(settings);
  }
}

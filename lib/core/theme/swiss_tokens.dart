import 'package:flutter/material.dart';

/// Musify's design tokens.
///
/// The visual paradigm is **Architectural Minimalism** — two sibling themes
/// rendered from one system:
///
/// * **Obsidian** (dark) — near-black obsidian planes, warm alabaster type and
///   a single champagne-amber filament accent. Soft glass, generous rounding.
/// * **Alabaster** (light) — paper-white architecture, ink-black accents,
///   monochrome editorial calm.
///
/// Type is **Plus Jakarta Sans** for voice and **JetBrains Mono** for the
/// technical register (counts, telemetry, timings, badges). Corners are soft:
/// 12px for small parts, 24px for cards, full pill for every control.
///
/// Every colour, radius, shadow and type ramp in the app comes from here, so
/// both themes are guaranteed to stay in sync.
@immutable
class SwissTokens extends ThemeExtension<SwissTokens> {
  const SwissTokens({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.hairline,
    required this.hairlineStrong,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.positive,
    required this.warning,
    required this.danger,
    required this.keycapTop,
    required this.keycapBottom,
    required this.keycapTopPressed,
    required this.keycapBottomPressed,
    required this.dropShadow,
    required this.innerShadow,
    required this.innerHighlight,
    required this.grainOpacity,
  });

  final Brightness brightness;

  /// Canvas — the deepest plane the whole UI floats above.
  final Color bg;

  /// A soft panel sitting on the canvas (rails, sheet bodies).
  final Color surface;

  /// A card or control raised off the canvas (white paper / graphite glass).
  final Color surfaceRaised;

  /// A well milled *into* the canvas (search fields, readout wells).
  final Color surfaceSunken;

  /// The hairline that softly separates planes.
  final Color hairline;
  final Color hairlineStrong;

  final Color ink;
  final Color inkMuted;
  final Color inkFaint;

  /// The single accent — Signal Champagne in the dark theme, Signal Ink in the
  /// light theme. Active states, progress, playback position only.
  final Color accent;
  final Color accentInk;
  final Color accentSoft;

  final Color positive;
  final Color warning;
  final Color danger;

  final Color keycapTop;
  final Color keycapBottom;
  final Color keycapTopPressed;
  final Color keycapBottomPressed;

  final Color dropShadow;
  final Color innerShadow;
  final Color innerHighlight;
  final double grainOpacity;

  /// Architectural rounding: 8px small parts, 16px cards, 24px large sheets, and
  /// stadium pills for every control.
  static const double radius = 16.0;
  static const double radiusLg = 24.0;
  static const double radiusSm = 8.0;

  /// Full pill — the shape of every button in the system.
  static const double radiusFull = 999.0;

  bool get isDark => brightness == Brightness.dark;

  /// **Monochrome Carbon** — the dark chassis (Black with White accents).
  static const SwissTokens carbon = SwissTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF0A0B0E),
    surface: Color(0xFF12141A),
    surfaceRaised: Color(0xFF181B22),
    surfaceSunken: Color(0xFF101217),
    hairline: Color(0x18FFFFFF),
    hairlineStrong: Color(0x28FFFFFF),
    ink: Color(0xFFFFFFFF),
    inkMuted: Color(0xFFB4B7BD),
    inkFaint: Color(0xFF71757E),
    accent: Color(0xFFFFFFFF),
    accentInk: Color(0xFF0A0B0E),
    accentSoft: Color(0x20FFFFFF),
    positive: Color(0xFF7ECF9E),
    warning: Color(0xFFE9C349),
    danger: Color(0xFFFFB4AB),
    keycapTop: Color(0xFF1E2129),
    keycapBottom: Color(0xFF181B22),
    keycapTopPressed: Color(0xFF14161C),
    keycapBottomPressed: Color(0xFF181B22),
    dropShadow: Color(0x55000000),
    innerShadow: Color(0xCC000000),
    innerHighlight: Color(0x0FFFFFFF),
    grainOpacity: 0.008,
  );

  /// **Monochrome Alabaster** — the light chassis (White with Black accents).
  static const SwissTokens alabaster = SwissTokens(
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF6F6F7),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEBECEE),
    hairline: Color(0xFFE2E3E6),
    hairlineStrong: Color(0xFFCDCFD4),
    ink: Color(0xFF0A0B0E),
    inkMuted: Color(0xFF4E535C),
    inkFaint: Color(0xFF8B909A),
    accent: Color(0xFF0A0B0E),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0x150A0B0E),
    positive: Color(0xFF2E7D4F),
    warning: Color(0xFF8A6A17),
    danger: Color(0xFFBA1A1A),
    keycapTop: Color(0xFFFFFFFF),
    keycapBottom: Color(0xFFF1F1EF),
    keycapTopPressed: Color(0xFFE7E7E4),
    keycapBottomPressed: Color(0xFFF0F0EE),
    dropShadow: Color(0x10000000),
    innerShadow: Color(0x18000000),
    innerHighlight: Color(0xFFFFFFFF),
    grainOpacity: 0.0,
  );

  /// Ambient lift — one soft, wide shadow for every floating plane. No hard
  /// contact edges: this architecture floats, it doesn't click.
  List<BoxShadow> get raisedShadow => [
    BoxShadow(
      color: dropShadow,
      offset: const Offset(0, 6),
      blurRadius: 20,
      spreadRadius: -6,
    ),
  ];

  List<BoxShadow> get pressedShadow => [
    BoxShadow(
      color: dropShadow,
      offset: const Offset(0, 2),
      blurRadius: 8,
      spreadRadius: -4,
    ),
  ];

  /// The filament bloom — champagne halo for latched/active hardware.
  List<BoxShadow> ledGlow(Color color, {double strength = 1}) => [
    BoxShadow(
      color: color.withValues(alpha: 0.45 * strength),
      blurRadius: 10 * strength,
      spreadRadius: 0.5,
    ),
    BoxShadow(
      color: color.withValues(alpha: 0.18 * strength),
      blurRadius: 22 * strength,
      spreadRadius: 1.5,
    ),
  ];

  @override
  SwissTokens copyWith({
    Brightness? brightness,
    Color? bg,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? hairline,
    Color? hairlineStrong,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? accent,
    Color? accentInk,
    Color? accentSoft,
    Color? positive,
    Color? warning,
    Color? danger,
    Color? keycapTop,
    Color? keycapBottom,
    Color? keycapTopPressed,
    Color? keycapBottomPressed,
    Color? dropShadow,
    Color? innerShadow,
    Color? innerHighlight,
    double? grainOpacity,
  }) {
    return SwissTokens(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      accentSoft: accentSoft ?? this.accentSoft,
      positive: positive ?? this.positive,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      keycapTop: keycapTop ?? this.keycapTop,
      keycapBottom: keycapBottom ?? this.keycapBottom,
      keycapTopPressed: keycapTopPressed ?? this.keycapTopPressed,
      keycapBottomPressed: keycapBottomPressed ?? this.keycapBottomPressed,
      dropShadow: dropShadow ?? this.dropShadow,
      innerShadow: innerShadow ?? this.innerShadow,
      innerHighlight: innerHighlight ?? this.innerHighlight,
      grainOpacity: grainOpacity ?? this.grainOpacity,
    );
  }

  @override
  SwissTokens lerp(covariant SwissTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return SwissTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      hairline: c(hairline, other.hairline),
      hairlineStrong: c(hairlineStrong, other.hairlineStrong),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      inkFaint: c(inkFaint, other.inkFaint),
      accent: c(accent, other.accent),
      accentInk: c(accentInk, other.accentInk),
      accentSoft: c(accentSoft, other.accentSoft),
      positive: c(positive, other.positive),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      keycapTop: c(keycapTop, other.keycapTop),
      keycapBottom: c(keycapBottom, other.keycapBottom),
      keycapTopPressed: c(keycapTopPressed, other.keycapTopPressed),
      keycapBottomPressed: c(keycapBottomPressed, other.keycapBottomPressed),
      dropShadow: c(dropShadow, other.dropShadow),
      innerShadow: c(innerShadow, other.innerShadow),
      innerHighlight: c(innerHighlight, other.innerHighlight),
      grainOpacity: grainOpacity + (other.grainOpacity - grainOpacity) * t,
    );
  }

  /// Convenience accessor — `SwissTokens.of(context)`.
  static SwissTokens of(BuildContext context) =>
      Theme.of(context).extension<SwissTokens>() ?? carbon;
}

/// The spatial grid. This is a *measured* system, so spacing is a fixed 4px
/// module rather than arbitrary numbers.
abstract final class SwissGrid {
  static const double u = 4;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;

  /// Page gutter used by every screen so left edges line up across tabs.
  static const double gutter = 20;

  /// Height of the docked mini-player (the floating glass mantle).
  static const double miniPlayerHeight = 68;

  /// Height of the bottom navigation bar.
  static const double navBarHeight = 64;

  /// The radius of the hero artwork plate on Now Playing.
  static const double artworkRadius = 24;
}

/// The typographic system.
///
/// Voice is set in **Plus Jakarta Sans** — a geometric-humanist face with
/// editorial proportions; display weights stay light and tightly tracked per
/// the house style. Every technical annotation — counts, telemetry, timings,
/// badges — is set in **JetBrains Mono**, uppercase and letterspaced, which is
/// what gives the interface its instrument-panel read.
abstract final class SwissType {
  static const String sansFont = 'PlusJakartaSans';
  static const String monoFont = 'JetBrainsMono';

  /// Section headers and eyebrow labels: `// HOME`, `JUMP BACK IN`.
  static const TextStyle label = TextStyle(
    fontFamily: monoFont,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
    height: 1.2,
  );

  static const TextStyle micro = TextStyle(
    fontFamily: monoFont,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
    height: 1.2,
  );

  /// Live readouts and elapsed time.
  static const TextStyle mono = TextStyle(
    fontFamily: monoFont,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    height: 1.25,
  );

  static const TextStyle monoStrong = TextStyle(
    fontFamily: monoFont,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    height: 1.2,
  );

  static const TextStyle displayXl = TextStyle(
    fontFamily: sansFont,
    fontSize: 32,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.8,
    height: 1.1,
  );

  static const TextStyle display = TextStyle(
    fontFamily: sansFont,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    height: 1.15,
  );

  static const TextStyle displaySm = TextStyle(
    fontFamily: sansFont,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.2,
  );

  static const TextStyle title = TextStyle(
    fontFamily: sansFont,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.25,
  );

  static const TextStyle body = TextStyle(
    fontFamily: sansFont,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.35,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: sansFont,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.3,
  );

  static const TextStyle bodyXs = TextStyle(
    fontFamily: sansFont,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.05,
    height: 1.25,
  );
}

import 'package:flutter/material.dart';

import 'swiss_tokens.dart';

/// Translates the Swiss tokens into a Material [ThemeData].
///
/// Material's defaults are deliberately overridden rather than embraced: no
/// ripples, no elevation shadows, no rounded surfaces. What survives is the
/// machinery Musify actually needs — text selection, ink-free buttons, a
/// correctly-sized bottom sheet — wearing the chassis.
ThemeData buildMusifyTheme(SwissTokens t) {
  final scheme = ColorScheme(
    brightness: t.brightness,
    primary: t.accent,
    onPrimary: t.accentInk,
    primaryContainer: t.accentSoft,
    onPrimaryContainer: t.ink,
    secondary: t.inkMuted,
    onSecondary: t.bg,
    secondaryContainer: t.surfaceRaised,
    onSecondaryContainer: t.ink,
    tertiary: t.positive,
    onTertiary: t.bg,
    error: t.danger,
    onError: t.bg,
    errorContainer: t.danger.withValues(alpha: 0.16),
    onErrorContainer: t.ink,
    surface: t.surface,
    onSurface: t.ink,
    surfaceContainerLowest: t.bg,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.surfaceRaised,
    surfaceContainerHighest: t.surfaceRaised,
    onSurfaceVariant: t.inkMuted,
    outline: t.hairline,
    outlineVariant: t.hairlineStrong,
    shadow: t.dropShadow,
    scrim: Colors.black,
    inverseSurface: t.ink,
    onInverseSurface: t.bg,
    inversePrimary: t.accent,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: t.hairline,
    dividerTheme: DividerThemeData(color: t.hairline, thickness: 1, space: 1),
    fontFamily: SwissType.sansFont,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    extensions: [t],
    iconTheme: IconThemeData(color: t.ink, size: 20),
    textTheme: TextTheme(
      displayLarge: SwissType.displayXl.copyWith(color: t.ink),
      displayMedium: SwissType.display.copyWith(color: t.ink),
      displaySmall: SwissType.displaySm.copyWith(color: t.ink),
      titleLarge: SwissType.title.copyWith(color: t.ink),
      titleMedium: SwissType.title.copyWith(color: t.ink, fontSize: 14.5),
      bodyLarge: SwissType.body.copyWith(color: t.ink),
      bodyMedium: SwissType.body.copyWith(color: t.inkMuted),
      bodySmall: SwissType.bodySm.copyWith(color: t.inkMuted),
      labelLarge: SwissType.label.copyWith(color: t.inkMuted),
      labelSmall: SwissType.micro.copyWith(color: t.inkFaint),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionColor: t.accentSoft,
      selectionHandleColor: t.accent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearTrackColor: t.hairline,
      circularTrackColor: t.hairline,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accent,
      inactiveTrackColor: t.hairlineStrong.withValues(alpha: 0.45),
      disabledActiveTrackColor: t.inkFaint,
      thumbColor: t.accent,
      overlayColor: t.accentSoft,
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? t.accent : t.inkFaint,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? t.accentSoft
            : t.surfaceSunken,
      ),
      trackOutlineColor: WidgetStateProperty.all(t.hairlineStrong),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.bg,
      modalBackgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      constraints: const BoxConstraints(maxWidth: 720),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surfaceRaised,
      contentTextStyle: SwissType.micro.copyWith(color: t.ink),
      actionTextColor: t.accent,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
        side: BorderSide(color: t.hairline),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        border: Border.all(color: t.hairlineStrong),
        borderRadius: BorderRadius.circular(SwissTokens.radius),
      ),
      textStyle: SwissType.micro.copyWith(color: t.ink),
      waitDuration: const Duration(milliseconds: 500),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

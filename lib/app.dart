import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/swiss_tokens.dart';
import 'core/theme/tactile_decorations.dart';
import 'presentation/cubits/library_cubit.dart';
import 'presentation/cubits/navigation_cubit.dart';
import 'presentation/cubits/player_cubit.dart';
import 'presentation/cubits/settings_cubit.dart';
import 'presentation/shell/main_shell_screen.dart';
import 'services/service_locator.dart';
import 'services/settings_service.dart';

/// Musify's root.
///
/// The three app-wide cubits live here because two of them (navigation and the
/// chassis theme) must exist *above* `MaterialApp`. Screen-scoped cubits are
/// created by the screens that own them.
class MusifyApp extends StatelessWidget {
  const MusifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<NavigationCubit>.value(value: locator<NavigationCubit>()),
        BlocProvider<PlayerCubit>.value(value: locator<PlayerCubit>()),
        BlocProvider<SettingsCubit>.value(value: locator<SettingsCubit>()),
        BlocProvider<LibraryCubit>.value(value: locator<LibraryCubit>()),
      ],
      child: const _MusifyMaterialApp(),
    );
  }
}

class _MusifyMaterialApp extends StatelessWidget {
  const _MusifyMaterialApp();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      // Only the chassis choice needs to reach this level.
      buildWhen: (previous, next) => previous.settings.theme != next.settings.theme,
      builder: (context, state) {
        final theme = switch (state.settings.theme) {
          ChassisTheme.carbon => ThemeMode.dark,
          ChassisTheme.alabaster => ThemeMode.light,
          ChassisTheme.system => ThemeMode.system,
        };

        return MaterialApp(
          title: 'Musify',
          debugShowCheckedModeBanner: false,
          themeMode: theme,
          theme: buildMusifyTheme(SwissTokens.alabaster),
          darkTheme: buildMusifyTheme(SwissTokens.carbon),
          builder: (context, child) {
            // LAW 5 — a runaway system font scale must never be able to break a
            // layout. Musify is a fixed-grid instrument panel, so the scale is
            // clamped rather than allowed to overflow every row.
            return MediaQuery.withClampedTextScaling(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.2,
              child: _GrainOverlay(child: child ?? const SizedBox.shrink()),
            );
          },
          home: const MainShellScreen(),
        );
      },
    );
  }
}

/// The anodised grain sits *behind* the UI and never intercepts a touch.
class _GrainOverlay extends StatelessWidget {
  const _GrainOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: t.bg),
        IgnorePointer(child: SwissGrain(color: t.ink, opacity: t.grainOpacity)),
        child,
      ],
    );
  }
}

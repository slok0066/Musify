import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';
import '../../services/service_locator.dart';
import '../../services/settings_service.dart';
import '../../services/update_service.dart';
import '../cubits/library_cubit.dart';
import '../cubits/navigation_cubit.dart';
import '../cubits/settings_cubit.dart';
import '../screens/credits/full_credit_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/library/library_screen.dart';
import '../screens/onboarding/artist_onboarding_screen.dart';
import '../screens/onboarding/name_onboarding_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/update/update_screen.dart';
import 'mini_player_bar.dart';

/// The four-tab chassis.
///
/// PRD Law 3: the tabs live in an [IndexedStack], so switching is a single
/// integer and nothing — scroll offset, loaded rails, a half-typed query — is
/// ever thrown away. The mini-player card and the nav bar share one docked
/// plane at the bottom of the screen, in that order.
class MainShellScreen extends StatelessWidget {
  const MainShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gate = context.select<
        SettingsCubit,
        ({
          bool loaded,
          bool seenCredits,
          String userName,
          List<String> selectedArtists,
        })>(
      (c) => (
        loaded: c.state.loaded,
        seenCredits: c.state.settings.hasSeenCredits,
        userName: c.state.settings.userName,
        selectedArtists: c.state.settings.selectedArtists,
      ),
    );

    final needsName = gate.userName.trim().isEmpty;
    final needsArtists = gate.selectedArtists.isEmpty;

    // Keep opening onboarding on launch until name is given and artist selection is resolved.
    if (gate.loaded && (needsName || needsArtists)) {
      return _FirstLaunchFlow(
        initialStep: !gate.seenCredits ? 0 : (needsName ? 1 : 2),
      );
    }

    return BlocListener<LibraryCubit, LibraryState>(
      listenWhen: (previous, next) =>
          next.toast != null && next.toast != previous.toast,
      listener: (context, state) {
        final message = state.toast;
        if (message == null) return;
        final t = SwissTokens.of(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: t.surfaceRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: t.hairline, width: 1),
              ),
              content: Text(
                message,
                style: SwissType.label.copyWith(
                  color: t.ink,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              duration: const Duration(milliseconds: 1900),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(
                SwissGrid.gutter,
                0,
                SwissGrid.gutter,
                SwissGrid.md,
              ),
            ),
          );
        context.read<LibraryCubit>().consumeToast();
      },
      child: const _Chassis(),
    );
  }
}


class _Chassis extends StatefulWidget {
  const _Chassis();

  @override
  State<_Chassis> createState() => _ChassisState();
}

class _ChassisState extends State<_Chassis> with WidgetsBindingObserver {
  /// In-app navigation happens here, on a navigator *inside* the chassis, and
  /// not on the root one.
  ///
  /// This is what keeps the transport dock and the tab bar on screen while the
  /// user browses into an album, a playlist or an artist — pushing on the root
  /// navigator is what used to bury the mini-player (and the tab bar) under the
  /// detail screen the moment a song was started from it.
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    NameOnboardingScreen.getLocalMascotUri();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdateSilently();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // A `LATER` answer lasts for the whole session: an update that appeared
      // while the app was backgrounded still raises the dialog, but one the
      // user already waved off never nags again until the next cold start.
      _checkUpdateSilently();
    }
  }

  Future<void> _checkUpdateSilently() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    try {
      final updateService = locator<UpdateService>();
      final info = await updateService.checkForUpdate();
      if (info != null && info.hasUpdate && mounted) {
        showUpdateDialog(context, info);
      }
    } catch (_) {
      // Silent degradation
    }
  }

  void _selectTab(AppTab tab) {
    // A tab tap is a jump home: leave any pushed detail screen behind.
    _navKey.currentState?.popUntil((route) => route.isFirst);
    context.read<NavigationCubit>().select(tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      // LAW 5: the four screens own their own scrolling, so the shell never
      // lets a keyboard resize the whole stack.
      resizeToAvoidBottomInset: true,
      body: NavigatorPopHandler<void>(
        // Android's back button unwinds the shelf before it reaches the OS.
        onPopWithResult: (void result) => _navKey.currentState?.maybePop(),
        child: Navigator(
          key: _navKey,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const _TabStack(),
          ),
        ),
      ),
      bottomNavigationBar: _BottomDock(onTabSelected: _selectTab),
    );
  }
}

/// The four screens, alive in an [IndexedStack] for the life of the shell.
class _TabStack extends StatelessWidget {
  const _TabStack();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationCubit, AppTab>(
      builder: (context, tab) => IndexedStack(
        index: tab.index,
        children: const [
          HomeScreen(),
          SearchScreen(),
          LibraryScreen(),
          SettingsScreen(),
        ],
      ),
    );
  }
}

/// Docked bottom plane: the floating mini-player floats freely over content,
/// and the navigation bar sits across the bottom edge with a Spotify-style
/// translucent pure-black frosted backdrop.
class _BottomDock extends StatelessWidget {
  const _BottomDock({required this.onTabSelected});

  final ValueChanged<AppTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const RepaintBoundary(child: MiniPlayerBar()),
        SwissNavBar(onTabSelected: onTabSelected),
      ],
    );
  }
}

/// Translucent pure-black navigation bar with frosted backdrop blur (Spotify style).
class SwissNavBar extends StatelessWidget {
  const SwissNavBar({this.onTabSelected, super.key});

  /// Lets the chassis unwind its pushed routes before the tab switches.
  final ValueChanged<AppTab>? onTabSelected;

  @override
  Widget build(BuildContext context) {
    final onSelected = onTabSelected;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            border: const Border(
              top: BorderSide(
                color: Color(0x14FFFFFF),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: BlocBuilder<NavigationCubit, AppTab>(
                builder: (context, current) {
                  return Row(
                    children: [
                      for (final tab in AppTab.values)
                        Expanded(
                          child: _NavItem(
                            tab: tab,
                            selected: tab == current,
                            onTap: () {
                              Haptics.tap();
                              if (onSelected != null) {
                                onSelected(tab);
                              } else {
                                context.read<NavigationCubit>().select(tab);
                              }
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.tab, required this.selected, required this.onTap});

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  static IconData _iconFor(AppTab tab) => switch (tab) {
    AppTab.home => Icons.grid_view_rounded,
    AppTab.search => Icons.search_rounded,
    AppTab.library => Icons.folder_open_rounded,
    AppTab.settings => Icons.settings_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final color = selected ? t.ink : t.inkFaint;

    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: Icon(_iconFor(tab), size: 21, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              tab.label,
              style: SwissType.label.copyWith(
                fontSize: 10,
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ],
        ),
      ),
    );
  }
}

class _FirstLaunchFlow extends StatefulWidget {
  const _FirstLaunchFlow({this.initialStep = 0});

  final int initialStep;

  @override
  State<_FirstLaunchFlow> createState() => _FirstLaunchFlowState();
}

class _FirstLaunchFlowState extends State<_FirstLaunchFlow> {
  late int _step;

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: switch (_step) {
        0 => FullCreditScreen(
            key: const ValueKey('credits_step'),
            onDismiss: () => setState(() => _step = 1),
          ),
        1 => NameOnboardingScreen(
            key: const ValueKey('name_step'),
            initialName: context.read<SettingsCubit>().state.settings.userName,
            onComplete: (name) {
              final settings = context.read<SettingsCubit>();
              settings.setUserName(name);
              settings.setHasSeenCredits(true);
              SettingsService.markCreditsSeenNow();
              setState(() => _step = 2);
            },
          ),
        _ => ArtistOnboardingScreen(
            key: const ValueKey('artist_step'),
            onComplete: (artists) {
              final settings = context.read<SettingsCubit>();
              settings.setSelectedArtists(artists);
            },
          ),
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../services/service_locator.dart';
import '../../services/update_service.dart';
import '../cubits/library_cubit.dart';
import '../cubits/navigation_cubit.dart';
import '../cubits/settings_cubit.dart';
import '../screens/credits/full_credit_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/library/library_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/settings/settings_screen.dart';
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
    final hasSeenCredits = context.select<SettingsCubit, bool>(
      (c) => c.state.settings.hasSeenCredits,
    );

    if (!hasSeenCredits) {
      return const FullCreditScreen();
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
      locator<UpdateService>().resetDismissed();
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
        UpdateService.showUpdateDialog(context, info);
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

/// One docked plane: the floating mini-player card over the nav bar, with a
/// soft upward shadow instead of a hard edge.
class _BottomDock extends StatelessWidget {
  const _BottomDock({required this.onTabSelected});

  final ValueChanged<AppTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(
          top: BorderSide(color: t.hairline.withValues(alpha: 0.5), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: t.dropShadow.withValues(alpha: t.isDark ? 0.35 : 0.05),
            blurRadius: 18,
            spreadRadius: -6,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayerBar(),
          SwissNavBar(onTabSelected: onTabSelected),
        ],
      ),
    );
  }
}

/// The 64 px navigation bar — icon over caps label; the live tab carries the
/// signal colour.
class SwissNavBar extends StatelessWidget {
  const SwissNavBar({this.onTabSelected, super.key});

  /// Lets the chassis unwind its pushed routes before the tab switches.
  final ValueChanged<AppTab>? onTabSelected;

  @override
  Widget build(BuildContext context) {
    final onSelected = onTabSelected;

    return SafeArea(
      top: false,
      child: BlocBuilder<NavigationCubit, AppTab>(
        builder: (context, current) {
          return SizedBox(
            height: SwissGrid.navBarHeight,
            child: Row(
              children: [
                for (final tab in AppTab.values)
                  Expanded(
                    child: _NavItem(
                      tab: tab,
                      selected: tab == current,
                      onTap: () => onSelected != null
                          ? onSelected(tab)
                          : context.read<NavigationCubit>().select(tab),
                    ),
                  ),
              ],
            ),
          );
        },
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
    AppTab.home => Icons.grid_view,
    AppTab.search => Icons.search,
    AppTab.library => Icons.folder_open,
    AppTab.settings => Icons.settings,
  };

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final color = selected ? t.accent : t.inkFaint;

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
            Flexible(
              child: Text(
                tab.label,
                style: SwissType.label.copyWith(
                  fontSize: 10,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.9,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

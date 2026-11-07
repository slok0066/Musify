import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';
import '../../services/settings_service.dart';
import '../cubits/navigation_cubit.dart';
import '../cubits/player_cubit.dart';
import '../cubits/settings_cubit.dart';

/// The four dynamic mountain atmosphere phases of the day.
enum TimeOfDayBucket {
  morning(
    assetPath: 'assets/mountains/mountain-morning.webp',
    greeting: 'Good Morning,',
    label: 'DAWN // 05:00 – 12:00',
    accentColor: Color(0xFFF59E0B),
  ),
  noon(
    assetPath: 'assets/mountains/mountain-noon.webp',
    greeting: 'Good Afternoon,',
    label: 'MIDDAY // 12:00 – 17:00',
    accentColor: Color(0xFF38BDF8),
  ),
  evening(
    assetPath: 'assets/mountains/mountain-evening.webp',
    greeting: 'Good Evening,',
    label: 'DUSK // 17:00 – 21:00',
    accentColor: Color(0xFFC084FC),
  ),
  night(
    assetPath: 'assets/mountains/mountain-night.webp',
    greeting: 'Good Night,',
    label: 'NIGHT // 21:00 – 05:00',
    accentColor: Color(0xFF818CF8),
  );

  const TimeOfDayBucket({
    required this.assetPath,
    required this.greeting,
    required this.label,
    required this.accentColor,
  });

  final String assetPath;
  final String greeting;
  final String label;
  final Color accentColor;

  static TimeOfDayBucket current() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return TimeOfDayBucket.morning;
    if (hour >= 12 && hour < 17) return TimeOfDayBucket.noon;
    if (hour >= 17 && hour < 21) return TimeOfDayBucket.evening;
    return TimeOfDayBucket.night;
  }
}

/// Dynamic mountain atmosphere hero header for the Home screen.
///
/// Automatically switches scenery with the time of day:
/// - 05:00–11:59: Morning mountain vista & sunrise amber accent.
/// - 12:00–16:59: Noon daylight mountain peak & cyan azure accent.
/// - 17:00–20:59: Evening twilight mountain glow & sunset violet accent.
/// - 21:00–04:59: Midnight starry mountain peaks & moonlit indigo accent.
///
/// Tuned for low-end devices:
/// - Precached local WebP assets (zero decoding hitching).
/// - Wrapped in [RepaintBoundary] to isolate repainting.
/// - Low-overhead timer (checks once every 60s & on app resume).
/// - Lightweight soundwave visualizer that sleeps when music is paused.
class MountainAtmosphereHero extends StatefulWidget {
  const MountainAtmosphereHero({
    this.onRefresh,
    this.refreshing = false,
    super.key,
  });

  final VoidCallback? onRefresh;
  final bool refreshing;

  @override
  State<MountainAtmosphereHero> createState() => _MountainAtmosphereHeroState();
}

class _MountainAtmosphereHeroState extends State<MountainAtmosphereHero>
    with WidgetsBindingObserver {
  late TimeOfDayBucket _bucket;
  Timer? _timer;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bucket = TimeOfDayBucket.current();
    // Low-overhead periodic check every 60 seconds
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkTime());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      for (final b in TimeOfDayBucket.values) {
        precacheImage(AssetImage(b.assetPath), context);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkTime();
    }
  }

  void _checkTime() {
    final next = TimeOfDayBucket.current();
    if (next != _bucket && mounted) {
      setState(() => _bucket = next);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    final userName = context.select<SettingsCubit, String>(
      (c) => c.state.settings.userName,
    );

    return RepaintBoundary(
      child: SizedBox(
        height: 220 + topPadding,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Mountain Background with smooth cross-fade transition
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 850),
              switchInCurve: Curves.easeInOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              child: Image.asset(
                _bucket.assetPath,
                key: ValueKey<String>(_bucket.assetPath),
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.25),
                width: double.infinity,
                height: double.infinity,
                filterQuality: FilterQuality.medium,
              ),
            ),

            // Ambient Gradient: top subtle vignette, bottom dissolves into app canvas
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.28, 0.65, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.08),
                    t.bg.withValues(alpha: 0.85),
                    t.bg,
                  ],
                ),
              ),
            ),

            // Content Column: Top brand row & Greeting
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SwissGrid.gutter,
                  8,
                  SwissGrid.gutter,
                  12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Brand navigation row
                    Row(
                      children: [
                        _BrandSoundwaves(accentColor: _bucket.accentColor),
                        const SizedBox(width: 8),
                        Text(
                          'MUSIFY',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.2,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.8),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        TactileIconKeycap(
                          icon: t.isDark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          size: 34,
                          iconSize: 17,
                          ghost: true,
                          tint: Colors.white,
                          tooltip: t.isDark
                              ? 'Switch to Light Theme'
                              : 'Switch to Dark Theme',
                          onPressed: () {
                            context.read<SettingsCubit>().setTheme(
                                  t.isDark
                                      ? ChassisTheme.alabaster
                                      : ChassisTheme.carbon,
                                );
                          },
                        ),
                        const SizedBox(width: 4),
                        TactileIconKeycap(
                          icon: Icons.tune,
                          size: 34,
                          iconSize: 17,
                          ghost: true,
                          tint: Colors.white,
                          tooltip: 'Settings & Equalizer',
                          onPressed: () => context
                              .read<NavigationCubit>()
                              .select(AppTab.settings),
                        ),
                        const SizedBox(width: 4),
                        TactileIconKeycap(
                          icon: Icons.sync,
                          size: 34,
                          iconSize: 17,
                          ghost: true,
                          tint: Colors.white,
                          tooltip: 'Reload the feed',
                          onPressed: widget.refreshing ? null : widget.onRefresh,
                        ),
                      ],
                    ),

                    // Greeting Section
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          child: Text(
                            _bucket.greeting,
                            key: ValueKey<String>(_bucket.greeting),
                            style: TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.80),
                              letterSpacing: -0.2,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  blurRadius: 8,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          userName.trim().isNotEmpty ? userName : 'Musify',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.6,
                            height: 1.15,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.85),
                                blurRadius: 12,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 7),
                        // Sleek glowing accent line matching time atmosphere
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeInOut,
                          width: 42,
                          height: 3.5,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              colors: [
                                Colors.white,
                                _bucket.accentColor,
                                _bucket.accentColor.withValues(alpha: 0.0),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _bucket.accentColor.withValues(alpha: 0.45),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dynamic lightweight soundwave bars beside the brand logo.
///
/// Animate when playing; sleep when paused to save battery and GPU on low-end devices.
class _BrandSoundwaves extends StatefulWidget {
  const _BrandSoundwaves({required this.accentColor});

  final Color accentColor;

  @override
  State<_BrandSoundwaves> createState() => _BrandSoundwavesState();
}

class _BrandSoundwavesState extends State<_BrandSoundwaves>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.select<PlayerCubit, bool>(
      (p) => p.state.isPlaying,
    );

    if (isPlaying && !_anim.isAnimating) {
      _anim.repeat(reverse: true);
    } else if (!isPlaying && _anim.isAnimating) {
      _anim.stop();
    }

    const baseHeights = [10.0, 18.0, 22.0, 15.0, 9.0];

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final val = isPlaying ? _anim.value : 0.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < 5; i++) ...[
              _buildBar(
                height: baseHeights[i] * (0.65 + 0.35 * ((val + (i * 0.2)) % 1.0)),
              ),
              if (i < 4) const SizedBox(width: 2.5),
            ],
          ],
        );
      },
    );
  }

  Widget _buildBar({required double height}) {
    return Container(
      width: 2.8,
      height: height.clamp(5.0, 24.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            color: widget.accentColor.withValues(alpha: 0.4),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}


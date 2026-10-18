import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/build_info.dart';
import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../services/settings_service.dart';
import '../../cubits/settings_cubit.dart';

/// Full-screen, one-time credit & welcome page displayed only on first app installation.
class FullCreditScreen extends StatefulWidget {
  const FullCreditScreen({super.key, this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  State<FullCreditScreen> createState() => _FullCreditScreenState();
}

class _FullCreditScreenState extends State<FullCreditScreen> {
  static const String _instaHandle = 'king_togetherness';

  @override
  void initState() {
    super.initState();
    // Record that the credits screen has been presented on first install
    _persistSeenDirect();
  }

  void _persistSeenDirect() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(SettingsService.seenCreditsKey, true);
    }).catchError((_) {});
  }

  void _markSeen(BuildContext context) {
    try {
      context.read<SettingsCubit>().setHasSeenCredits(true);
    } catch (_) {}
    _persistSeenDirect();
  }

  Future<void> _openInstagram(BuildContext context) async {
    HapticFeedback.mediumImpact();
    _markSeen(context);

    // 1. Try native Instagram app first
    final appUri = Uri.parse('instagram://user?username=$_instaHandle');
    try {
      final launched = await launchUrl(
        appUri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (launched) return;
    } catch (_) {}

    // 2. Try launching in external browser
    final webUri = Uri.parse('https://www.instagram.com/$_instaHandle/');
    try {
      final launched = await launchUrl(
        webUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;
    } catch (_) {}

    // 3. Try standard platform launch
    try {
      final launched = await launchUrl(
        webUri,
        mode: LaunchMode.platformDefault,
      );
      if (launched) return;
    } catch (_) {}

    // 4. Fallback to copying handle
    if (context.mounted) _copyHandle(context);
  }

  void _copyHandle(BuildContext context) {
    HapticFeedback.lightImpact();
    Clipboard.setData(const ClipboardData(text: _instaHandle));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied @$_instaHandle to clipboard! ✨',
          style: SwissType.label.copyWith(color: Colors.white, fontSize: 13),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _enterApp(BuildContext context) {
    Haptics.commit();
    _markSeen(context);
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _markSeen(context);
        widget.onDismiss?.call();
      },
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
            child: Column(
              children: [
                const SizedBox(height: SwissGrid.lg),
                // Top Eyebrow
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: t.surfaceSunken,
                        borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
                        border: Border.all(color: t.hairline, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LedDot(active: true, size: 6),
                          const SizedBox(width: 8),
                          Text(
                            'WELCOME TO MUSIFY',
                            style: SwissType.micro.copyWith(
                              color: t.accent,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // App Icon with Ambient Glow
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            t.accent.withValues(alpha: 0.28),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: t.hairline, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SwissGrid.lg),

                // Title (Clean: subtitle text removed as requested)
                Text(
                  'Musify',
                  style: SwissType.display.copyWith(
                    color: t.ink,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: SwissGrid.xl),

                // Creator Card: "Created by a human being called Shlok"
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: t.surfaceRaised,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: t.hairline, width: 1.2),
                    boxShadow: t.raisedShadow,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_rounded, size: 18, color: t.accent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Created by a human being called Shlok',
                          style: SwissType.label.copyWith(
                            color: t.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SwissGrid.md),

                // Instagram Profile Card
                GestureDetector(
                  onTap: () => _openInstagram(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: t.surfaceSunken,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: t.hairline, width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF833AB4),
                                Color(0xFFFD1D1D),
                                Color(0xFFFCB045),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFD1D1D).withValues(alpha: 0.28),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@$_instaHandle',
                                style: SwissType.label.copyWith(
                                  color: t.ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Follow on Instagram',
                                style: SwissType.micro.copyWith(
                                  color: t.inkMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TactileIconKeycap(
                          icon: Icons.copy_rounded,
                          size: 40,
                          iconSize: 18,
                          tooltip: 'Copy handle',
                          onPressed: () => _copyHandle(context),
                        ),
                        const SizedBox(width: 6),
                        TactileIconKeycap(
                          icon: Icons.open_in_new_rounded,
                          size: 40,
                          iconSize: 18,
                          tooltip: 'Open Instagram',
                          onPressed: () => _openInstagram(context),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Enter Musify Button
                TactileKeycap(
                  height: 52,
                  width: double.infinity,
                  accent: true,
                  onPressed: () => _enterApp(context),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'ENTER MUSIFY',
                          style: SwissType.label.copyWith(
                            color: t.accentInk,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 18, color: t.accentInk),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: SwissGrid.md),

                // Version stamp
                Text(
                  kBuildLabel,
                  style: SwissType.micro.copyWith(color: t.inkFaint, fontSize: 10),
                ),
                const SizedBox(height: SwissGrid.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

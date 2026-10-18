import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/build_info.dart';
import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';

/// A cute, minimal, and clean credits sheet celebrating the creator.
class CreditsSheet extends StatelessWidget {
  const CreditsSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreditsSheet(),
    );
  }

  static const String _instaHandle = 'king_togetherness';

  Future<void> _openInstagram(BuildContext context) async {
    HapticFeedback.mediumImpact();
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

    // 4. Fallback: copy to clipboard
    if (context.mounted) {
      _copyHandle(context);
    }
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

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return Container(
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: t.hairline, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 14,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cute Top Grab Handle
          Container(
            width: 42,
            height: 4.5,
            decoration: BoxDecoration(
              color: t.inkFaint.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 22),

          // Glowing App Icon
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      t.accent.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: t.hairline, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Title & Subtitle
          Text(
            'Musify',
            style: SwissType.displaySm.copyWith(
              color: t.ink,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Architectural Minimalism · Pure 8D Audio',
            style: SwissType.micro.copyWith(
              color: t.inkMuted,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 20),

          // Main Hero Card: "Created by a human being called Shlok"
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.hairline, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(Icons.favorite_rounded, size: 16, color: t.accent),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'Created by a human being called Shlok',
                    style: SwissType.label.copyWith(
                      color: t.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Instagram Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.hairline, width: 1),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Cute Instagram Gradient Icon Box
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
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
                            color: const Color(0xFFFD1D1D).withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 22,
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
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Follow on Instagram',
                            style: SwissType.micro.copyWith(
                              color: t.inkFaint,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Copy handle button
                    TactileIconKeycap(
                      icon: Icons.copy_rounded,
                      size: 38,
                      iconSize: 18,
                      onPressed: () => _copyHandle(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Tap to open button
                TactileKeycap(
                  height: 44,
                  accent: true,
                  onPressed: () => _openInstagram(context),
                  child: Center(
                    child: Text(
                      'OPEN INSTAGRAM',
                      style: SwissType.label.copyWith(
                        color: t.accentInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Telemetry Footer
          Text(
            kBuildLabel,
            style: SwissType.micro.copyWith(
              color: t.inkFaint,
              fontSize: 10.5,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

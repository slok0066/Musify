import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:masko_player/masko_player.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';

/// Clean and minimal Name Onboarding Screen shown after the Credit page.
///
/// Features the waving Masko mascot above a minimal name input field,
/// allowing the user to personalize their home mountain vista greeting.
class NameOnboardingScreen extends StatefulWidget {
  const NameOnboardingScreen({
    required this.onComplete,
    this.initialName = '',
    super.key,
  });

  final ValueChanged<String> onComplete;
  final String initialName;

  static const String mascotHevc =
      'https://assets.masko.ai/fc3fdf/mascot-20b3/waves-hello-0b2b5650.mov';
  static const String mascotStacked =
      'https://assets.masko.ai/fc3fdf/mascot-20b3/waves-hello-4813c530.mp4';

  static String? _cachedLocalMascotUri;

  /// Returns the local file URI for the mascot video, extracting it from
  /// bundled assets into the app cache directory if not already extracted.
  /// This eliminates the 3MB remote network download, allowing the mascot
  /// to load immediately.
  static Future<String> getLocalMascotUri() async {
    if (_cachedLocalMascotUri != null) return _cachedLocalMascotUri!;

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/musify_mascot_waves.mp4');
      if (await file.exists() && await file.length() > 0) {
        _cachedLocalMascotUri = file.uri.toString();
        return _cachedLocalMascotUri!;
      }

      final data = await rootBundle.load('assets/mascot/waves-hello.mp4');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      _cachedLocalMascotUri = file.uri.toString();
      return _cachedLocalMascotUri!;
    } catch (_) {
      return mascotStacked;
    }
  }

  @override
  State<NameOnboardingScreen> createState() => _NameOnboardingScreenState();
}

class _NameOnboardingScreenState extends State<NameOnboardingScreen> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String _stackedMascot = NameOnboardingScreen._cachedLocalMascotUri ?? NameOnboardingScreen.mascotStacked;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _loadMascot();
  }

  Future<void> _loadMascot() async {
    if (NameOnboardingScreen._cachedLocalMascotUri != null) return;
    final uri = await NameOnboardingScreen.getLocalMascotUri();
    if (mounted && uri != _stackedMascot) {
      setState(() => _stackedMascot = uri);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      Haptics.tap();
      return;
    }
    Haptics.commit();
    widget.onComplete(name);
  }

  Widget _buildMascot(BuildContext context) {
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    return SizedBox(
      width: 190,
      height: 190,
      child: isMobile
          ? MaskoView(
              clip: MaskoClipFiles(
                hevc: NameOnboardingScreen.mascotHevc,
                stacked: _stackedMascot,
              ),
              sound: false,
              autoPlay: true,
            )
          : Image.asset(
              'assets/mascot/waves-hello-poster.webp',
              width: 190,
              height: 190,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Eyebrow tag
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: t.surfaceSunken,
                      borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
                      border: Border.all(color: t.hairline, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: t.accent,
                            boxShadow: t.ledGlow(t.accent, strength: 0.6),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '// INITIALIZE IDENTITY',
                          style: SwissType.label.copyWith(
                            color: t.inkMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Mascot animation above the name box
                  _buildMascot(context),

                  const SizedBox(height: 16),

                  // Headline
                  Text(
                    "What's your name?",
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: t.ink,
                      letterSpacing: -0.6,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    'Your name personalizes your daily mountain vista & morning greetings.',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: t.inkMuted,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 28),

                  // Minimal Name Input Box
                  Container(
                    decoration: BoxDecoration(
                      color: t.surfaceSunken,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: t.hairline, width: 1.2),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 20,
                          color: t.inkMuted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            textCapitalization: TextCapitalization.words,
                            style: TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: t.ink,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Enter your name',
                              hintStyle: TextStyle(
                                fontFamily: 'PlusJakartaSans',
                                color: t.inkFaint,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // CTA Button
                  TactileKeycap(
                    height: 52,
                    width: double.infinity,
                    accent: true,
                    onPressed: _submit,
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
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: t.accentInk,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

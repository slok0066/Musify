import 'package:flutter/material.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';

/// The shared empty / offline / error plate.
///
/// Every "nothing here" moment in Musify is the same quiet card: an ordinal, a
/// headline, one line of plain instruction and an optional keycap — never a
/// spinner, never a red box (PRD Laws 4 and 5).
class MusifyStatePanel extends StatelessWidget {
  const MusifyStatePanel({
    required this.index,
    required this.title,
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.accent = false,
    this.compact = false,
    super.key,
  });

  final String index;
  final String title;
  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: SwissGrid.gutter,
        vertical: compact ? SwissGrid.lg : SwissGrid.xxl,
      ),
      child: Container(
        padding: EdgeInsets.all(compact ? SwissGrid.lg : SwissGrid.xl),
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          borderRadius: BorderRadius.circular(SwissTokens.radiusLg),
          border: Border.all(color: t.hairline, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                LedDot(active: accent, size: 6),
                const SizedBox(width: SwissGrid.sm),
                Text(
                  index,
                  style: SwissType.label.copyWith(color: accent ? t.accent : t.inkFaint),
                ),
                const Spacer(),
                if (icon != null)
                  Icon(icon, size: 15, color: t.inkFaint),
              ],
            ),
            SizedBox(height: compact ? SwissGrid.sm : SwissGrid.md),
            Text(
              title,
              style: SwissType.displaySm.copyWith(color: t.ink, fontSize: compact ? 18 : 21),
            ),
            const SizedBox(height: SwissGrid.xs),
            Text(
              message,
              style: SwissType.bodySm.copyWith(color: t.inkMuted),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? SwissGrid.md : SwissGrid.lg),
              TactileKeycap(
                accent: accent,
                height: 38,
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The offline strip that sits above Home when there is no transport.
class OfflineStrip extends StatelessWidget {
  const OfflineStrip({required this.onRetry, this.note, super.key});

  final VoidCallback onRetry;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(SwissGrid.gutter, 0, SwissGrid.gutter, SwissGrid.md),
      padding: const EdgeInsets.all(SwissGrid.md),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        border: Border.all(color: t.hairline, width: 1),
        borderRadius: BorderRadius.circular(SwissTokens.radius),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 15, color: t.warning),
          const SizedBox(width: SwissGrid.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'NO TRANSPORT // OFFLINE VAULT ACTIVE',
                  style: SwissType.label.copyWith(color: t.ink),
                ),
                if (note != null)
                  Text(note!, style: SwissType.micro.copyWith(color: t.inkFaint)),
              ],
            ),
          ),
          const SizedBox(width: SwissGrid.sm),
          TactileKeycap(
            accent: true,
            height: 32,
            onPressed: onRetry,
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }
}

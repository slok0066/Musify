import 'package:flutter/material.dart';

import '../../core/theme/swiss_tokens.dart';
import '../cubits/navigation_cubit.dart';

/// The header every tab opens with.
///
/// Architectural grammar: the MUSIFY wordmark anchors the top row with the
/// screen's controls sitting at the right edge; a `// TAB` eyebrow with a
/// signal dot opens the second row while live telemetry reads against the
/// right margin. When a screen passes a display [title] it follows the
/// eyebrow, and the full-width [actions] strip (filter pills, a search field)
/// closes the block.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.tab,
    this.title,
    this.subtitle,
    this.trailing,
    this.actions,
    super.key,
  });

  final AppTab tab;

  /// Optional display title (`System Settings`). Most tabs run without one —
  /// the eyebrow carries the identity.
  final String? title;

  /// Telemetry / counters, right-aligned next to the eyebrow.
  final String? subtitle;

  /// Sits at the right of the wordmark row (icon keycaps, switches).
  final Widget? trailing;

  /// A full-width row under the eyebrow (filter pills, a search field).
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return Container(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(
          bottom: BorderSide(color: t.hairline.withValues(alpha: 0.5), width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              SwissGrid.gutter, SwissGrid.sm, SwissGrid.gutter, SwissGrid.sm + 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- wordmark row -------------------------------------------
              Row(
                children: [
                  Icon(Icons.graphic_eq, size: 20, color: t.accent),
                  const SizedBox(width: 8),
                  Text(
                    'MUSIFY',
                    style: SwissType.label.copyWith(
                      color: t.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: SwissGrid.sm + 4),
              // ---- eyebrow row --------------------------------------------
              Row(
                children: [
                  Text(
                    '// ${tab.label}',
                    style: SwissType.label.copyWith(
                      color: t.inkMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.accent,
                      boxShadow: t.ledGlow(t.accent, strength: 0.5),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(width: SwissGrid.md),
                    Expanded(
                      child: Text(
                        subtitle!,
                        style: SwissType.micro.copyWith(color: t.inkFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ],
              ),
              if (title != null) ...[
                const SizedBox(height: 6),
                Text(
                  title!,
                  style: SwissType.display.copyWith(color: t.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (actions != null) ...[
                const SizedBox(height: SwissGrid.sm + 4),
                actions!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The horizontal pill strip used by Home's filters, Search's facets and the
/// Library's views. Scrolls, never wraps, keeps a 20 px gutter.
class PillStrip extends StatelessWidget {
  const PillStrip({required this.children, this.padding, super.key});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: SwissGrid.sm),
        itemBuilder: (context, i) => Center(child: children[i]),
      ),
    );
  }
}

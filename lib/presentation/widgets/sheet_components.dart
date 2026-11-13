import 'package:flutter/material.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';

/// Standard sheet container with flat background surface, crisp top hairline radius,
/// and safe-area padding.
class MusifySheetShell extends StatelessWidget {
  const MusifySheetShell({
    required this.child,
    this.maxHeightFactor = 0.86,
    super.key,
  });

  final Widget child;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final height = MediaQuery.sizeOf(context).height * maxHeightFactor;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height, minWidth: double.infinity),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(32),
          ),
        ),
        child: SafeArea(top: false, child: child),
      ),
    );
  }
}

/// Unified header for modal bottom sheets with eyebrow dot and optional trailing widget.
class MusifySheetHeader extends StatelessWidget {
  const MusifySheetHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        SwissGrid.lg,
        SwissGrid.md,
        SwissGrid.md,
        SwissGrid.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.accent,
            ),
          ),
          const SizedBox(width: SwissGrid.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.toUpperCase(),
                  style: SwissType.label.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!.toUpperCase(),
                    style: SwissType.micro.copyWith(color: t.inkMuted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Standard full-width action row for bottom sheets.
class SwissSheetActionTile extends StatelessWidget {
  const SwissSheetActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
    this.enabled = true,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  /// Accepts either a `bool` (true -> t.accent) or a `Color` directly (e.g. `t.danger`).
  final dynamic accent;
  final bool enabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final Color itemColor;
    if (!enabled) {
      itemColor = t.inkFaint;
    } else if (accent is Color) {
      itemColor = accent as Color;
    } else if (accent == true) {
      itemColor = t.accent;
    } else {
      itemColor = t.ink;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled
            ? () {
                Haptics.tap();
                onTap();
              }
            : null,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SwissGrid.lg,
            vertical: SwissGrid.md + 2,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.hairline, width: 1)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: itemColor),
              const SizedBox(width: SwissGrid.md),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: SwissType.label.copyWith(
                    color: itemColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// A label + hint + physical switch row for settings and calibration sheets.
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: SwissGrid.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: SwissType.label.copyWith(
                    color: enabled ? t.ink : t.inkFaint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: SwissType.micro.copyWith(
                    color: t.inkFaint,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: SwissGrid.sm),
          TactileSwitch(
            value: value,
            onChanged: enabled ? onChanged : (_) {},
          ),
        ],
      ),
    );
  }
}

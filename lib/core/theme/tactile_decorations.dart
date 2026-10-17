import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'swiss_tokens.dart';

/// Global haptics gate.
///
/// `SettingsCubit` writes to this, every hardware control reads it. Keeping it
/// as a plain notifier (instead of a widget dependency) means haptics work
/// identically in dialogs, sheets and the notification-driven code paths.
abstract final class Haptics {
  static bool enabled = true;

  static void tap() {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  static void press() {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }

  static void commit() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  static void reject() {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
  }
}

/// The obsidian canvas texture.
///
/// A deterministic, near-invisible speckle that stops large flat fills from
/// reading as dead pixels on OLED. Painted once behind the app and cached in a
/// [RepaintBoundary].
class SwissGrain extends StatelessWidget {
  const SwissGrain({required this.color, required this.opacity, super.key});

  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GrainPainter(color: color.withValues(alpha: opacity)),
        size: Size.infinite,
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // Fixed 3px lattice: looks like brushed stone grain, never like noise.
    const step = 3.0;
    final cols = (size.width / step).ceil();
    final rows = (size.height / step).ceil();
    var seed = 0x9E3779B9;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        if (seed % 11 != 0) continue;
        final jitterX = ((seed >> 3) % 3) - 1;
        final jitterY = ((seed >> 7) % 3) - 1;
        canvas.drawRect(
          Rect.fromLTWH(x * step + jitterX, y * step + jitterY, 1, 1),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A soft panel floating on the canvas — a card, a rail body, a sheet slab.
class SwissPanel extends StatelessWidget {
  const SwissPanel({
    required this.child,
    this.padding,
    this.color,
    this.borderColor,
    this.radius = SwissTokens.radiusLg,
    this.raised = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? (raised ? t.surfaceRaised : t.surface),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? t.hairline, width: 1),
        boxShadow: raised ? t.raisedShadow : null,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
  }
}

/// A shallow well — search fields, readout bays, recessed control strips.
///
/// Unlike the old machined inset, this is a soft architectural recess: a
/// slightly deeper fill inside a hairline, nothing more.
class RecessedWell extends StatelessWidget {
  const RecessedWell({
    required this.child,
    this.padding,
    this.radius = SwissTokens.radiusLg,
    this.depth = 1,
    this.fill,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double depth;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? t.surfaceSunken,
        borderRadius: r,
        border: Border.all(color: t.hairline, width: depth),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(SwissGrid.md),
        child: child,
      ),
    );
  }
}

/// The primary control: a soft pill.
///
/// Rests flat on its plane and dips 1px when pressed. Accent fills carry the
/// single signal colour; ghost pills are bare icons with no chrome.
class TactileKeycap extends StatefulWidget {
  const TactileKeycap({
    required this.child,
    this.onPressed,
    this.padding = const EdgeInsets.symmetric(
        horizontal: SwissGrid.lg, vertical: SwissGrid.sm + 1),
    this.width,
    this.height,
    this.radius = SwissTokens.radius,
    this.ghost = false,
    this.accent = false,
    this.glow = false,
    this.borderColor,
    this.foregroundColor,
    this.tooltip,
    this.enabled = true,
    this.hapticOnPress = true,
    super.key,
  });

  /// Solid accent pill — reserved for the primary action on screen
  /// (8D AUDIO, PLAY ALL).
  final bool accent;

  /// Adds the filament bloom. Only for latched/active hardware.
  final bool glow;

  /// A bare icon/text control with no fill of its own.
  final bool ghost;

  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  final double radius;
  final Color? borderColor;

  /// Overrides the icon/text colour — used by ghost pills that carry accent
  /// chrome (the transport play button).
  final Color? foregroundColor;
  final String? tooltip;
  final bool enabled;
  final bool hapticOnPress;

  @override
  State<TactileKeycap> createState() => _TactileKeycapState();
}

class _TactileKeycapState extends State<TactileKeycap> {
  bool _down = false;

  bool get _interactive => widget.enabled && widget.onPressed != null;

  void _setDown(bool value) {
    if (!_interactive || _down == value) return;
    setState(() => _down = value);
    if (widget.hapticOnPress) Haptics.press();
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    final fill = widget.ghost
        ? (_down ? t.hairline.withValues(alpha: 0.6) : Colors.transparent)
        : widget.accent
            ? (_down ? t.accent.withValues(alpha: 0.82) : t.accent)
            : (_down ? t.keycapTopPressed : t.keycapTop);

    final fg = widget.foregroundColor ??
        (widget.ghost
            ? (_down ? t.ink : t.inkMuted)
            : widget.accent
                ? t.accentInk
                : t.ink);

    final border = widget.borderColor ??
        (widget.ghost || widget.accent
            ? Colors.transparent
            : t.hairline.withValues(alpha: 0.7));

    final shape = BorderRadius.circular(
      widget.height != null
          ? widget.height! / 2
          : (widget.radius != SwissTokens.radius
              ? widget.radius
              : SwissTokens.radiusFull),
    );

    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      transform: Matrix4.translationValues(0, _down ? 1 : 0, 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: shape,
        border: Border.all(color: border, width: 1),
        boxShadow: widget.glow && !_down
            ? t.ledGlow(t.accent, strength: 0.85)
            : null,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: fg,
          fontFamily: SwissType.monoFont,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
        child: IconTheme.merge(
          data: IconThemeData(size: 19, color: fg),
          child: widget.child,
        ),
      ),
    );

    Widget result = Opacity(
      opacity: _interactive ? 1 : 0.42,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setDown(true),
        onTapUp: (_) => _setDown(false),
        onTapCancel: () => _setDown(false),
        onTap: _interactive ? widget.onPressed : null,
        child: body,
      ),
    );

    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return result;
  }
}

/// A circular, icon-only keycap. Used for transport controls and toolbar rows.
class TactileIconKeycap extends StatelessWidget {
  const TactileIconKeycap({
    required this.icon,
    this.onPressed,
    this.size = 40,
    this.iconSize = 19,
    this.accent = false,
    this.glow = false,
    this.ghost = false,
    this.tint,
    this.active = false,
    this.enabled = true,
    this.tooltip,
    this.hapticOnPress = true,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool accent;
  final bool glow;
  final bool ghost;
  final Color? tint;
  final bool active;
  final bool enabled;
  final String? tooltip;
  final bool hapticOnPress;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return TactileKeycap(
      onPressed: onPressed,
      width: size,
      height: size,
      padding: EdgeInsets.zero,
      radius: size / 2,
      accent: accent,
      glow: glow,
      ghost: ghost,
      foregroundColor: tint,
      enabled: enabled,
      tooltip: tooltip,
      hapticOnPress: hapticOnPress,
      borderColor: active ? t.accent.withValues(alpha: 0.65) : null,
      child: Icon(icon, size: iconSize),
    );
  }
}

/// The signal LED.
class LedDot extends StatelessWidget {
  const LedDot({
    this.active = false,
    this.size = 7,
    this.color,
    super.key,
  });

  final bool active;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final c = color ?? t.accent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? c : t.inkFaint.withValues(alpha: 0.35),
        border: Border.all(
          color: active ? c : t.hairline,
          width: 1,
        ),
        boxShadow: active ? t.ledGlow(c) : null,
      ),
    );
  }
}

/// The soft hairline that separates planes.
class Hairline extends StatelessWidget {
  const Hairline(
      {this.color, this.indent = 0, this.vertical = false, super.key});

  final Color? color;
  final double indent;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final line = Container(
      color: color ?? t.hairline,
      width: vertical ? 1 : null,
      height: vertical ? null : 1,
    );
    if (indent == 0) return vertical ? line : SizedBox(height: 1, child: line);
    return vertical
        ? Padding(padding: EdgeInsets.only(top: indent), child: line)
        : Padding(padding: EdgeInsets.only(left: indent), child: line);
  }
}

/// A compact architectural section header:
/// `01  TRENDING NOW                    12 ITEMS`.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.index,
    required this.title,
    this.trailing,
    this.subtitle,
    super.key,
  });

  final String index;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SwissGrid.gutter, SwissGrid.xl, SwissGrid.gutter, SwissGrid.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (index.isNotEmpty) ...[
                Text(
                  index,
                  style: SwissType.label.copyWith(color: t.accent),
                ),
                const SizedBox(width: SwissGrid.sm),
              ],
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: SwissType.label.copyWith(
                    color: t.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: SwissGrid.sm),
                trailing!,
              ] else if (subtitle != null) ...[
                const SizedBox(width: SwissGrid.sm),
                Text(
                  subtitle!.toUpperCase(),
                  style: SwissType.micro.copyWith(color: t.inkFaint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          if (subtitle != null && trailing != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                subtitle!,
                style: SwissType.micro.copyWith(color: t.inkFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A technical badge: `320 KBPS`, `OFFLINE`, `8D` — a soft pill.
class SwissBadge extends StatelessWidget {
  const SwissBadge({
    required this.text,
    this.color,
    this.filled = false,
    this.icon,
    super.key,
  });

  final String text;
  final Color? color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final c = color ?? t.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: filled ? c : t.surfaceSunken,
        borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
        border: Border.all(
            color: filled ? c : t.hairline, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: filled ? t.bg : c),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: SwissType.micro.copyWith(
              color: filled ? t.bg : c,
              fontSize: 9,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Filter pill (search categories, library filters, quick filters, presets).
class SwissPill extends StatelessWidget {
  const SwissPill({
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
    this.dense = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              Haptics.tap();
              onTap!();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 14 : 18,
          vertical: dense ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: selected ? t.accent : t.surfaceRaised,
          borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
          border: Border.all(
            color: selected ? t.accent : t.hairline,
            width: 1,
          ),
          boxShadow: selected ? t.ledGlow(t.accent, strength: 0.45) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 5),
            ],
            Text(
              label.toUpperCase(),
              style: SwissType.label.copyWith(
                color: selected ? t.accentInk : t.inkMuted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: dense ? 10.5 : 11,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A latched hardware toggle — a small pill switch that stays down.
class TactileSwitch extends StatelessWidget {
  const TactileSwitch({
    required this.value,
    required this.onChanged,
    this.width = 46,
    this.height = 26,
    this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final double width;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Semantics(
      label: semanticLabel,
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.press();
          onChanged(!value);
        },
        child: RecessedWell(
          radius: height / 2,
          padding: EdgeInsets.zero,
          child: Container(
            width: width,
            height: height,
            padding: const EdgeInsets.all(3),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              width: height - 6,
              height: height - 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? t.accent : t.inkFaint,
                border: Border.all(
                  color: value ? t.accent : t.hairlineStrong,
                ),
                boxShadow: value ? t.ledGlow(t.accent, strength: 0.7) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft "back" affordance used on detail screens: `← 02 // SEARCH`.
class SwissBackBar extends StatelessWidget {
  const SwissBackBar({
    required this.title,
    this.onBack,
    this.trailing,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
          SwissGrid.sm, SwissGrid.sm, SwissGrid.gutter, SwissGrid.sm),
      color: t.bg,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            TactileIconKeycap(
              icon: Icons.arrow_back,
              size: 40,
              ghost: true,
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
            ),
            const SizedBox(width: SwissGrid.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: SwissType.micro.copyWith(color: t.accent),
                    ),
                  Text(
                    title,
                    style: SwissType.title.copyWith(color: t.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Draws a soft "skeleton" while content loads — never a spinner that blocks
/// the layout.
class SwissSkeleton extends StatelessWidget {
  const SwissSkeleton({
    this.width,
    this.height = 12,
    this.radius = SwissTokens.radius,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: t.inkFaint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A horizontal ruler/scale motif — pure ornament used under headers and
/// in empty states to keep the measured read going.
class SwissRule extends StatelessWidget {
  const SwissRule({this.divisions = 24, this.height = 8, super.key});

  final int divisions;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(divisions, (i) {
          final major = i % 4 == 0;
          return Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 1,
                height: major ? height : height * 0.45,
                color: major ? t.hairlineStrong : t.hairline,
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Marquee for long track titles in the docked mini-player.
///
/// Scrolls only when the text actually overflows, and pauses on the ends, so
/// short titles stay perfectly still.
class TextMarquee extends StatefulWidget {
  const TextMarquee({
    required this.text,
    required this.style,
    this.velocity = 26,
    this.pauseAfter = const Duration(milliseconds: 1400),
    this.gap = 48,
    super.key,
  });

  final String text;
  final TextStyle style;
  final double velocity;
  final Duration pauseAfter;
  final double gap;

  @override
  State<TextMarquee> createState() => _TextMarqueeState();
}

class _TextMarqueeState extends State<TextMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  double _textWidth = 0;
  double _viewWidth = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    if (_textWidth <= 0 || _viewWidth <= 0) return;
    final overflow = _textWidth - _viewWidth;
    if (overflow <= 2) {
      _controller.stop();
      _controller.value = 0;
      return;
    }
    final travel = overflow + widget.gap;
    final scrollSeconds = travel / widget.velocity;
    final pauseSeconds = widget.pauseAfter.inMilliseconds / 1000;
    _controller.duration = Duration(
      milliseconds: ((scrollSeconds + pauseSeconds * 2) * 1000).round(),
    );
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    // Measuring with a TextPainter keeps the marquee synchronous: no probe
    // widget, no extra frame, no layout jump when the title changes.
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();

    return LayoutBuilder(
      builder: (context, constraints) {
        _textWidth = painter.width;
        _viewWidth = constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sync();
        });
        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Transform.translate(
                offset: Offset(-_offset(), 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.text,
                    style: widget.style,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  double _offset() {
    final overflow = _textWidth - _viewWidth;
    if (overflow <= 2) return 0;
    final travel = overflow + widget.gap;
    final total = _controller.duration?.inMilliseconds ?? 1;
    final pause = widget.pauseAfter.inMilliseconds;
    final scrollMs = math.max(1.0, total - pause * 2);
    final t = _controller.value * total;
    if (t < pause) return 0;
    if (t > pause + scrollMs) return travel;
    return ((t - pause) / scrollMs) * travel;
  }
}

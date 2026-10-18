import 'package:flutter/material.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';
import '../../core/utils/formatters.dart';

/// The soft slider: a quiet 4 px groove, the signal fill, and a bead that
/// visibly travels.
///
/// Used for every continuous control in Settings and for the seekbar, so the
/// whole app scrubs with the same feel.
class TactileSlider extends StatefulWidget {
  const TactileSlider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.onChangeStart,
    this.onChangeEnd,
    this.height = 34,
    this.thumbWidth = 14,
    this.thumbHeight = 26,
    this.steps,
    this.enabled = true,
    this.leading,
    this.trailing,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final double height;
  final double thumbWidth;
  final double thumbHeight;

  /// Optional discrete stops (used by the orbit-speed and crossfade controls).
  final int? steps;
  final bool enabled;
  final Widget? leading;
  final Widget? trailing;

  @override
  State<TactileSlider> createState() => _TactileSliderState();
}

class _TactileSliderState extends State<TactileSlider> {
  bool _dragging = false;

  double get _fraction {
    final span = widget.max - widget.min;
    if (span <= 0) return 0;
    return ((widget.value - widget.min) / span).clamp(0.0, 1.0);
  }

  void _emit(double localX, double width) {
    if (!widget.enabled || width <= 0) return;
    var fraction = (localX / width).clamp(0.0, 1.0);
    if (widget.steps != null && widget.steps! > 1) {
      fraction = (fraction * (widget.steps! - 1)).round() / (widget.steps! - 1);
    }
    widget.onChanged(widget.min + fraction * (widget.max - widget.min));
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = widget.height;
        final grooveWidth = constraints.maxWidth;
        final bead = widget.thumbHeight.clamp(12.0, 18.0);

        return SizedBox(
          height: trackHeight,
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: SwissGrid.sm),
              ],
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    if (!widget.enabled) return;
                    setState(() => _dragging = true);
                    widget.onChangeStart?.call();
                    _emit(details.localPosition.dx, grooveWidth);
                  },
                  onHorizontalDragUpdate: (details) {
                    _emit(details.localPosition.dx, grooveWidth);
                  },
                  onHorizontalDragEnd: (_) {
                    if (!widget.enabled) return;
                    setState(() => _dragging = false);
                    widget.onChangeEnd?.call(widget.value);
                    Haptics.tap();
                  },
                  onHorizontalDragCancel: () => setState(() => _dragging = false),
                  onTapDown: (details) {
                    if (!widget.enabled) return;
                    widget.onChangeStart?.call();
                    _emit(details.localPosition.dx, grooveWidth);
                    widget.onChangeEnd?.call(widget.value);
                  },
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // The quiet groove.
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: t.hairlineStrong.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // The fill.
                      FractionallySizedBox(
                        widthFactor: _fraction,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: widget.enabled ? t.accent : t.inkFaint,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // The bead thumb: ink shell, canvas pip.
                      Align(
                        alignment: Alignment(_fraction * 2 - 1, 0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 70),
                          width: bead,
                          height: bead,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.enabled ? t.ink : t.inkFaint,
                            boxShadow: _dragging ? t.raisedShadow : null,
                          ),
                          child: Center(
                            child: Container(
                              width: bead * 0.36,
                              height: bead * 0.36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: t.bg,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: SwissGrid.sm),
                widget.trailing!,
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A label + readout row for a settings slider: `ORBIT SPEED        10.0 S`.
class SliderReadout extends StatelessWidget {
  const SliderReadout({
    required this.label,
    required this.readout,
    this.hint,
    super.key,
  });

  final String label;
  final String readout;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: SwissType.label.copyWith(color: t.ink)),
              if (hint != null)
                Text(hint!, style: SwissType.micro.copyWith(color: t.inkFaint)),
            ],
          ),
        ),
        const SizedBox(width: SwissGrid.sm),
        Text(
          readout,
          style: SwissType.monoStrong.copyWith(color: t.accent, fontSize: 12),
        ),
      ],
    );
  }
}

/// Custom track shape that removes default horizontal paddings so the seekbar spans
/// edge-to-edge across its container.
class SwissSeekBarTrackShape extends RoundedRectSliderTrackShape {
  const SwissSeekBarTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4.0;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

/// The Swiss bead thumb: ink shell around a canvas pip with subtle elevation.
class SwissSliderThumbShape extends SliderComponentShape {
  const SwissSliderThumbShape({
    this.thumbRadius = 7.0,
    this.pipRadius = 2.5,
    required this.thumbColor,
    required this.pipColor,
  });

  final double thumbRadius;
  final double pipRadius;
  final Color thumbColor;
  final Color pipColor;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(thumbRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final dragging = activationAnimation.value > 0.05;
    final radius = dragging ? thumbRadius + 1.5 : thumbRadius;

    // Drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: dragging ? 0.35 : 0.18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, dragging ? 4.0 : 2.5);
    canvas.drawCircle(center.translate(0, 1.2), radius, shadowPaint);

    // Ink shell
    final shellPaint = Paint()..color = thumbColor;
    canvas.drawCircle(center, radius, shellPaint);

    // Canvas pip
    final pipPaint = Paint()..color = pipColor;
    canvas.drawCircle(center, pipRadius, pipPaint);
  }
}

/// The Now Playing seekbar: buffered band, playhead, and continuous drag preview.
/// Powered by Flutter's Slider engine to guarantee uninterrupted dragging inside
/// vertical scroll views.
class TactileSeekBar extends StatefulWidget {
  const TactileSeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    this.buffered = 0,
    this.enabled = true,
    super.key,
  });

  final Duration position;
  final Duration duration;

  /// 0.0–1.0.
  final double buffered;
  final ValueChanged<Duration> onSeek;
  final bool enabled;

  @override
  State<TactileSeekBar> createState() => _TactileSeekBarState();
}

class _TactileSeekBarState extends State<TactileSeekBar> {
  double? _dragMilliseconds;

  Duration get _displayed {
    if (_dragMilliseconds == null) return widget.position;
    return Duration(milliseconds: _dragMilliseconds!.round());
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final totalMs = widget.duration.inMilliseconds.toDouble();
    final canSeek = widget.enabled && totalMs > 0;
    final dragging = _dragMilliseconds != null;

    final currentMs = canSeek
        ? (_dragMilliseconds ?? widget.position.inMilliseconds.toDouble())
            .clamp(0.0, totalMs)
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 30,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Quiet background groove
              Container(
                height: 4,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: t.hairlineStrong.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 2. Buffered progress band
              FractionallySizedBox(
                widthFactor: widget.buffered.clamp(0.0, 1.0),
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.hairlineStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 3. Fluid, scroll-proof Slider
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: canSeek ? t.accent : t.inkFaint,
                  inactiveTrackColor: Colors.transparent,
                  overlayColor: t.accent.withValues(alpha: 0.16),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  trackShape: const SwissSeekBarTrackShape(),
                  thumbShape: SwissSliderThumbShape(
                    thumbRadius: 7.0,
                    pipRadius: 2.2,
                    thumbColor: canSeek ? t.ink : t.inkFaint,
                    pipColor: t.bg,
                  ),
                ),
                child: Slider(
                  value: currentMs,
                  min: 0.0,
                  max: canSeek ? totalMs : 1.0,
                  onChangeStart: canSeek
                      ? (val) {
                          setState(() => _dragMilliseconds = val);
                          Haptics.tap();
                        }
                      : null,
                  onChanged: canSeek
                      ? (val) {
                          setState(() => _dragMilliseconds = val);
                        }
                      : null,
                  onChangeEnd: canSeek
                      ? (val) {
                          setState(() => _dragMilliseconds = null);
                          widget.onSeek(Duration(milliseconds: val.round()));
                          Haptics.commit();
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SwissGrid.xs),
        Row(
          children: [
            Text(
              Fmt.duration(_displayed),
              style: SwissType.mono.copyWith(
                color: dragging ? t.accent : t.inkMuted,
                fontSize: 11.5,
              ),
            ),
            const Spacer(),
            Text(
              Fmt.duration(widget.duration),
              style: SwissType.mono.copyWith(color: t.inkFaint, fontSize: 11.5),
            ),
          ],
        ),
      ],
    );
  }
}


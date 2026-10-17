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

/// The Now Playing seekbar: buffered band, playhead, and a drag preview so the
/// user can read the exact target time before releasing.
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
  double? _preview;

  double get _fraction {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    final value = _preview ?? (widget.position.inMilliseconds / total);
    return value.clamp(0.0, 1.0);
  }

  Duration get _displayed {
    if (_preview == null) return widget.position;
    return Duration(milliseconds: (widget.duration.inMilliseconds * _preview!).round());
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final dragging = _preview != null;

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            void emit(double dx) {
              if (width <= 0) return;
              setState(() => _preview = (dx / width).clamp(0.0, 1.0));
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => emit(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => emit(d.localPosition.dx),
              onHorizontalDragEnd: (_) {
                final fraction = _preview;
                setState(() => _preview = null);
                if (fraction == null) return;
                widget.onSeek(
                  Duration(milliseconds: (widget.duration.inMilliseconds * fraction).round()),
                );
              },
              onHorizontalDragCancel: () => setState(() => _preview = null),
              onTapDown: (d) {
                if (width <= 0) return;
                final fraction = (d.localPosition.dx / width).clamp(0.0, 1.0);
                widget.onSeek(
                  Duration(milliseconds: (widget.duration.inMilliseconds * fraction).round()),
                );
              },
              child: SizedBox(
                height: 28,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.hairlineStrong.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
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
                    // The bead: ink shell around a canvas pip.
                    Align(
                      alignment: Alignment(_fraction * 2 - 1, 0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 80),
                        width: dragging ? 18 : 14,
                        height: dragging ? 18 : 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.enabled ? t.ink : t.inkFaint,
                          boxShadow: dragging ? t.raisedShadow : null,
                        ),
                        child: Center(
                          child: Container(
                            width: 5,
                            height: 5,
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
            );
          },
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

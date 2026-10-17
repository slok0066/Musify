import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../services/player/playback_service.dart';
import '../../services/service_locator.dart';
import '../../services/settings_service.dart';

/// The Now Playing spectrum.
///
/// SoLoud feeds raw FFT frames; this widget folds them into a fixed number of
/// log-spaced bars with asymmetric smoothing (fast attack, slow decay), which is
/// what makes a spectrum look like a hardware analyser instead of a jitter
/// graph. It only asks the engine for FFT data while it is actually on screen.
class FftVisualizer extends StatefulWidget {
  const FftVisualizer({
    this.mode = VisualizerMode.fft,
    this.barCount = 44,
    this.height = 76,
    super.key,
  });

  final VisualizerMode mode;
  final int barCount;
  final double height;

  @override
  State<FftVisualizer> createState() => _FftVisualizerState();
}

class _FftVisualizerState extends State<FftVisualizer> {
  final ValueNotifier<List<double>> _levels = ValueNotifier<List<double>>(const []);
  StreamSubscription<Float32List>? _sub;
  late PlaybackService _player;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant FftVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _bind();
  }

  void _bind() {
    _player = locator<PlaybackService>();
    _sub?.cancel();
    _sub = null;
    _levels.value = List<double>.filled(widget.barCount, 0);

    if (widget.mode == VisualizerMode.off) return;

    _sub = _player.fftStream.listen(
      _onFrame,
      onError: (Object _) {},
    );
    unawaited(_player.setVisualizerActive(true));
  }

  @override
  void dispose() {
    _sub?.cancel();
    // Only release the FFT feed if nothing else is drawing it.
    if (widget.mode != VisualizerMode.off) {
      unawaited(_player.setVisualizerActive(false));
    }
    _levels.dispose();
    super.dispose();
  }

  /// Folds an FFT frame into [barCount] bands, then applies attack/decay.
  void _onFrame(Float32List frame) {
    if (frame.isEmpty || !mounted) return;

    final bars = widget.barCount;
    final next = List<double>.filled(bars, 0);
    // Skip the lowest DC bin and use a log-space split so the bass does not eat
    // the whole display.
    final usable = frame.length;
    final denominator = math.log(usable + 1);

    for (var bar = 0; bar < bars; bar++) {
      final start = ((math.exp(denominator * bar / bars).round()) - 1).clamp(1, usable - 1);
      final end = ((math.exp(denominator * (bar + 1) / bars).round()) - 1)
          .clamp(start + 1, usable);
      var peak = 0.0;
      for (var i = start; i < end; i++) {
        final value = _normalise(frame[i]);
        if (value > peak) peak = value;
      }
      next[bar] = peak;
    }

    final current = _levels.value;
    final smoothed = List<double>.filled(bars, 0);
    for (var i = 0; i < bars; i++) {
      final previous = i < current.length ? current[i] : 0.0;
      // 0.62 attack / 0.16 decay per frame ≈ a real analyser's ballistics.
      smoothed[i] = next[i] > previous
          ? previous + (next[i] - previous) * 0.62
          : previous + (next[i] - previous) * 0.16;
    }
    _levels.value = smoothed;
  }

  /// Tolerates dB frames (`-90…0`), normalised frames (`0…1`) and raw bytes.
  static double _normalise(double raw) {
    if (raw.isNaN) return 0;
    if (raw <= 0) return ((raw + 90) / 90).clamp(0.0, 1.0);
    if (raw <= 1.5) return raw.clamp(0.0, 1.0);
    if (raw <= 255) return (raw / 255).clamp(0.0, 1.0);
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    if (widget.mode == VisualizerMode.off) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'ANALYSER OFF // ENABLE IN SETTINGS',
            style: SwissType.micro.copyWith(color: t.inkFaint),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: widget.mode == VisualizerMode.wave
              ? _WavePainter(levels: _levels, color: t.accent, hairline: t.hairline)
              : _BarsPainter(levels: _levels, color: t.accent, hairline: t.hairline),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.levels, required this.color, required this.hairline})
      : super(repaint: levels);

  final ValueListenable<List<double>> levels;
  final Color color;
  final Color hairline;

  @override
  void paint(Canvas canvas, Size size) {
    final data = levels.value;
    if (data.isEmpty) return;

    final gap = size.width / data.length;
    final barWidth = math.max(1.5, gap * 0.55);
    final paint = Paint()..color = color;
    final faded = Paint()..color = color.withValues(alpha: 0.28);
    final line = Paint()
      ..color = hairline
      ..strokeWidth = 1;

    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), line);

    for (var i = 0; i < data.length; i++) {
      final level = data[i].clamp(0.0, 1.0);
      final barHeight = math.max(1.0, level * (size.height - 4));
      final left = i * gap + (gap - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - barHeight, barWidth, barHeight),
          const Radius.circular(2),
        ),
        level > 0.55 ? paint : faded,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) => false;
}

/// The minimal waveform mode: a single mirrored polyline.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.levels, required this.color, required this.hairline})
      : super(repaint: levels);

  final ValueListenable<List<double>> levels;
  final Color color;
  final Color hairline;

  @override
  void paint(Canvas canvas, Size size) {
    final data = levels.value;
    if (data.isEmpty) return;

    final center = size.height / 2;
    final path = Path()..moveTo(0, center);
    final step = size.width / (data.length - 1).clamp(1, 1000);

    for (var i = 0; i < data.length; i++) {
      final amplitude = data[i].clamp(0.0, 1.0) * (size.height / 2 - 3);
      path.lineTo(i * step, center - amplitude);
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawLine(
      Offset(0, center),
      Offset(size.width, center),
      Paint()
        ..color = hairline
        ..strokeWidth = 1,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => false;
}

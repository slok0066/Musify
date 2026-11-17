import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';
import '../../services/player/playback_service.dart';
import '../../services/service_locator.dart';
import '../cubits/player_cubit.dart';
import '../navigation.dart';
import '../widgets/swiss_artwork.dart';
import '../widgets/tactile_eight_d_switch.dart';
import '../widgets/track_options_sheet.dart';

/// The docked transport — Chronos Circular Ring design.
///
/// The body opens Now Playing, long-press opens track options. The circular
/// progress ring directly wraps the Play/Pause button and repaints smoothly
/// without rebuilding the card.
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (previous, next) =>
          previous.track?.id != next.track?.id ||
          previous.isPlaying != next.isPlaying ||
          previous.isBuffering != next.isBuffering ||
          previous.is8D != next.is8D ||
          previous.shuffle != next.shuffle ||
          previous.errorText != next.errorText ||
          previous.headphones != next.headphones,
      builder: (context, state) {
        if (!state.hasTrack) return const SizedBox.shrink();
        return _Bar(state: state);
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.state});

  final PlayerState state;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final track = state.track!;
    final player = context.read<PlayerCubit>();
    final engine = locator<PlaybackService>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SwissGrid.gutter,
        SwissGrid.xs,
        SwissGrid.gutter,
        6,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.hairline, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Haptics.tap();
                openNowPlaying(context);
              },
              onLongPress: () {
                Haptics.press();
                showTrackOptions(context, track, source: state.sourceLabel);
              },
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    SwissArtwork(
                      imageUrl: track.imageUrl,
                      size: 44,
                      radius: 12,
                      showBorder: false,
                      placeholderIcon: Icons.music_note,
                      heroTag: 'musify-artwork',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            style: SwissType.title.copyWith(
                              color: t.ink,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            state.isBuffering
                                ? _bufferingLabel(state)
                                : track.artist,
                            style: SwissType.bodyXs.copyWith(
                              color: state.isBuffering ? t.ink : t.inkMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: SwissGrid.xs),
                    if (state.errorText != null) ...[
                      Icon(Icons.error_outline, size: 15, color: t.danger),
                      const SizedBox(width: SwissGrid.xs),
                    ],
                    MiniEightDKeycap(
                      enabled: state.is8D,
                      onToggle: player.toggle8D,
                    ),
                    const SizedBox(width: 8),
                    _CircularRingPlayButton(
                      isPlaying: state.isPlaying,
                      onToggle: player.togglePlayPause,
                      engine: engine,
                    ),
                    const SizedBox(width: 4),
                    TactileIconKeycap(
                      icon: Icons.skip_next,
                      size: 34,
                      iconSize: 20,
                      ghost: true,
                      tooltip: 'Next',
                      onPressed: player.next,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _bufferingLabel(PlayerState state) {
    final fraction = state.bufferFraction;
    if (fraction == null) return 'BUFFERING';
    return 'BUFFERING ${(fraction * 100).round()}%';
  }
}

class _CircularRingPlayButton extends StatelessWidget {
  const _CircularRingPlayButton({
    required this.isPlaying,
    required this.onToggle,
    required this.engine,
  });

  final bool isPlaying;
  final VoidCallback onToggle;
  final PlaybackService engine;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return RepaintBoundary(
      child: ValueListenableBuilder<Duration>(
        valueListenable: engine.position,
        builder: (context, position, _) {
          final total = engine.duration.value.inMilliseconds;
          final played = total <= 0
              ? 0.0
              : (position.inMilliseconds / total).clamp(0.0, 1.0);

          return GestureDetector(
            onTap: () {
              Haptics.tap();
              onToggle();
            },
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(42, 42),
                    painter: _RingProgressPainter(
                      progress: played,
                      trackColor: t.hairlineStrong.withValues(alpha: 0.35),
                      progressColor: t.ink,
                      strokeWidth: 2.2,
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.surface,
                      border: Border.all(color: t.hairline, width: 1),
                    ),
                    child: Center(
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 17,
                        color: t.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingProgressPainter extends CustomPainter {
  const _RingProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    this.strokeWidth = 2.2,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2;
      final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

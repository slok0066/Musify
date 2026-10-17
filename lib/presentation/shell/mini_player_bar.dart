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

/// The docked transport — a floating card that never leaves the screen once
/// something is playing.
///
/// The body opens Now Playing, the long-press opens the same `⋮` sheet every
/// other row uses, and the progress hairline is the only thing in the card
/// that repaints while the music runs (it listens to the engine directly, so a
/// 250 ms position tick cannot cost a rebuild of the whole shell).
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
          SwissGrid.gutter, SwissGrid.xs, SwissGrid.gutter, SwissGrid.xs + 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.hairline, width: 1),
          boxShadow: [
            BoxShadow(
              color: t.dropShadow.withValues(alpha: t.isDark ? 0.35 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(SwissGrid.sm),
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
                        const SizedBox(width: SwissGrid.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextMarquee(
                                text: track.title,
                                style: SwissType.mono.copyWith(
                                  color: t.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                state.isBuffering
                                    ? _bufferingLabel(state)
                                    : track.artist,
                                style: SwissType.bodyXs.copyWith(
                                  color: state.isBuffering
                                      ? t.accent
                                      : t.inkMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: SwissGrid.sm),
                        if (state.errorText != null) ...[
                          Icon(Icons.error_outline, size: 15, color: t.danger),
                          const SizedBox(width: SwissGrid.sm),
                        ],

                        MiniEightDKeycap(
                          enabled: state.is8D,
                          onToggle: player.toggle8D,
                        ),
                        const SizedBox(width: SwissGrid.xs),
                        TactileIconKeycap(
                          icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 40,
                          iconSize: 22,
                          ghost: true,
                          tint: t.accent,
                          tooltip: state.isPlaying ? 'Pause' : 'Play',
                          onPressed: player.togglePlayPause,
                        ),
                        const SizedBox(width: SwissGrid.xs),
                        TactileIconKeycap(
                          icon: Icons.skip_next,
                          size: 36,
                          iconSize: 20,
                          ghost: true,
                          tooltip: 'Next',
                          onPressed: player.next,
                        ),
                      ],
                    ),
                  ),
                  // The progress hairline, tucked inside the card's bottom
                  // edge: buffered band first, playhead on top.
                  ValueListenableBuilder<Duration>(
                    valueListenable: engine.position,
                    builder: (context, position, _) {
                      final total = engine.duration.value.inMilliseconds;
                      final played = total <= 0
                          ? 0.0
                          : (position.inMilliseconds / total).clamp(0.0, 1.0);
                      final buffered = total <= 0
                          ? 0.0
                          : (engine.buffered.value.inMilliseconds / total)
                              .clamp(0.0, 1.0);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                            SwissGrid.sm, 0, SwissGrid.sm, SwissGrid.sm),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 3,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ColoredBox(
                                    color:
                                        t.hairlineStrong.withValues(alpha: 0.4),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: buffered,
                                  alignment: Alignment.centerLeft,
                                  child: ColoredBox(color: t.hairlineStrong),
                                ),
                                FractionallySizedBox(
                                  widthFactor: played,
                                  alignment: Alignment.centerLeft,
                                  child: ColoredBox(color: t.accent),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
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

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/track.dart';
import '../../../services/settings_service.dart';
import '../../cubits/player_cubit.dart';
import '../../widgets/swiss_artwork.dart';
import '../../widgets/track_options_sheet.dart';

/// The queue, in the order the engine will actually play it.
///
/// Shuffle is a playback order, not a reshuffle of the queue, so the list stays
/// stable and every row can be dragged: reordering while the engine shuffles
/// simply reshuffles the remaining order.
Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _QueueSheet(),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (previous, next) =>
          previous.queue != next.queue ||
          previous.queueIndex != next.queueIndex ||
          previous.shuffle != next.shuffle ||
          previous.repeat != next.repeat,
      builder: (context, state) {
        final player = context.read<PlayerCubit>();
        final queue = state.queue;
        final upcoming = state.queueIndex + 1;

        return MusifySheetShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MusifySheetHeader(
                title: 'PLAYING QUEUE',
                subtitle: '${state.queueIndex + 1} OF ${queue.length} // '
                    '${state.shuffle ? 'SHUFFLED' : 'IN ORDER'} // ${state.repeat.name.toUpperCase()}',
                trailing: TactileIconKeycap(
                  icon: Icons.close,
                  size: 30,
                  iconSize: 15,
                  hapticOnPress: false,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              if (queue.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(SwissGrid.xl),
                  child: Text(
                    'THE QUEUE IS EMPTY',
                    style: SwissType.label.copyWith(color: t.inkFaint),
                  ),
                )
              else
                Flexible(
                  child: ReorderableListView.builder(
                    padding: EdgeInsets.zero,
                    buildDefaultDragHandles: false,
                    itemCount: queue.length,
                    onReorderItem: (oldIndex, newIndex) {
                      // `onReorderItem` already reports the item's final index,
                      // so the engine can insert it directly.
                      player.reorderQueue(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      final current = index == state.queueIndex;
                      return _QueueRow(
                        key: ValueKey('queue-${track.id}-$index'),
                        track: track,
                        index: index,
                        current: current,
                        upcoming: index >= upcoming,
                        onTap: () {
                          Haptics.tap();
                          player.jumpTo(index);
                        },
                        onRemove: () => player.removeFromQueue(index),
                        onOptions: () => showTrackOptions(
                          context,
                          track,
                          source: state.sourceLabel,
                          queueContext: queue,
                        ),
                      );
                    },
                  ),
                ),
              if (queue.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      SwissGrid.lg, SwissGrid.sm, SwissGrid.lg, SwissGrid.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: TactileKeycap(
                          height: 40,
                          width: double.infinity,
                          onPressed: () {
                            Haptics.reject();
                            player.clearQueue();
                          },
                          child: const Text('CLEAR QUEUE'),
                        ),
                      ),
                      const SizedBox(width: SwissGrid.sm),
                      TactileIconKeycap(
                        icon: Icons.shuffle,
                        size: 40,
                        iconSize: 18,
                        active: state.shuffle,
                        glow: false,
                        tooltip: 'Shuffle the queue',
                        onPressed: player.toggleShuffle,
                      ),
                      const SizedBox(width: SwissGrid.sm),
                      TactileIconKeycap(
                        icon: switch (state.repeat) {
                          RepeatMode.one => Icons.repeat_one,
                          _ => Icons.repeat,
                        },
                        size: 40,
                        iconSize: 18,
                        active: state.repeat != RepeatMode.off,
                        glow: false,
                        tooltip: 'Repeat mode',
                        onPressed: player.cycleRepeat,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.track,
    required this.index,
    required this.current,
    required this.upcoming,
    required this.onTap,
    required this.onRemove,
    required this.onOptions,
    super.key,
  });

  final Track track;
  final int index;
  final bool current;
  final bool upcoming;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return Material(
      color: current ? t.accentSoft.withValues(alpha: 0.2) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: SwissGrid.md, vertical: SwissGrid.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: SwissType.mono
                      .copyWith(fontSize: 11, color: current ? t.accent : t.inkFaint),
                ),
              ),
              const SizedBox(width: SwissGrid.sm),
              SwissArtwork(
                imageUrl: track.imageUrl,
                size: 46,
                radius: 10,
                placeholderIcon: Icons.music_note,
              ),
              const SizedBox(width: SwissGrid.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      style: SwissType.body.copyWith(
                        color: current
                            ? t.accent
                            : (upcoming ? t.ink : t.inkMuted),
                        fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      current ? 'NOW PLAYING' : track.artist,
                      style: SwissType.bodyXs.copyWith(
                        color: current ? t.accent : t.inkFaint,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                Fmt.durationShort(track.duration),
                style: SwissType.micro.copyWith(color: t.inkFaint),
              ),
              const SizedBox(width: SwissGrid.sm),
              TactileIconKeycap(
                icon: Icons.more_vert,
                size: 28,
                iconSize: 14,
                hapticOnPress: false,
                tooltip: 'Track options',
                onPressed: onOptions,
              ),
              const SizedBox(width: SwissGrid.xs),
              TactileIconKeycap(
                icon: Icons.close,
                size: 28,
                iconSize: 14,
                hapticOnPress: false,
                tooltip: 'Remove from queue',
                onPressed: onRemove,
              ),
              const SizedBox(width: SwissGrid.xs),
              ReorderableDragStartListener(
                index: index,
                child: Icon(Icons.drag_indicator, size: 17, color: t.inkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

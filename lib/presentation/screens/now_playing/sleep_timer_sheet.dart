import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../core/utils/formatters.dart';
import '../../cubits/player_cubit.dart';
import '../../widgets/track_options_sheet.dart';

/// The sleep timer.
///
/// Fades the output over five seconds and then pauses — never stops the app, so
/// waking up mid-album is one tap on the same keycap that armed the timer.
Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends StatelessWidget {
  const _SleepTimerSheet();

  static const List<int> _presets = [5, 10, 15, 30, 45, 60];

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (previous, next) =>
          previous.sleepRemaining != next.sleepRemaining ||
          previous.track?.id != next.track?.id ||
          previous.duration != next.duration ||
          previous.isPlaying != next.isPlaying,
      builder: (context, state) {
        final player = context.read<PlayerCubit>();
        final remaining = state.sleepRemaining;
        final trackRemaining = state.duration - state.position;

        return MusifySheetShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MusifySheetHeader(
                title: 'SLEEP TIMER',
                subtitle: remaining == null
                    ? 'NOT ARMED'
                    : 'FADES OUT IN ${Fmt.countdown(remaining)}',
                trailing: TactileIconKeycap(
                  icon: Icons.close,
                  size: 30,
                  iconSize: 15,
                  hapticOnPress: false,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(SwissGrid.lg),
                  children: [
                    RecessedWell(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            remaining == null ? 'STANDBY' : 'COUNTDOWN LIVE',
                            style: SwissType.label.copyWith(
                              color: remaining == null ? t.inkFaint : t.accent,
                            ),
                          ),
                          const SizedBox(height: SwissGrid.sm),
                          Row(
                            children: [
                              LedDot(active: remaining != null, size: 8),
                              const SizedBox(width: SwissGrid.sm),
                              Text(
                                remaining == null ? '--:--' : Fmt.countdown(remaining),
                                style: SwissType.display.copyWith(
                                  color: remaining == null ? t.inkFaint : t.accent,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '5 S FADE OUT',
                                style: SwissType.micro.copyWith(color: t.inkFaint),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SwissGrid.md),
                    Text('ARM FOR', style: SwissType.label.copyWith(color: t.inkFaint)),
                    const SizedBox(height: SwissGrid.sm),
                    Wrap(
                      spacing: SwissGrid.sm,
                      runSpacing: SwissGrid.sm,
                      children: [
                        for (final minutes in _presets)
                          SwissPill(
                            label: '$minutes MIN',
                            selected: remaining != null &&
                                remaining.inMinutes >= minutes - 1 &&
                                remaining.inMinutes <= minutes,
                            onTap: () {
                              Haptics.commit();
                              player.setSleepTimer(Duration(minutes: minutes));
                              Navigator.of(context).maybePop();
                            },
                          ),
                        SwissPill(
                          label: 'END OF TRACK',
                          onTap: () {
                            Haptics.commit();
                            player.setSleepTimer(
                              trackRemaining > Duration.zero
                                  ? trackRemaining
                                  : const Duration(minutes: 3),
                            );
                            Navigator.of(context).maybePop();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: SwissGrid.lg),
                    TactileKeycap(
                      height: 44,
                      width: double.infinity,
                      enabled: remaining != null,
                      onPressed: () {
                        player.cancelSleepTimer();
                        Navigator.of(context).maybePop();
                      },
                      child: Text(remaining == null ? 'NO TIMER ARMED' : 'CANCEL THE TIMER'),
                    ),
                    const SizedBox(height: SwissGrid.md),
                    Text(
                      'THE TIMER RUNS INSIDE THE PLAYBACK ENGINE, SO IT KEEPS COUNTING '
                      'WHILE THE SCREEN IS OFF OR THE APP IS BACKGROUNDED.',
                      style: SwissType.micro.copyWith(color: t.inkFaint, fontSize: 9),
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

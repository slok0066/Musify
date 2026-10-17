import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';
import '../cubits/settings_cubit.dart';
import 'tactile_slider.dart';
import 'track_options_sheet.dart';

/// The 8D calibration console.
///
/// The same three parameters the Settings screen exposes, reachable from the Now
/// Playing module so tuning never means stopping the music. Every change is
/// written straight into the running engine — the user hears the orbit change
/// while the sheet is still open.
Future<void> showEightDCalibration(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CalibrationSheet(),
  );
}

class _CalibrationSheet extends StatelessWidget {
  const _CalibrationSheet();

  @override
  Widget build(BuildContext context) {
    return MusifySheetShell(
      maxHeightFactor: 0.9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MusifySheetHeader(
            title: '8D CALIBRATION',
            subtitle: 'SPATIAL DSP // LIVE',
            trailing: TactileIconKeycap(
              icon: Icons.close,
              size: 30,
              iconSize: 15,
              hapticOnPress: false,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(SwissGrid.lg),
              child: EightDControls(showMath: true),
            ),
          ),
        ],
      ),
    );
  }
}

/// The orbit controls themselves — used by the calibration sheet and by the
/// Settings screen, so the two can never drift apart.
class EightDControls extends StatelessWidget {
  const EightDControls({this.showMath = false, super.key});

  /// Prints the DSP formula chain under the controls.
  final bool showMath;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return BlocBuilder<SettingsCubit, SettingsState>(
      buildWhen: (previous, next) =>
          previous.settings.orbitSeconds != next.settings.orbitSeconds ||
          previous.settings.reverbMix != next.settings.reverbMix ||
          previous.settings.rearLowPassEnabled != next.settings.rearLowPassEnabled ||
          previous.settings.auto8DOnHeadphones != next.settings.auto8DOnHeadphones,
      builder: (context, state) {
        final settings = state.settings;
        final cubit = context.read<SettingsCubit>();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SwissPanel(
              raised: true,
              padding: const EdgeInsets.all(SwissGrid.md),
              child: Column(
                children: [
                  SliderReadout(
                    label: 'ORBIT SPEED',
                    hint: 'SECONDS PER FULL REVOLUTION',
                    readout: '${settings.orbitSeconds.toStringAsFixed(1)}S',
                  ),
                  TactileSlider(
                    value: settings.orbitSeconds,
                    min: 5,
                    max: 20,
                    steps: 31,
                    onChangeStart: () => Haptics.tap(),
                    onChanged: cubit.setOrbitSeconds,
                  ),
                  const SizedBox(height: SwissGrid.lg),
                  SliderReadout(
                    label: 'ROOM SIZE',
                    hint: 'FREEVERB WET MIX INTO THE ORBIT',
                    readout: '${(settings.reverbMix * 100).round()}%',
                  ),
                  TactileSlider(
                    value: settings.reverbMix,
                    min: 0,
                    max: 0.5,
                    steps: 21,
                    onChangeStart: () => Haptics.tap(),
                    onChanged: cubit.setReverbMix,
                  ),
                ],
              ),
            ),
            const SizedBox(height: SwissGrid.md),
            SettingsToggleRow(
              label: 'REAR LOW-PASS',
              hint: 'DARKENS THE BACK OF THE ORBIT (3.2 – 16 KHZ)',
              value: settings.rearLowPassEnabled,
              onChanged: cubit.setRearLowPass,
            ),
            SettingsToggleRow(
              label: 'AUTO 8D ON HEADPHONES',
              hint: 'ENGAGE THE ORBIT WHEN A PAIR IS CONNECTED',
              value: settings.auto8DOnHeadphones,
              onChanged: cubit.setAuto8DOnHeadphones,
            ),
            const SizedBox(height: SwissGrid.md),
            TactileKeycap(
              height: 44,
              width: double.infinity,
              onPressed: cubit.reset8DDefaults,
              child: const Text('RESET TO FACTORY CALIBRATION'),
            ),
            if (showMath) ...[
              const SizedBox(height: SwissGrid.lg),
              Text('HOW THE ORBIT IS BUILT', style: SwissType.label.copyWith(color: t.inkFaint)),
              const SizedBox(height: SwissGrid.sm),
              Text(
                'x = 2·sin θ   z = 2·cos θ   pan = 0.85·sin θ\n'
                'rear cut-off tracks (cos θ + 1) / 2 between 3.2 kHz and 16 kHz\n'
                'freeverb room 0.72, damping 0.50, wet 0 → 24% over 350 ms',
                style: SwissType.mono.copyWith(color: t.inkMuted, fontSize: 10.5),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A label + hint + physical switch row. Every settings group is built from it.
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
                  style: SwissType.label.copyWith(color: enabled ? t.ink : t.inkFaint),
                ),
                const SizedBox(height: 2),
                Text(hint, style: SwissType.micro.copyWith(color: t.inkFaint, fontSize: 9)),
              ],
            ),
          ),
          const SizedBox(width: SwissGrid.sm),
          TactileSwitch(
            value: value,
            onChanged: enabled ? onChanged : (_) {},
            semanticLabel: label,
          ),
        ],
      ),
    );
  }
}

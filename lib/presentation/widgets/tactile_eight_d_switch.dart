import 'package:flutter/material.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';

/// The signature `03 // SPATIAL DSP` module.
///
/// A recessed well holds the latching 8D keycap, its Signal Orange LED and the
/// live telemetry line. Everything the user needs to trust that the DSP is
/// really running is visible here — orbit period, reverb mix and whether the
/// rear low-pass is engaged — and the calibration button sits inside the same
/// panel so tuning never means leaving the player.
class TactileEightDSwitch extends StatelessWidget {
  const TactileEightDSwitch({
    required this.enabled,
    required this.onToggle,
    required this.orbitSeconds,
    required this.reverbMix,
    required this.rearLowPass,
    this.onCalibrate,
    this.compact = false,
    super.key,
  });

  final bool enabled;
  final VoidCallback onToggle;
  final double orbitSeconds;
  final double reverbMix;
  final bool rearLowPass;
  final VoidCallback? onCalibrate;
  final bool compact;

  String get _telemetry =>
      'ORBIT: ${orbitSeconds.toStringAsFixed(1)}S  //  REVERB: ${(reverbMix * 100).round()}%  //  REAR LPF: ${rearLowPass ? 'ACTIVE' : 'OFF'}';

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return SwissPanel(
      raised: true,
      padding: EdgeInsets.all(compact ? SwissGrid.sm : SwissGrid.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (!compact)
                Text(
                  '03 // SPATIAL DSP',
                  style: SwissType.label.copyWith(color: t.inkFaint),
                ),
              const Spacer(),
              LedDot(active: enabled, size: 6),
              const SizedBox(width: 5),
              Text(
                enabled ? 'LIVE' : 'STANDBY',
                style: SwissType.micro.copyWith(
                  color: enabled ? t.accent : t.inkFaint,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? SwissGrid.xs : SwissGrid.sm),
          Row(
            children: [
              Expanded(
                child: TactileKeycap(
                  accent: enabled,
                  glow: enabled,
                  width: double.infinity,
                  height: compact ? 38 : 46,
                  onPressed: () {
                    Haptics.commit();
                    onToggle();
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.surround_sound,
                        size: compact ? 16 : 18,
                        color: enabled ? t.accentInk : t.ink,
                      ),
                      const SizedBox(width: SwissGrid.sm),
                      Text(
                        '8D AUDIO',
                        style: SwissType.label.copyWith(
                          color: enabled ? t.accentInk : t.ink,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (onCalibrate != null) ...[
                const SizedBox(width: SwissGrid.sm),
                TactileKeycap(
                  height: compact ? 38 : 46,
                  onPressed: () {
                    Haptics.tap();
                    onCalibrate!();
                  },
                  child: Row(
                    children: [
                      Icon(Icons.tune, size: 15, color: t.ink),
                      const SizedBox(width: 5),
                      Text(
                        'CALIBRATE',
                        style: SwissType.micro.copyWith(
                          color: t.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: SwissGrid.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _telemetry,
                style: SwissType.mono.copyWith(
                  color: enabled ? t.accent : t.inkFaint,
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The mini-player's 8D control: a sleek tactile pill keycap.
class MiniEightDKeycap extends StatelessWidget {
  const MiniEightDKeycap({required this.enabled, required this.onToggle, super.key});

  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Tooltip(
      message: enabled ? '8D Spatial Audio ON' : '8D Spatial Audio OFF',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Haptics.commit();
            onToggle();
          },
          borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: enabled
                  ? t.accent
                  : t.surfaceSunken,
              borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
              border: Border.all(
                color: enabled ? t.accent : t.hairline,
                width: 1,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: t.accent.withValues(alpha: 0.3),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.surround_sound,
                  size: 14,
                  color: enabled ? t.accentInk : t.inkMuted,
                ),
                const SizedBox(width: 3),
                Text(
                  '8D',
                  style: SwissType.micro.copyWith(
                    color: enabled ? t.accentInk : t.inkMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

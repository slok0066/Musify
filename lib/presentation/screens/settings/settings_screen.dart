import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/build_info.dart';
import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../core/utils/formatters.dart';
import '../../../services/service_locator.dart';
import '../../../services/settings_service.dart';
import '../../../services/update_service.dart';
import '../../cubits/navigation_cubit.dart';
import '../../cubits/player_cubit.dart';
import '../../cubits/settings_cubit.dart';
import '../../widgets/eight_d_calibration_sheet.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/tactile_eight_d_switch.dart';
import '../../widgets/tactile_slider.dart';
import '../../widgets/track_options_sheet.dart';

/// `04 // SETTINGS` — the audio engineering lab, the storage bay and the
/// backup drawer.
///
/// There is no "apply" anywhere: every control writes through
/// [SettingsCubit] into the persisted settings object and the running engine at
/// the same time, so what is on screen and what is audible are the same truth.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (previous, next) => next.message != null && next.message != previous.message,
      listener: (context, state) {
        final message = state.message;
        if (message == null) return;
        final t = SwissTokens.of(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: t.surfaceRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: t.hairline, width: 1),
              ),
              content: Text(
                message,
                style: SwissType.label.copyWith(
                  color: t.ink,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              duration: const Duration(milliseconds: 1800),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(
                SwissGrid.gutter,
                0,
                SwissGrid.gutter,
                SwissGrid.md,
              ),
            ),
          );
        context.read<SettingsCubit>().consumeMessage();
      },
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();
        final settings = state.settings;

        return Column(
          children: [
            ScreenHeader(
              tab: AppTab.settings,
              subtitle: state.qualityLine,
              trailing: TactileIconKeycap(
                icon: Icons.refresh,
                size: 40,
                tooltip: 'Re-measure storage',
                onPressed: state.busy ? null : cubit.refreshStorage,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: SwissGrid.xxl),
                children: [
                  // ------------------------------------------------- quality
                  const _SectionLabel(index: '01', title: 'STREAMING QUALITY'),
                  _QualityGroup(
                    label: 'WI-FI / UNMETERED',
                    hint: '',
                    selected: settings.wifiQuality,
                    onSelected: cubit.setWifiQuality,
                  ),
                  _QualityGroup(
                    label: 'MOBILE DATA',
                    hint: '',
                    selected: settings.mobileQuality,
                    onSelected: cubit.setMobileQuality,
                  ),
                  _QualityGroup(
                    label: 'OFFLINE DOWNLOADS',
                    hint: '',
                    selected: settings.downloadQuality,
                    onSelected: cubit.setDownloadQuality,
                  ),

                  // ---------------------------------------------------- spatial
                  const _SectionLabel(index: '02', title: 'SPATIAL 8D ENGINE'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
                    child: BlocBuilder<PlayerCubit, PlayerState>(
                      buildWhen: (previous, next) => previous.is8D != next.is8D,
                      builder: (context, playerState) => TactileEightDSwitch(
                        enabled: playerState.is8D,
                        onToggle: () => context.read<PlayerCubit>().toggle8D(),
                        orbitSeconds: settings.orbitSeconds,
                        reverbMix: settings.reverbMix,
                        rearLowPass: settings.rearLowPassEnabled,
                        onCalibrate: () => showEightDCalibration(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: SwissGrid.md),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
                    child: EightDControls(),
                  ),

                  // ------------------------------------------------------- EQ
                  const _SectionLabel(index: '03', title: 'EQUALISER'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
                    child: Column(
                      children: [
                        SettingsToggleRow(
                          label: 'PARAMETRIC EQ',
                          hint: '10 BANDS AT ISO CENTRES, Q = 1.0',
                          value: settings.eqEnabled,
                          onChanged: cubit.setEqEnabled,
                        ),
                        const SizedBox(height: SwissGrid.md),
                        PillStrip(
                          padding: EdgeInsets.zero,
                          children: [
                            for (final preset in EqPreset.all)
                              SwissPill(
                                label: preset.name,
                                selected: settings.eqEnabled &&
                                    settings.eqPresetName.toLowerCase() ==
                                        preset.name.toLowerCase(),
                                dense: true,
                                onTap: () {
                                  cubit.setEqEnabled(true);
                                  cubit.applyEqPreset(preset.name);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: SwissGrid.md),
                        SwissPanel(
                          raised: true,
                          padding: const EdgeInsets.all(SwissGrid.md),
                          child: Column(
                            children: [
                              for (var band = 0; band < EqPreset.bandFrequencies.length; band++)
                                _BandSlider(
                                  band: band,
                                  value: settings.eqGains.length > band
                                      ? settings.eqGains[band]
                                      : 1,
                                  enabled: settings.eqEnabled,
                                  onChanged: (value) => cubit.setEqGain(band, value),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: SwissGrid.md),
                        SwissPanel(
                          raised: true,
                          padding: const EdgeInsets.all(SwissGrid.md),
                          child: Column(
                            children: [
                              SliderReadout(
                                label: 'BASS BOOST',
                                hint: 'GLOBAL LOW-SHELF ON TOP OF THE EQ',
                                readout: settings.bassBoost.toStringAsFixed(2),
                              ),
                              TactileSlider(
                                value: settings.bassBoost,
                                min: 0,
                                max: 4,
                                steps: 17,
                                onChangeStart: () => Haptics.tap(),
                                onChanged: cubit.setBassBoost,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // -------------------------------------------------- playback
                  const _SectionLabel(index: '04', title: 'PLAYBACK BEHAVIOUR'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
                    child: Column(
                      children: [
                        SwissPanel(
                          raised: true,
                          padding: const EdgeInsets.all(SwissGrid.md),
                          child: Column(
                            children: [
                              SliderReadout(
                                label: 'CROSSFADE',
                                hint: 'OVERLAP INTO THE NEXT TRACK',
                                readout: settings.crossfadeSeconds == 0
                                    ? 'OFF'
                                    : '${settings.crossfadeSeconds}S',
                              ),
                              TactileSlider(
                                value: settings.crossfadeSeconds.toDouble(),
                                min: 0,
                                max: 12,
                                steps: 13,
                                onChangeStart: () => Haptics.tap(),
                                onChanged: (value) =>
                                    cubit.setCrossfadeSeconds(value.round()),
                              ),
                            ],
                          ),
                        ),
                        SettingsToggleRow(
                          label: 'GAPLESS PRELOAD',
                          hint: 'STAGE THE NEXT TRACK BEFORE THIS ONE ENDS',
                          value: settings.gaplessPreload,
                          onChanged: cubit.setGaplessPreload,
                        ),
                        SettingsToggleRow(
                          label: 'PREFETCH AHEAD',
                          hint: 'KEEP THE NEXT TWO MINUTES ON DISK',
                          value: settings.prefetchNext,
                          onChanged: cubit.setPrefetchNext,
                        ),
                        SettingsToggleRow(
                          label: 'INSTANT PLAY',
                          hint: settings.instantStart
                              ? 'STREAM FRAMES — SOUND IN UNDER A SECOND'
                              : 'DOWNLOAD FIRST — SLOW TO START, SAFEST',
                          value: settings.instantStart,
                          onChanged: cubit.setInstantStart,
                        ),
                        const SizedBox(height: SwissGrid.md),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'SPECTRUM DISPLAY',
                                style: SwissType.label.copyWith(color: t.ink),
                              ),
                            ),
                            PillStrip(
                              padding: EdgeInsets.zero,
                              children: [
                                for (final mode in VisualizerMode.values)
                                  SwissPill(
                                    label: switch (mode) {
                                      VisualizerMode.fft => 'FFT',
                                      VisualizerMode.wave => 'WAVE',
                                      VisualizerMode.off => 'OFF',
                                    },
                                    selected: settings.visualizer == mode,
                                    dense: true,
                                    onTap: () => cubit.setVisualizer(mode),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ------------------------------------------------- interface
                  const _SectionLabel(index: '05', title: 'INTERFACE'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
                    child: Column(
                      children: [
                        PillStrip(
                          padding: EdgeInsets.zero,
                          children: [
                            for (final theme in ChassisTheme.values)
                              SwissPill(
                                label: switch (theme) {
                                  ChassisTheme.carbon => 'DARK',
                                  ChassisTheme.alabaster => 'LIGHT',
                                  ChassisTheme.system => 'SYSTEM',
                                },
                                selected: settings.theme == theme,
                                onTap: () => cubit.setTheme(theme),
                              ),
                          ],
                        ),
                        SettingsToggleRow(
                          label: 'HAPTIC FEEDBACK',
                          hint: 'KEYCAP PRESSES, TAPS AND COMMITS',
                          value: settings.hapticsEnabled,
                          onChanged: cubit.setHaptics,
                        ),
                      ],
                    ),
                  ),

                  // --------------------------------------------------- storage
                  const _SectionLabel(index: '06', title: 'STORAGE'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _StorageCell(
                                label: 'STREAM CACHE',
                                value: Fmt.bytes(state.cacheBytes),
                                hint: 'AUTO-CLEARED BUFFER',
                              ),
                            ),
                            const SizedBox(width: SwissGrid.md),
                            Expanded(
                              child: _StorageCell(
                                label: 'OFFLINE VAULT',
                                value: Fmt.bytes(state.downloadsBytes),
                                hint: '${state.downloadsCount} TRACKS PINNED',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: SwissGrid.md),
                        Row(
                          children: [
                            Expanded(
                              child: TactileKeycap(
                                height: 42,
                                width: double.infinity,
                                enabled: !state.busy,
                                onPressed: cubit.clearStreamCache,
                                child: const Text('CLEAR CACHE'),
                              ),
                            ),
                            const SizedBox(width: SwissGrid.sm),
                            Expanded(
                              child: TactileKeycap(
                                height: 42,
                                width: double.infinity,
                                enabled: !state.busy && state.downloadsCount > 0,
                                onPressed: cubit.deleteAllDownloads,
                                child: const Text('DELETE DOWNLOADS'),
                              ),
                            ),
                          ],
                        ),
                        if (state.busy) ...[
                          const SizedBox(height: SwissGrid.sm),
                          Row(
                            children: [
                              LedDot(active: true, size: 6),
                              const SizedBox(width: SwissGrid.sm),
                              Text('WORKING…', style: SwissType.micro.copyWith(color: t.accent)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ---------------------------------------------------- backup
                  const _SectionLabel(index: '07', title: 'BACKUP & RESTORE'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
                    child: Column(
                      children: [
                        Text(
                          'Export or restore your liked songs, playlists, history, and preferences.',
                          style: SwissType.micro.copyWith(color: t.inkFaint, fontSize: 10),
                        ),
                        const SizedBox(height: SwissGrid.md),
                        Row(
                          children: [
                            Expanded(
                              child: TactileKeycap(
                                height: 42,
                                width: double.infinity,
                                enabled: !state.busy,
                                onPressed: () => _export(context),
                                child: const Text('EXPORT .JSON'),
                              ),
                            ),
                            const SizedBox(width: SwissGrid.sm),
                            Expanded(
                              child: TactileKeycap(
                                height: 42,
                                width: double.infinity,
                                enabled: !state.busy,
                                onPressed: () => _import(context),
                                child: const Text('IMPORT JSON'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ----------------------------------------------------- credit
                  const SizedBox(height: SwissGrid.xl),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SwissGrid.gutter, vertical: SwissGrid.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: t.hairline, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Image.asset(
                                'assets/icon/app_icon.png',
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: SwissGrid.md),
                          // Check for Updates
                          TactileKeycap(
                            height: 42,
                            onPressed: () => _checkForUpdates(context),
                            child: Center(
                              child: Text(
                                'CHECK FOR UPDATES',
                                style: SwissType.label.copyWith(color: t.ink),
                              ),
                            ),
                          ),
                          const SizedBox(height: SwissGrid.md),
                          Text(
                            kBuildLabel,
                            style: SwissType.micro.copyWith(color: t.inkFaint),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _checkForUpdates(BuildContext context) async {
    HapticFeedback.lightImpact();
    final t = SwissTokens.of(context);
    final scaffold = ScaffoldMessenger.of(context);

    scaffold.showSnackBar(
      SnackBar(
        content: Text(
          'Checking for updates...',
          style: SwissType.label.copyWith(color: t.ink),
        ),
        backgroundColor: t.surfaceRaised,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final updateService = locator<UpdateService>();
    final info = await updateService.checkForUpdate(force: true);

    if (!context.mounted) return;
    scaffold.hideCurrentSnackBar();

    if (info != null && info.hasUpdate) {
      UpdateService.showUpdateDialog(context, info);
    } else {
      scaffold.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
              const SizedBox(width: 10),
              Text(
                'You are on the latest build (v$kAppVersion) ✨',
                style: SwissType.label.copyWith(color: t.ink),
              ),
            ],
          ),
          backgroundColor: t.surfaceRaised,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: t.hairline, width: 1),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static Future<void> _export(BuildContext context) async {
    final cubit = context.read<SettingsCubit>();
    final path = await cubit.exportBackup();
    if (!context.mounted) return;
    if (path == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          subject: 'Musify backup',
          text: 'Musify backup — likes, playlists, history and settings.',
        ),
      );
    } catch (_) {
      // No share target: the file is already downloaded and written to storage.
    }
  }

  static Future<void> _import(BuildContext context) async {
    final cubit = context.read<SettingsCubit>();

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file != null) {
        String? content;
        if (file.path != null) {
          content = await File(file.path!).readAsString();
        } else {
          final bytes = await file.readAsBytes();
          content = utf8.decode(bytes);
        }
        if (content.trim().isNotEmpty) {
          await cubit.importBackup(content);
          return;
        }
      }
    } catch (e) {
      debugPrint('File picker error: $e');
    }

    if (!context.mounted) return;
    final controller = TextEditingController();

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final t = SwissTokens.of(sheetContext);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: MusifySheetShell(
            maxHeightFactor: 0.9,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MusifySheetHeader(
                  title: 'IMPORT BACKUP',
                  subtitle: 'SELECT OR PASTE A MUSIFY .JSON BACKUP',
                  trailing: TactileIconKeycap(
                    icon: Icons.close,
                    size: 30,
                    iconSize: 15,
                    hapticOnPress: false,
                    onPressed: () => Navigator.of(sheetContext).maybePop(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(SwissGrid.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TactileKeycap(
                              height: 38,
                              onPressed: () async {
                                final file = await FilePicker.pickFile(
                                  type: FileType.custom,
                                  allowedExtensions: ['json'],
                                );
                                if (file != null) {
                                  String? content;
                                  if (file.path != null) {
                                    content = await File(file.path!).readAsString();
                                  } else {
                                    final bytes = await file.readAsBytes();
                                    content = utf8.decode(bytes);
                                  }
                                  if (content.trim().isNotEmpty && sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop(content);
                                  }
                                }
                              },
                              child: const Text('CHOOSE .JSON FILE'),
                            ),
                          ),
                          const SizedBox(width: SwissGrid.sm),
                          Expanded(
                            child: TactileKeycap(
                              height: 38,
                              onPressed: () async {
                                final data = await Clipboard.getData(Clipboard.kTextPlain);
                                final text = data?.text;
                                if (text == null || text.isEmpty) return;
                                controller.text = text;
                              },
                              child: const Text('PASTE CLIPBOARD'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SwissGrid.md),
                      RecessedWell(
                        padding: const EdgeInsets.symmetric(horizontal: SwissGrid.md),
                        child: TextField(
                          controller: controller,
                          maxLines: 6,
                          minLines: 4,
                          autofocus: false,
                          style: SwissType.mono.copyWith(color: t.ink, fontSize: 11),
                          cursorColor: t.accent,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            hintText: '{"schema":1,"liked":[…]}',
                            hintStyle: SwissType.micro.copyWith(color: t.inkFaint),
                          ),
                        ),
                      ),
                      const SizedBox(height: SwissGrid.lg),
                      TactileKeycap(
                        accent: true,
                        glow: true,
                        height: 46,
                        width: double.infinity,
                        onPressed: () => Navigator.of(sheetContext).pop(controller.text),
                        child: const Text('RESTORE THIS BACKUP'),
                      ),
                      const SizedBox(height: SwissGrid.sm),
                      Text(
                        'RESTORING MERGES INTO WHAT IS ALREADY ON THE DEVICE — IT NEVER DELETES YOUR LIBRARY.',
                        style: SwissType.micro.copyWith(color: t.inkFaint, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    await cubit.importBackup(result);
  }
}

/// One quality tier: three keycaps, one selected.
class _QualityGroup extends StatelessWidget {
  const _QualityGroup({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String hint;
  final AudioQuality selected;
  final ValueChanged<AudioQuality> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(SwissGrid.gutter, 0, SwissGrid.gutter, SwissGrid.md),
      child: SwissPanel(
        raised: true,
        padding: const EdgeInsets.all(SwissGrid.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: SwissType.label.copyWith(color: t.ink)),
            if (hint.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(hint, style: SwissType.micro.copyWith(color: t.inkFaint, fontSize: 9)),
            ],
            const SizedBox(height: SwissGrid.md),
            Row(
              children: [
                for (final quality in AudioQuality.values) ...[
                  Expanded(
                    child: TactileKeycap(
                      height: 42,
                      width: double.infinity,
                      accent: selected == quality,
                      glow: selected == quality,
                      onPressed: () {
                        Haptics.commit();
                        onSelected(quality);
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            quality.label,
                            style: SwissType.micro.copyWith(
                              color: selected == quality ? t.accentInk : t.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 9.5,
                            ),
                          ),
                          Text(
                            quality.tag,
                            style: SwissType.micro.copyWith(
                              color: selected == quality
                                  ? t.accentInk.withValues(alpha: 0.75)
                                  : t.inkFaint,
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (quality != AudioQuality.values.last) const SizedBox(width: SwissGrid.xs),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One EQ band: frequency on the left, the machined slider, the gain readout.
class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.band,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int band;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final hz = EqPreset.bandFrequencies[band];
    final label = hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}K' : hz.round().toString();
    final delta = value - 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              '$label HZ',
              style: SwissType.micro.copyWith(color: enabled ? t.inkMuted : t.inkFaint, fontSize: 9),
            ),
          ),
          Expanded(
            child: TactileSlider(
              value: value,
              min: 0,
              max: 4,
              height: 24,
              thumbWidth: 11,
              thumbHeight: 18,
              enabled: enabled,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              '${delta >= 0 ? '+' : '−'}${delta.abs().toStringAsFixed(1)}',
              textAlign: TextAlign.right,
              style: SwissType.mono.copyWith(
                color: !enabled ? t.inkFaint : (delta.abs() < 0.05 ? t.inkMuted : t.accent),
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageCell extends StatelessWidget {
  const _StorageCell({required this.label, required this.value, required this.hint});

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return SwissPanel(
      raised: true,
      padding: const EdgeInsets.all(SwissGrid.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: SwissType.micro.copyWith(color: t.inkFaint, fontSize: 9)),
          const SizedBox(height: SwissGrid.xs),
          Text(value, style: SwissType.displaySm.copyWith(color: t.ink, fontSize: 19)),
          const SizedBox(height: 2),
          Text(hint, style: SwissType.micro.copyWith(color: t.inkFaint, fontSize: 8.5)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.index, required this.title});

  final String index;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(SwissGrid.gutter, SwissGrid.xl, SwissGrid.gutter, SwissGrid.md),
      child: Row(
        children: [
          Text(index, style: SwissType.label.copyWith(color: t.accent)),
          const SizedBox(width: SwissGrid.sm),
          Expanded(
            child: Text(
              title,
              style: SwissType.label.copyWith(color: t.ink, fontWeight: FontWeight.w700),
            ),
          ),
          Container(height: 1, width: 24, color: t.hairline),
        ],
      ),
    );
  }
}

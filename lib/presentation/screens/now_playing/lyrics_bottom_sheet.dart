import 'package:flutter/material.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../data/models/lyrics.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../services/player/playback_service.dart';
import '../../../services/service_locator.dart';
import '../../widgets/track_options_sheet.dart';

/// The lyric sheet.
///
/// LRCLIB returns `[mm:ss.xx]` sheets for most catalogue tracks; when only a
/// plain sheet exists the words are still shown, just without the follow-along.
/// The highlight is driven by the engine's position notifier rather than the
/// cubit, so scrolling follows 4 times a second without rebuilding the player.
Future<void> showLyricsSheet(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LyricsSheet(track: track),
  );
}

class _LyricsSheet extends StatefulWidget {
  const _LyricsSheet({required this.track});

  final Track track;

  @override
  State<_LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<_LyricsSheet> {
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _lineKeys = [];
  Lyrics? _lyrics;
  bool _loading = true;
  bool _failed = false;
  int _active = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    locator<PlaybackService>().position.removeListener(_onPosition);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lyrics = await locator<MusicRepository>().lyricsFor(widget.track);
      if (!mounted) return;
      setState(() {
        _lyrics = lyrics;
        _loading = false;
        _failed = lyrics == null;
        _lineKeys
          ..clear()
          ..addAll(List<GlobalKey>.generate(lyrics?.lines.length ?? 0, (_) => GlobalKey()));
      });
      if (lyrics != null && lyrics.synced) {
        locator<PlaybackService>().position.addListener(_onPosition);
        _onPosition();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _onPosition() {
    final lyrics = _lyrics;
    if (lyrics == null || !lyrics.synced || !mounted) return;
    final index = lyrics.activeIndex(locator<PlaybackService>().position.value);
    if (index == _active) return;
    setState(() => _active = index);
    if (index < 0 || index >= _lineKeys.length) return;
    final keyContext = _lineKeys[index].currentContext;
    if (keyContext == null) return;
    Scrollable.ensureVisible(
      keyContext,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.42,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final lyrics = _lyrics;

    return MusifySheetShell(
      maxHeightFactor: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MusifySheetHeader(
            title: 'LYRICS',
            subtitle: _loading
                ? 'QUERYING LRCLIB…'
                : lyrics == null
                    ? 'NO MATCH IN THE LRCLIB INDEX'
                    : lyrics.synced
                        ? 'SYNCED // LRCLIB'
                        : 'PLAIN TEXT // LRCLIB',
            trailing: TactileIconKeycap(
              icon: Icons.close,
              size: 30,
              iconSize: 15,
              hapticOnPress: false,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Flexible(
            child: _loading
                ? ListView(
                    padding: const EdgeInsets.all(SwissGrid.lg),
                    children: [
                      for (var i = 0; i < 12; i++) ...[
                        SwissSkeleton(height: 13, width: 180 + (i % 4) * 60),
                        const SizedBox(height: SwissGrid.md),
                      ],
                    ],
                  )
                : _failed || lyrics == null || lyrics.isEmpty
                    ? _EmptyLyrics(track: widget.track)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(
                          SwissGrid.lg,
                          SwissGrid.md,
                          SwissGrid.lg,
                          SwissGrid.huge,
                        ),
                        itemCount: lyrics.lines.length,
                        itemBuilder: (context, i) {
                          final line = lyrics.lines[i];
                          final active = i == _active;
                          return GestureDetector(
                            key: _lineKeys.length > i ? _lineKeys[i] : null,
                            behavior: HitTestBehavior.opaque,
                            onTap: line.time == null
                                ? null
                                : () => locator<PlaybackService>().seek(line.time!),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (active)
                                    Container(
                                      width: 2,
                                      height: 18,
                                      margin: const EdgeInsets.only(top: 2, right: SwissGrid.sm),
                                      color: t.accent,
                                    ),
                                  Expanded(
                                    child: Text(
                                      line.text.isEmpty ? '…' : line.text,
                                      style: SwissType.bodySm.copyWith(
                                        color: active
                                            ? t.accent
                                            : (i < _active ? t.inkFaint : t.ink),
                                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                                        fontSize: active ? 14.5 : 13.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (!_loading && lyrics != null && lyrics.synced && lyrics.lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(SwissGrid.lg, SwissGrid.sm, SwissGrid.lg, SwissGrid.md),
              child: Row(
                children: [
                  Text(
                    'TAP A LINE TO JUMP THE PLAYHEAD',
                    style: SwissType.micro.copyWith(color: t.inkFaint),
                  ),
                  const Spacer(),
                  LedDot(active: _active >= 0, size: 6),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyLyrics extends StatelessWidget {
  const _EmptyLyrics({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(SwissGrid.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('00 // NO LYRICS', style: SwissType.label.copyWith(color: t.accent)),
          const SizedBox(height: SwissGrid.sm),
          Text(
            'LRCLIB has no sheet for “${track.title}”. Everything else still works — '
            'the queue, the 8D orbit and the analyser keep running.',
            style: SwissType.bodySm.copyWith(color: t.inkMuted),
          ),
          const SizedBox(height: SwissGrid.lg),
          SwissRule(divisions: 24),
        ],
      ),
    );
  }
}

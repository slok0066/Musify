import 'package:equatable/equatable.dart';

/// One line of a lyric sheet.
class LyricLine extends Equatable {
  const LyricLine({required this.text, this.time});

  final String text;

  /// `null` for unsynced (plain text) sheets.
  final Duration? time;

  bool get isTimed => time != null;

  @override
  List<Object?> get props => [text, time];
}

/// A parsed `.lrc` sheet.
class Lyrics extends Equatable {
  const Lyrics({required this.lines, required this.synced});

  final List<LyricLine> lines;

  /// True when the sheet carries `[mm:ss.xx]` stamps and can auto-scroll.
  final bool synced;

  bool get isEmpty => lines.isEmpty;

  /// Index of the line that should be highlighted for [position].
  /// Returns -1 before the first stamp.
  int activeIndex(Duration position) {
    if (!synced || lines.isEmpty) return -1;
    var lo = 0;
    var hi = lines.length - 1;
    var result = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final t = lines[mid].time;
      if (t == null) {
        lo = mid + 1;
        continue;
      }
      if (t <= position) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }

  /// Parses an LRCLIB payload.
  ///
  /// `syncedLyrics` is preferred; when it is absent the plain sheet is split on
  /// newlines so the user still reads the words, just without a highlight.
  factory Lyrics.parse({String? syncedLyrics, String? plainLyrics}) {
    final syncedRaw = syncedLyrics?.trim();
    if (syncedRaw != null && syncedRaw.isNotEmpty) {
      final lines = <LyricLine>[];
      final stamp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
      for (final raw in syncedRaw.split('\n')) {
        final matches = stamp.allMatches(raw);
        if (matches.isEmpty) continue;
        final text = raw.replaceAll(stamp, '').trim();
        if (text.isEmpty) continue;
        for (final m in matches) {
          final minutes = int.tryParse(m.group(1) ?? '') ?? 0;
          final seconds = int.tryParse(m.group(2) ?? '') ?? 0;
          final fracRaw = m.group(3) ?? '';
          final millis = switch (fracRaw.length) {
            1 => (int.tryParse(fracRaw) ?? 0) * 100,
            2 => (int.tryParse(fracRaw) ?? 0) * 10,
            3 => int.tryParse(fracRaw) ?? 0,
            _ => 0,
          };
          lines.add(
            LyricLine(
              text: text,
              time: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
            ),
          );
        }
      }
      if (lines.isNotEmpty) {
        lines.sort((a, b) => (a.time ?? Duration.zero).compareTo(b.time ?? Duration.zero));
        return Lyrics(lines: lines, synced: true);
      }
    }

    final plain = plainLyrics?.trim();
    if (plain != null && plain.isNotEmpty) {
      final lines = plain
          .split('\n')
          .map((l) => LyricLine(text: l.trim()))
          .where((l) => l.text.isNotEmpty)
          .toList();
      return Lyrics(lines: lines, synced: false);
    }

    return const Lyrics(lines: [], synced: false);
  }

  @override
  List<Object?> get props => [lines, synced];
}

import '../../core/utils/formatters.dart';

/// A YouTube title split into the app's title + primary artist fields.
class ParsedYtTitle {
  const ParsedYtTitle({required this.title, required this.artist});

  final String title;
  final String artist;
}

/// Best-effort normalisation of YouTube video titles:
/// `Kesariya - Arijit Singh (Official Video)` -> `Kesariya` / `Arijit Singh`.
class YtTitles {
  const YtTitles._();

  static final RegExp _noiseGroup = RegExp(
    r'[\(\[](?:[^\)\]]*\b(?:official|lyrics?|audio|video|visuali[sz]er|full song|remaster(?:ed)?|hd|4k|8k)\b[^\)\]]*)[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _separator = RegExp(r'\s+[-–—|]\s+');
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _edgePunctuation = RegExp(r'^[\s\-–—|]+|[\s\-–—|]+$');
  static final RegExp _noiseStart = RegExp(
    r'^(?:official|lyrics?|audio|video|music|full song|visuali[sz]er|remaster)',
    caseSensitive: false,
  );

  static ParsedYtTitle parse(String rawTitle, String fallbackArtist) {
    final original = _tidy(rawTitle);
    final uploader = _tidy(fallbackArtist);

    var title = _tidy(original.replaceAll(_noiseGroup, ' '));
    var artist = '';

    final parts = title.split(_separator);
    if (parts.length == 2) {
      final left = _tidy(parts[0]);
      final right = _tidy(parts[1]);
      if (left.isNotEmpty && right.isNotEmpty) {
        if (_noiseStart.hasMatch(right)) {
          // `Song - Official Video`: the right side is not an artist.
          title = left;
        } else if (_noiseStart.hasMatch(left)) {
          // `Official Video - Song`: the left side is not a title.
          title = right;
        } else {
          title = left;
          artist = right;
        }
      }
    }

    if (title.isEmpty) title = original.isEmpty ? 'Unknown' : original;
    if (artist.isEmpty) artist = uploader.isEmpty ? 'Unknown' : uploader;
    return ParsedYtTitle(title: title, artist: artist);
  }

  static String _tidy(String raw) {
    if (raw.trim().isEmpty) return '';
    return Fmt.cleanTitle(raw)
        .replaceAll(_edgePunctuation, '')
        .replaceAll(_spaces, ' ')
        .trim();
  }
}

enum YtContainer { mp4, webm, other }

/// One audio URL from either resolver, carrying the UA that obtained it.
class YtAudioCandidate {
  const YtAudioCandidate({
    required this.itag,
    required this.container,
    required this.codec,
    required this.bitrateKbps,
    required this.url,
    required this.userAgent,
    required this.source,
  });

  final int itag;
  final YtContainer container;
  final String codec;
  final int bitrateKbps;
  final String url;
  final String userAgent;

  /// `piped` or `youtube_explode_<client>`; only used in failure logs.
  final String source;

  bool get isMp4 => container == YtContainer.mp4;

  bool get isAacMp4 {
    final c = codec.toLowerCase();
    return isMp4 && (c.contains('mp4a') || c.contains('aac'));
  }
}

/// AAC/MP4 first (itag 140 ahead of every other stream), then any MP4, then
/// WebM; highest bitrate first inside each group.
List<YtAudioCandidate> rankYtAudio(Iterable<YtAudioCandidate> input) {
  final out = input.toList()
    ..sort((a, b) {
      final byContainer = _score(b) - _score(a);
      if (byContainer != 0) return byContainer;
      return b.bitrateKbps.compareTo(a.bitrateKbps);
    });
  return out;
}

int _score(YtAudioCandidate candidate) {
  if (candidate.itag == 140) return 3;
  if (candidate.isAacMp4) return 2;
  if (candidate.isMp4) return 1;
  return 0;
}


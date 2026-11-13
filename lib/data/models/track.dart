import 'package:equatable/equatable.dart';

import '../../core/utils/formatters.dart';

/// Which catalogue produced a [Track]. Persisted, so entries written before
/// YouTube-first existed load as [saavn].
enum TrackSource { youtube, saavn }

/// The single unified track shape used by *every* screen, cubit, queue entry
/// and persistence box in Musify.
///
/// Both the JioSaavn resolver and the local offline vault normalise into this,
/// so the player never needs to know where a song came from.
class Track extends Equatable {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.source = TrackSource.saavn,
    this.artistsFull,
    this.album = '',
    this.imageUrl = '',
    this.duration = Duration.zero,
    this.streamUrl,
    this.bitrate = 320,
    this.has320 = true,
    this.localPath,
    this.artistId,
    this.albumId,
    this.permaUrl,
    this.year,
    this.language,
    this.hasLyrics = false,
    this.playCount,
    this.addedAt,
    this.lastPlayedAt,
    this.sizeBytes,
    this.sourceLabel,
  });

  final String id;
  final String title;

  /// Catalogue that produced this entry.
  final TrackSource source;

  bool get isYouTube => source == TrackSource.youtube;

  /// YouTube video id, encoded as `yt:<videoId>` in [id].
  String? get videoId {
    if (!isYouTube || !id.startsWith('yt:')) return null;
    final value = id.substring(3);
    return value.isEmpty ? null : value;
  }

  /// `[YT]` / `[Saavn]` search-row tag.
  String get sourceTag => isYouTube ? 'YT' : 'Saavn';

  /// Display artist — the primary one.
  final String artist;

  /// Full comma-joined artist credit, shown on the Now Playing screen.
  final String? artistsFull;

  final String album;
  final String imageUrl;
  final Duration duration;

  /// A resolved, playable URL (JioSaavn CDN). Null means "not resolved yet" —
  /// the repository fills it in on demand.
  final String? streamUrl;

  /// Actual negotiated bitrate in kbps.
  final int bitrate;

  /// The catalogue advertises a 320 kbps rendition for this track.
  final bool has320;

  /// Absolute path to a downloaded file. When set, playback never touches the
  /// network.
  final String? localPath;

  final String? artistId;
  final String? albumId;
  final String? permaUrl;
  final int? year;
  final String? language;
  final bool hasLyrics;
  final int? playCount;

  final DateTime? addedAt;
  final DateTime? lastPlayedAt;

  /// On-disk size for downloads (`null` until downloaded).
  final int? sizeBytes;

  /// `SEARCH // 320 KBPS AAC` — where this track was started from.
  final String? sourceLabel;

  bool get isDownloaded => localPath != null && localPath!.isNotEmpty;

  /// What the player should actually feed the engine.
  bool get hasPlayableSource =>
      isDownloaded || (streamUrl != null && streamUrl!.isNotEmpty);

  String get displayArtist =>
      artistsFull == null || artistsFull!.isEmpty ? artist : artistsFull!;

  /// `320 KBPS` badge only when the higher rendition is genuinely available.
  String get bitrateLabel => '${isDownloaded ? 320 : bitrate} KBPS';

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    TrackSource? source,
    String? artistsFull,
    String? album,
    String? imageUrl,
    Duration? duration,
    String? streamUrl,
    int? bitrate,
    bool? has320,
    String? localPath,
    bool clearLocalPath = false,
    String? artistId,
    String? albumId,
    String? permaUrl,
    int? year,
    String? language,
    bool? hasLyrics,
    int? playCount,
    DateTime? addedAt,
    DateTime? lastPlayedAt,
    int? sizeBytes,
    String? sourceLabel,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      source: source ?? this.source,
      artistsFull: artistsFull ?? this.artistsFull,
      album: album ?? this.album,
      imageUrl: imageUrl ?? this.imageUrl,
      duration: duration ?? this.duration,
      streamUrl: streamUrl ?? this.streamUrl,
      bitrate: bitrate ?? this.bitrate,
      has320: has320 ?? this.has320,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
      permaUrl: permaUrl ?? this.permaUrl,
      year: year ?? this.year,
      language: language ?? this.language,
      hasLyrics: hasLyrics ?? this.hasLyrics,
      playCount: playCount ?? this.playCount,
      addedAt: addedAt ?? this.addedAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sourceLabel: sourceLabel ?? this.sourceLabel,
    );
  }

  /// Hive/JSON round-trip. Every field is defensively typed because these maps
  /// come back off disk from older app versions.
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'artist': artist,
    'source': source.name,
    'artistsFull': artistsFull,
    'album': album,
    'imageUrl': imageUrl,
    'durationMs': duration.inMilliseconds,
    'streamUrl': streamUrl,
    'bitrate': bitrate,
    'has320': has320,
    'localPath': localPath,
    'artistId': artistId,
    'albumId': albumId,
    'permaUrl': permaUrl,
    'year': year,
    'language': language,
    'hasLyrics': hasLyrics,
    'playCount': playCount,
    'addedAt': addedAt?.millisecondsSinceEpoch,
    'lastPlayedAt': lastPlayedAt?.millisecondsSinceEpoch,
    'sizeBytes': sizeBytes,
    'sourceLabel': sourceLabel,
  };

  static Track? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<Object?, Object?>();
    String str(String key, [String fallback = '']) {
      final v = map[key];
      return v == null ? fallback : v.toString();
    }

    int intAt(String key, [int fallback = 0]) {
      final v = map[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    bool boolAt(String key, [bool fallback = false]) {
      final v = map[key];
      if (v is bool) return v;
      return fallback;
    }

    DateTime? dateAt(String key) {
      final ms = map[key];
      if (ms is num) return DateTime.fromMillisecondsSinceEpoch(ms.toInt());
      return null;
    }

    String? nullable(String key) {
      final v = map[key];
      if (v == null) return null;
      final s = v.toString();
      return s.isEmpty ? null : s;
    }

    final id = str('id');
    final title = str('title');
    if (id.isEmpty && title.isEmpty) return null;

    return Track(
      id: id.isEmpty ? 'local-${title.hashCode}' : id,
      title: title,
      artist: str('artist', 'Unknown'),
      source: TrackSource.values.firstWhere(
        (s) => s.name == map['source']?.toString(),
        orElse: () => TrackSource.saavn,
      ),
      artistsFull: nullable('artistsFull'),
      album: str('album'),
      imageUrl: str('imageUrl'),
      duration: Duration(milliseconds: intAt('durationMs')),
      streamUrl: nullable('streamUrl'),
      bitrate: intAt('bitrate', 320),
      has320: boolAt('has320', true),
      localPath: nullable('localPath'),
      artistId: nullable('artistId'),
      albumId: nullable('albumId'),
      permaUrl: nullable('permaUrl'),
      year: map['year'] is num ? intAt('year') : null,
      language: nullable('language'),
      hasLyrics: boolAt('hasLyrics'),
      playCount: map['playCount'] is num ? intAt('playCount') : null,
      addedAt: dateAt('addedAt'),
      lastPlayedAt: dateAt('lastPlayedAt'),
      sizeBytes: map['sizeBytes'] is num ? intAt('sizeBytes') : null,
      sourceLabel: nullable('sourceLabel'),
    );
  }

  /// Safe list decoder for boxes that store a list of maps.
  static List<Track> listFrom(Object? raw) {
    if (raw is! List) return <Track>[];
    final out = <Track>[];
    for (final entry in raw) {
      final t = fromMap(entry);
      if (t != null) out.add(t);
    }
    return out;
  }

  static List<Map<String, dynamic>> listTo(List<Track> tracks) =>
      tracks.map((t) => t.toMap()).toList();

  /// Stable identity for de-duplication across sources. Two results for the same
  /// recording often differ only by punctuation or the `(From "…")` suffix —
  /// a search row says `Kesariya`, the album row says
  /// `Kesariya (From "Brahmastra")` — so that whole parenthetical group is folded
  /// away first. Without it the queue and history keep two copies of one song.
  String get dedupeKey {
    final normTitle = _normalizeTitle(title);
    final pArtist = _primaryArtist(artist);
    if (pArtist.isNotEmpty) {
      return '$normTitle|$pArtist';
    }
    final a = artist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '$normTitle|$a';
  }

  static List<Track> dedupe(Iterable<Track> input) {
    final seen = <String>{};
    final out = <Track>[];
    for (final t in input) {
      final key = t.dedupeKey;
      if (seen.add(key)) out.add(t);
    }
    return out;
  }

  /// Returns whether [a] and [b] represent the same underlying song recording.
  static bool isDuplicate(Track a, Track b) {
    if (identical(a, b)) return true;
    if (a.id == b.id) return true;
    if (a.videoId != null && b.videoId != null && a.videoId == b.videoId) {
      return true;
    }

    final tA = _normalizeTitle(a.title);
    final tB = _normalizeTitle(b.title);
    if (tA.isEmpty || tB.isEmpty) return false;
    final titleMatch = tA == tB ||
        (tA.length >= 4 && tB.length >= 4 && (tA.startsWith(tB) || tB.startsWith(tA)));
    if (!titleMatch) return false;

    final pA = _primaryArtist(a.artist);
    final pB = _primaryArtist(b.artist);
    if (pA.isNotEmpty && pB.isNotEmpty && (pA == pB || pA.contains(pB) || pB.contains(pA))) {
      return true;
    }

    final aA = _normalizeArtist(a.artist);
    final aB = _normalizeArtist(b.artist);
    if (aA.isEmpty || aB.isEmpty || aA == aB) return true;
    if (aA.contains(aB) || aB.contains(aA)) return true;

    final tokensA = a.artist
        .toLowerCase()
        .split(RegExp(r'[,&/\s]+'))
        .where((s) => s.length > 2)
        .toSet();
    final tokensB = b.artist
        .toLowerCase()
        .split(RegExp(r'[,&/\s]+'))
        .where((s) => s.length > 2)
        .toSet();
    if (tokensA.intersection(tokensB).isNotEmpty) return true;

    if (a.duration > Duration.zero && b.duration > Duration.zero) {
      if ((a.duration - b.duration).inSeconds.abs() <= 6) return true;
    }

    return false;
  }

  static String _normalizeTitle(String text) {
    var cleaned = Fmt.cleanTitle(text);
    // Strip trailing tags like " - Official Video", " | Audio", " - Lyrical", " - Single", etc.
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*[-–—|/]+\s*(?:official\s*(?:video|audio|music\s*video)?|full\s*(?:video|song|audio)|lyrics?|lyrical(?:\s*video)?|audio|video|visuali[sz]er|music\s*video|single|remaster(?:ed)?(?:\s*\d+)?|deluxe(?:\s*edition)?|bonus\s*track)\b.*$',
        caseSensitive: false,
      ),
      '',
    );
    // Strip parenthetical and bracket tags including feat, ft, with, remaster, live, etc.
    final stripped = cleaned.replaceAll(
      RegExp(
        r'\s*[(\[](?:[^()\[\]]*\b(?:from|official|audio|video|lyrics?|full song|visuali[sz]er|feat|ft|featuring|with|remaster(?:ed)?|deluxe|bonus|live|acoustic|slowed|reverb)\b[^()\[\]]*)[)\]]',
        caseSensitive: false,
      ),
      '',
    );
    // Strip trailing standalone "feat. ...", "ft. ..."
    var base = stripped.replaceAll(
      RegExp(r'\s*\b(?:feat\.?|ft\.?|featuring)\b.*$', caseSensitive: false),
      '',
    );
    if (base.trim().isEmpty) base = cleaned;
    return base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _primaryArtist(String artist) {
    if (artist.trim().isEmpty) return '';
    var first = artist.split(RegExp(r'[,&/]|(?:\s+-\s+)|\b(?:feat\.?|ft\.?|featuring|with|x)\b', caseSensitive: false)).first.trim();
    first = first.replaceAll(RegExp(r'\b(?:vevo|topic|official|music)\b', caseSensitive: false), '').trim();
    return first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _normalizeArtist(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Interleaves [primary] and [secondary] tracks while eliminating duplicates.
  static List<Track> mixAndDedupe(
    Iterable<Track> primary,
    Iterable<Track> secondary, {
    int limit = 40,
  }) {
    final listA = primary.toList();
    final listB = secondary.toList();
    final result = <Track>[];
    var iA = 0;
    var iB = 0;

    bool isDup(Track t) {
      for (final existing in result) {
        if (isDuplicate(existing, t)) return true;
      }
      return false;
    }

    while ((iA < listA.length || iB < listB.length) && result.length < limit) {
      while (iA < listA.length) {
        final tA = listA[iA++];
        if (!isDup(tA)) {
          result.add(tA);
          break;
        }
      }
      if (result.length >= limit) break;
      while (iB < listB.length) {
        final tB = listB[iB++];
        if (!isDup(tB)) {
          result.add(tB);
          break;
        }
      }
    }
    return result;
  }

  @override
  List<Object?> get props => [
    id,
    title,
    artist,
    source,
    album,
    imageUrl,
    duration,
    streamUrl,
    bitrate,
    localPath,
    has320,
  ];
}

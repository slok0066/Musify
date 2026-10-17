import 'package:equatable/equatable.dart';

import '../../core/utils/formatters.dart';

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

  /// Display artist — the primary one.
  final String artist;

  /// Full comma-joined artist credit, shown on the Now Playing screen.
  final String? artistsFull;

  final String album;
  final String imageUrl;
  final Duration duration;

  /// A resolved, playable URL (JioSaavn CDN or YouTube fallback). Null means
  /// "not resolved yet" — the repository fills it in on demand.
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
    final cleaned = Fmt.cleanTitle(title);
    final stripped = cleaned.replaceAll(
      RegExp(r'\s*[(\[](?:[^()\[\]]*\bfrom\b[^()\[\]]*)[)\]]', caseSensitive: false),
      '',
    );
    // A title that *is* only a parenthetical must not normalise to nothing.
    final base = stripped.trim().isEmpty ? cleaned : stripped;

    final normalisedTitle = base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final a = artist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '$normalisedTitle|$a';
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

  @override
  List<Object?> get props => [
    id,
    title,
    artist,
    album,
    imageUrl,
    duration,
    streamUrl,
    bitrate,
    localPath,
    has320,
  ];
}

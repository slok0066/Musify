import 'package:equatable/equatable.dart';

import 'track.dart';

/// A music collection shown as a card in a rail or a row in the Library:
/// a chart, an album, a genre playlist, an artist or a user playlist.
enum CollectionKind { album, playlist, artist, chart, genre, mix, system }

class Collection extends Equatable {
  const Collection({
    required this.id,
    required this.title,
    required this.kind,
    this.subtitle = '',
    this.imageUrl = '',
    this.songCount,
    this.permaUrl,
    this.permaToken,
    this.language,
    this.year,
    this.artistId,
    this.dominantColor,
  });

  final String id;
  final String title;
  final CollectionKind kind;
  final String subtitle;
  final String imageUrl;
  final int? songCount;
  final String? permaUrl;

  /// The trailing segment of `perma_url` — what the JioSaavn resolution calls
  /// need for albums and channels.
  final String? permaToken;
  final String? language;
  final int? year;
  final String? artistId;

  /// Optional 0xAARRGGBB tint extracted from artwork, used as the flat plate
  /// colour behind a mosaic card.
  final int? dominantColor;

  bool get isRound => kind == CollectionKind.artist;

  String get kindLabel => switch (kind) {
    CollectionKind.album => 'ALBUM',
    CollectionKind.playlist => 'PLAYLIST',
    CollectionKind.artist => 'ARTIST',
    CollectionKind.chart => 'CHART',
    CollectionKind.genre => 'GENRE',
    CollectionKind.mix => 'MIX',
    CollectionKind.system => 'COLLECTION',
  };

  String? get token {
    if (permaToken != null && permaToken!.isNotEmpty) return permaToken;
    final url = permaUrl;
    if (url == null || url.isEmpty) return null;
    final parts = url.split('/')..removeWhere((p) => p.isEmpty);
    return parts.isEmpty ? null : parts.last;
  }

  Collection copyWith({
    String? id,
    String? title,
    CollectionKind? kind,
    String? subtitle,
    String? imageUrl,
    int? songCount,
    String? permaUrl,
    String? permaToken,
    String? language,
    int? year,
    String? artistId,
    int? dominantColor,
  }) {
    return Collection(
      id: id ?? this.id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      songCount: songCount ?? this.songCount,
      permaUrl: permaUrl ?? this.permaUrl,
      permaToken: permaToken ?? this.permaToken,
      language: language ?? this.language,
      year: year ?? this.year,
      artistId: artistId ?? this.artistId,
      dominantColor: dominantColor ?? this.dominantColor,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'subtitle': subtitle,
    'imageUrl': imageUrl,
    'songCount': songCount,
    'permaUrl': permaUrl,
    'permaToken': permaToken,
    'language': language,
    'year': year,
    'artistId': artistId,
    'dominantColor': dominantColor,
  };

  static Collection? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<Object?, Object?>();
    final id = map['id']?.toString() ?? '';
    final title = map['title']?.toString() ?? '';
    if (id.isEmpty && title.isEmpty) return null;
    final kindName = map['kind']?.toString() ?? 'playlist';
    final kind = CollectionKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => CollectionKind.playlist,
    );
    final count = map['songCount'];
    final yearVal = map['year'];
    final colorVal = map['dominantColor'];

    return Collection(
      id: id,
      title: title,
      kind: kind,
      subtitle: map['subtitle']?.toString() ?? '',
      imageUrl: map['imageUrl']?.toString() ?? '',
      songCount: count is int ? count : int.tryParse(count?.toString() ?? ''),
      permaUrl: map['permaUrl']?.toString(),
      permaToken: map['permaToken']?.toString(),
      language: map['language']?.toString(),
      year: yearVal is int ? yearVal : int.tryParse(yearVal?.toString() ?? ''),
      artistId: map['artistId']?.toString(),
      dominantColor: colorVal is int ? colorVal : int.tryParse(colorVal?.toString() ?? ''),
    );
  }

  static List<Map<String, dynamic>> listTo(List<Collection> list) =>
      list.map((c) => c.toMap()).toList();

  static List<Collection> listFrom(Object? raw) {
    if (raw is! List) return <Collection>[];
    return raw.map(fromMap).whereType<Collection>().toList();
  }

  @override
  List<Object?> get props => [id, title, kind, imageUrl, songCount, permaToken];
}

/// A fully resolved collection — the detail screen's payload.
class CollectionDetail {
  const CollectionDetail({
    required this.collection,
    required this.tracks,
    this.description,
    this.artistBio,
    this.similarArtists = const [],
  });

  final Collection collection;
  final List<Track> tracks;
  final String? description;
  final String? artistBio;
  final List<Collection> similarArtists;

  bool get isEmpty => tracks.isEmpty;
}

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

/// A named rail on the Home screen.
class HomeRail {
  const HomeRail({
    required this.title,
    required this.index,
    required this.items,
    this.kind = CollectionKind.playlist,
    this.subtitle,
    this.tracksArePlayable = false,
    this.tracks = const [],
  });

  final String title;

  /// The `01 //` ordinal rendered before the title.
  final String index;
  final List<Collection> items;
  final CollectionKind kind;
  final String? subtitle;

  /// Some rails (Recently Played, Daily Mixes) are a flat list of playable
  /// tracks rather than collections.
  final bool tracksArePlayable;
  final List<Track> tracks;

  bool get isEmpty => items.isEmpty && tracks.isEmpty;
}

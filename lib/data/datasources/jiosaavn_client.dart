import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../../core/utils/formatters.dart';
import '../models/collection.dart';
import '../models/track.dart';

/// One entry on a Home rail. JioSaavn mixes playable songs, albums and
/// playlists inside a single rail (`new_trending` is 17 albums + 4 playlists +
/// 3 songs), so the UI needs a union rather than a fake uniformity.
class RailItem {
  const RailItem({this.collection, this.track});

  const RailItem.ofCollection(Collection c) : this(collection: c);
  const RailItem.ofTrack(Track t) : this(track: t);

  final Collection? collection;
  final Track? track;

  bool get isTrack => track != null;
  bool get isCollection => collection != null;

  String get dedupeKey =>
      track != null ? 't:${track!.dedupeKey}' : 'c:${collection!.kind.name}:${collection!.id}';

  String get title => track?.title ?? collection?.title ?? '';
  String get subtitle => track?.displayArtist ?? collection?.subtitle ?? '';
  String get imageUrl => track?.imageUrl ?? collection?.imageUrl ?? '';
}

/// The entire launch payload in one round trip.
class LaunchPayload {
  const LaunchPayload({
    this.trending = const [],
    this.playlists = const [],
    this.albums = const [],
    this.charts = const [],
    this.genres = const [],
    this.topSearches = const [],
  });

  final List<RailItem> trending;
  final List<RailItem> playlists;
  final List<RailItem> albums;
  final List<RailItem> charts;
  final List<Collection> genres;
  final List<Track> topSearches;

  bool get isEmpty =>
      trending.isEmpty &&
      playlists.isEmpty &&
      albums.isEmpty &&
      charts.isEmpty &&
      genres.isEmpty;
}

/// JioSaavn API client.
///
/// Talks to the public `api.php` endpoint with `api_version=4`, which returns
/// 320 kbps AAC renditions. Stream URLs arrive DES-encrypted and are decrypted
/// locally — no third-party relay, no API key, no server.
///
/// ## On the DES key
/// [pointycastle] 4.x ships `DESedeEngine` but no single-DES engine. 3DES with
/// three identical subkeys (`E_K(D_K(E_K(x)))`) is *exactly* single DES, so the
/// 8-byte key is repeated three times. `tool/des_check.dart` proves this
/// against a captured ciphertext.
///
/// Every parse is defensive: the catalogue is user-generated, so a null title,
/// a missing artwork or a malformed artist map must never throw.
class JioSaavnClient {
  JioSaavnClient(this._dio);

  final Dio _dio;

  static const String _base = 'https://www.jiosaavn.com/api.php';
  static const List<int> _desKey = [0x33, 0x38, 0x33, 0x34, 0x36, 0x35, 0x39, 0x31]; // '38346591'

  /// songId -> still-encrypted media url, so a queue only ever resolves once.
  final Map<String, String> _encryptedMediaCache = {};

  /// songId -> resolved url at a given bitrate.
  final Map<String, String> _resolvedCache = {};

  final Map<String, LaunchPayload> _launchCache = {};
  DateTime? _launchFetchedAt;

  void clearCaches() {
    _resolvedCache.clear();
    _launchCache.clear();
    _launchFetchedAt = null;
  }

  // ---------------------------------------------------------------- transport

  /// Issues an `api.php` call and decodes the JSON payload.
  ///
  /// Response type is forced to plain text because JioSaavn sometimes labels
  /// JSON as `text/html`; decoding it by hand is the only reliable path.
  Future<Object?> _call(
    String function, [
    Map<String, String> params = const {},
  ]) async {
    try {
      final response = await _dio.get<dynamic>(
        _base,
        queryParameters: {
          '__call': function,
          '_format': 'json',
          '_marker': '0',
          'api_version': '4',
          'ctx': 'web6dot0',
          ...params,
        },
        options: Options(responseType: ResponseType.plain),
      );

      final raw = response.data;
      if (raw is Map) return raw;
      if (raw is List) return raw;
      if (raw is! String || raw.isEmpty) return null;

      final trimmed = raw.trim();
      if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
      return jsonDecode(trimmed);
    } catch (e) {
      debugPrint('JioSaavn $_call failed: $e');
      return null;
    }
  }

  Map<String, dynamic>? _asMap(Object? raw) =>
      raw is Map ? raw.cast<String, dynamic>() : null;

  List<Map<String, dynamic>> _asList(Object? raw) {
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  // ------------------------------------------------------------------- public

  /// The whole Home feed from a single `webapi.getLaunchData` call, cached for
  /// ten minutes so pull-to-refresh is meaningful but tab switching never
  /// re-hits the network.
  Future<LaunchPayload> fetchLaunch({bool refresh = false}) async {
    final fresh = _launchFetchedAt != null &&
        DateTime.now().difference(_launchFetchedAt!) < const Duration(minutes: 10);
    if (!refresh && fresh) {
      final cached = _launchCache['launch'];
      if (cached != null) return cached;
    }

    final raw = await _call('webapi.getLaunchData');
    final map = _asMap(raw);
    if (map == null) {
      return _launchCache['launch'] ?? const LaunchPayload();
    }

    List<RailItem> rail(String key) {
      return _asList(map[key]).map(_parseRailItem).whereType<RailItem>().toList();
    }

    final payload = LaunchPayload(
      trending: rail('new_trending'),
      playlists: rail('top_playlists'),
      albums: rail('new_albums'),
      charts: rail('charts'),
      genres: _asList(map['browse_discover'])
          .map(_parseChannel)
          .whereType<Collection>()
          .toList(),
      topSearches: <Track>[],
    );

    _launchCache['launch'] = payload;
    _launchFetchedAt = DateTime.now();
    return payload;
  }

  /// Songs the country is searching for right now — a playable rail without
  /// needing a second catalogue call per item.
  Future<List<Track>> fetchTopSearches() async {
    final raw = await _call('content.getTopSearches');
    return _asList(raw).map(_parseSong).whereType<Track>().toList();
  }

  /// Additional charts (`content.getCharts`) — richer than launch data's set.
  Future<List<Collection>> fetchCharts() async {
    final raw = await _call('content.getCharts');
    return _asList(raw)
        .map(
          (e) => Collection(
            id: _str(e['id']),
            title: Fmt.cleanTitle(_str(e['title'])),
            kind: CollectionKind.chart,
            subtitle: 'JIOSAAVN',
            imageUrl: hires(_str(e['image'])),
            songCount: _int(e['count']),
            permaUrl: _str(e['perma_url']),
            permaToken: _token(e['perma_url']),
          ),
        )
        .where((c) => c.id.isNotEmpty)
        .toList();
  }

  /// Featured/editorial playlists — used for the daily mixes fallback.
  Future<List<Collection>> fetchFeaturedPlaylists({int limit = 20}) async {
    final raw = await _call('content.getFeaturedPlaylists', {'n': '$limit'});
    final map = _asMap(raw);
    return _asList(map?['data'])
        .map(_parseCollectionLike)
        .whereType<Collection>()
        .toList();
  }

  // ------------------------------------------------------------------ search

  Future<List<Track>> searchSongs(
    String query, {
    int page = 1,
    int limit = 30,
  }) async {
    if (query.trim().isEmpty) return const [];
    final raw = await _call('search.getResults', {
      'q': query,
      'n': '$limit',
      'p': '$page',
    });
    final map = _asMap(raw);
    return _asList(map?['results']).map(_parseSong).whereType<Track>().toList();
  }

  Future<List<Collection>> searchAlbums(String query, {int limit = 20}) async {
    final raw = await _call('search.getAlbumResults', {'q': query, 'n': '$limit'});
    final map = _asMap(raw);
    return _asList(map?['results'])
        .map((e) => _parseCollectionLike(e, fallback: CollectionKind.album))
        .whereType<Collection>()
        .toList();
  }

  Future<List<Collection>> searchPlaylists(String query, {int limit = 20}) async {
    final raw = await _call('search.getPlaylistResults', {'q': query, 'n': '$limit'});
    final map = _asMap(raw);
    return _asList(map?['results'])
        .map((e) => _parseCollectionLike(e, fallback: CollectionKind.playlist))
        .whereType<Collection>()
        .toList();
  }

  Future<List<Collection>> searchArtists(String query, {int limit = 20}) async {
    final raw = await _call('search.getArtistResults', {'q': query, 'n': '$limit'});
    final map = _asMap(raw);
    return _asList(map?['results'])
        .map(_parseArtistItem)
        .whereType<Collection>()
        .toList();
  }

  /// Live suggestions for the search field.
  ///
  /// JioSaavn has no autocomplete endpoint (`getAutocompleteSuggestions` is
  /// explicitly unsupported by the API), so a shallow search over a small
  /// result window is used and the titles are de-duplicated into suggestion
  /// rows.
  Future<List<String>> suggest(String query) async {
    final tracks = await searchSongs(query, limit: 8);
    return Track.dedupe(tracks).map((t) => t.title).toSet().take(7).toList();
  }

  // ------------------------------------------------------------------ detail

  /// Resolves an album (either by numeric id or perma token).
  Future<CollectionDetail?> albumDetail(Collection collection) async {
    var songs = <Track>[];

    final byId = await _call('content.getAlbumDetails', {'albumid': collection.id});
    songs = _asList(_asMap(byId)?['songs']).map(_parseSong).whereType<Track>().toList();

    if (songs.isEmpty) {
      final token = collection.token;
      if (token != null) {
        final byToken = await _call('webapi.get', {
          'token': token,
          'type': 'album',
          'n': '100',
        });
        final map = _asMap(byToken);
        songs = _asList(map?['songs'] ?? map?['list'])
            .map(_parseSong)
            .whereType<Track>()
            .toList();
      }
    }

    if (songs.isEmpty && collection.title.trim().isNotEmpty) {
      final searchResults = await searchAlbums(collection.title, limit: 3);
      if (searchResults.isNotEmpty && searchResults.first.id != collection.id) {
        final fallback = await albumDetail(searchResults.first);
        if (fallback != null && fallback.tracks.isNotEmpty) {
          return fallback;
        }
      }
    }

    if (songs.isEmpty && collection.permaUrl == null) return null;

    return CollectionDetail(
      collection: collection.copyWith(songCount: songs.length),
      tracks: Track.dedupe(songs),
      description: collection.subtitle.isEmpty ? null : collection.subtitle,
    );
  }

  /// Resolves a playlist or chart.
  ///
  /// `playlist.getDetails` paginates hard (25 per page), so long charts are
  /// walked until `list_count` is satisfied or a page comes back empty.
  Future<CollectionDetail?> playlistDetail(
    Collection collection, {
    int maxTracks = 100,
  }) async {
    final tracks = <Track>[];
    var page = 1;
    var total = 0;
    String? resolvedTitle;
    String? resolvedImage;
    String? description;

    while (tracks.length < maxTracks && page <= 5) {
      final raw = await _call('playlist.getDetails', {
        'listid': collection.id,
        'n': '50',
        'p': '$page',
      });
      final map = _asMap(raw);
      if (map == null) break;

      resolvedTitle ??= Fmt.cleanTitle(_str(map['title']));
      resolvedImage ??= hires(_str(map['image']));
      description ??= Fmt.cleanTitle(_str(map['header_desc']));
      total = _int(map['list_count']) ?? total;

      final batch = _asList(map['list']).map(_parseSong).whereType<Track>().toList();
      if (batch.isEmpty) break;
      tracks.addAll(batch);

      if (total > 0 && tracks.length >= total) break;
      if (batch.length < 25) break;
      page++;
    }

    if (tracks.isEmpty) return null;

    return CollectionDetail(
      collection: collection.copyWith(
        title: (resolvedTitle ?? '').isEmpty ? collection.title : resolvedTitle,
        imageUrl: (resolvedImage ?? '').isEmpty ? collection.imageUrl : resolvedImage,
        songCount: tracks.length,
      ),
      tracks: Track.dedupe(tracks),
      description: (description ?? '').isEmpty ? null : description,
    );
  }

  /// Resolves an artist: top songs, albums, singles and similar artists.
  Future<CollectionDetail?> artistDetail(Collection artist) async {
    final raw = await _call('artist.getArtistPageDetails', {
      'artistId': artist.id,
      'n': '20',
    });
    var map = _asMap(raw);
    if (map == null || _asList(map['topSongs']).isEmpty) {
      if (artist.title.trim().isNotEmpty) {
        final searchResults = await searchArtists(artist.title, limit: 3);
        if (searchResults.isNotEmpty && searchResults.first.id != artist.id) {
          final fallbackRaw = await _call('artist.getArtistPageDetails', {
            'artistId': searchResults.first.id,
            'n': '20',
          });
          final fallbackMap = _asMap(fallbackRaw);
          if (fallbackMap != null && _asList(fallbackMap['topSongs']).isNotEmpty) {
            map = fallbackMap;
          }
        }
      }
    }
    if (map == null) return null;

    final tracks = <Track>[
      ..._asList(map['topSongs']).map(_parseSong).whereType<Track>(),
      ..._asList(map['singles']).map(_parseSong).whereType<Track>(),
    ];

    final similar = <Collection>[
      ..._asList(map['featured_artist_playlist'])
          .map(_parseCollectionLike)
          .whereType<Collection>(),
      ..._asList(map['similarArtists'])
          .map(_parseArtistItem)
          .whereType<Collection>(),
    ];

    final bio = Fmt.cleanTitle(_str(map['bio']));

    return CollectionDetail(
      collection: artist.copyWith(
        title: Fmt.cleanTitle(_str(map['name'], artist.title)),
        imageUrl: hires(_str(map['image'], artist.imageUrl)),
        songCount: tracks.length,
        subtitle: Fmt.compactCount(_int(map['follower_count'])) == '—'
            ? artist.subtitle
            : '${Fmt.compactCount(_int(map['follower_count']))} FOLLOWERS',
      ),
      tracks: Track.dedupe(tracks),
      artistBio: bio.isEmpty ? null : bio,
      similarArtists: similar,
    );
  }

  /// A genre tile's contents.
  ///
  /// JioSaavn's `browse_discover` entries are *channels*, and neither
  /// `playlist.getDetails` nor `webapi.get?type=channel` serves their track
  /// lists. The reliable route is to search playlists for the genre, then open
  /// the fullest match — with a flat song search as the last resort.
  Future<CollectionDetail?> genreDetail(Collection genre) async {
    final query = genre.title;

    final playlists = await searchPlaylists(query, limit: 8);
    final viable = playlists
        .where((p) => (p.songCount ?? 0) >= 5 || p.songCount == null)
        .toList()
      ..sort((a, b) => (b.songCount ?? 0).compareTo(a.songCount ?? 0));

    if (viable.isNotEmpty) {
      final detail = await playlistDetail(viable.first, maxTracks: 60);
      if (detail != null && detail.tracks.length >= 5) {
        return CollectionDetail(
          collection: detail.collection.copyWith(
            kind: CollectionKind.genre,
            title: genre.title,
          ),
          tracks: detail.tracks,
          description: 'CURATED FROM JIOSAAVN · ${genre.title}',
        );
      }
    }

    final songs = await searchSongs(query, limit: 50);
    if (songs.isEmpty) return null;

    return CollectionDetail(
      collection: Collection(
        id: genre.id,
        title: genre.title,
        kind: CollectionKind.genre,
        subtitle: 'SONG MATCHES',
        imageUrl: genre.imageUrl,
      ),
      tracks: Track.dedupe(songs),
      description: 'MATCHED BY SONG QUERY',
    );
  }

  // ------------------------------------------------------------------ streams

  /// Resolves a playable URL for [songId] at up to [preferredKbps].
  ///
  /// The 320 kbps rendition does not exist for every release, so the ladder
  /// walks down to 160 and 96 rather than handing the engine a dead link.
  Future<String?> resolveStreamUrl(
    String songId, {
    int preferredKbps = 320,
  }) async {
    final cachedKey = '$songId@$preferredKbps';
    final cached = _resolvedCache[cachedKey];
    if (cached != null) return cached;

    var encrypted = _encryptedMediaCache[songId];
    if (encrypted == null || encrypted.isEmpty) {
      final raw = await _call('song.getDetails', {'pids': songId});
      final songs = _asList(_asMap(raw)?['songs']);
      if (songs.isEmpty) return null;
      final more = _map(songs.first['more_info']);
      encrypted = _str(
        more['encrypted_media_url'] ?? more['encrypted_des_media_url'],
      );
      if (encrypted.isEmpty) {
        // Some very old catalogue entries only expose the encrypted *path*,
        // which resolves against a CDN host instead of a full URL.
        final path = _str(more['encrypted_media_path']);
        final decoded = path.isEmpty ? null : decryptMediaUrl(path);
        if (decoded == null) return null;
        final url = rewriteBitrate(
          decoded.startsWith('http') ? decoded : 'https://aac.saavncdn.com/$decoded',
          preferredKbps,
        );
        _resolvedCache[cachedKey] = url;
        return url;
      }
      _encryptedMediaCache[songId] = encrypted;
    }

    final decoded = decryptMediaUrl(encrypted);
    if (decoded == null || decoded.isEmpty) return null;

    final url = rewriteBitrate(decoded, preferredKbps);
    _resolvedCache[cachedKey] = url;
    return url;
  }

  /// Notes the encrypted media url for a song id so `resolveStreamUrl` never
  /// has to fetch `song.getDetails` for a row that came out of a search.
  void rememberEncrypted(String songId, String encrypted) {
    if (songId.isEmpty || encrypted.isEmpty) return;
    _encryptedMediaCache.putIfAbsent(songId, () => encrypted);
  }

  // ------------------------------------------------------------------ parsing

  // --------------------------------------------------------- Law 7 test seams
  //
  // The coercers below are private because the app only ever reaches them
  // through a network call — which used to make hostile-payload behaviour
  // untestable. These wrappers are the entire added surface: one line each, no
  // logic, so `test/jiosaavn_parsing_test.dart` can pin down what happens when
  // JioSaavn sends nulls, numbers-as-strings, `'false'`, HTML entities or a
  // missing `encrypted_media_url`. Do not grow them.

  /// [JioSaavnClient._parseSong] — one catalogue song → [Track].
  @visibleForTesting
  Track? parseSong(Map<String, dynamic> json) => _parseSong(json);

  /// [JioSaavnClient._parseRailItem] — the song/album/playlist rail union.
  @visibleForTesting
  RailItem? parseRailItem(Map<String, dynamic> json) => _parseRailItem(json);

  /// [JioSaavnClient._parseCollectionLike] — album / playlist / artist card.
  @visibleForTesting
  Collection? parseCollection(
    Map<String, dynamic> json, {
    CollectionKind fallback = CollectionKind.playlist,
  }) =>
      _parseCollectionLike(json, fallback: fallback);

  /// The still-encrypted media url remembered for [songId] while parsing — the
  /// hand-off between "we saw this song" and `resolveStreamUrl`.
  @visibleForTesting
  String? rememberedEncrypted(String songId) => _encryptedMediaCache[songId];

  RailItem? _parseRailItem(Map<String, dynamic> json) {
    final type = _str(json['type']).toLowerCase();
    if (type == 'song') {
      final track = _parseSong(json);
      return track == null ? null : RailItem.ofTrack(track);
    }
    final collection = _parseCollectionLike(json);
    return collection == null ? null : RailItem.ofCollection(collection);
  }

  Collection? _parseCollectionLike(
    Map<String, dynamic> json, {
    CollectionKind fallback = CollectionKind.playlist,
  }) {
    final id = _str(json['id']);
    if (id.isEmpty) return null;

    final rawType = _str(json['type']).toLowerCase();
    final kind = switch (rawType) {
      'album' => CollectionKind.album,
      'playlist' => CollectionKind.playlist,
      'artist' => CollectionKind.artist,
      'channel' => CollectionKind.genre,
      _ => fallback,
    };

    final more = _map(json['more_info']);
    final musicLine = Fmt.cleanTitle(_str(more['music']));
    // `Fmt.cleanTitle` answers with the 'Unknown' sentinel for an empty string,
    // which would make the emptiness check below dead code — normalise it back.
    final music = musicLine == 'Unknown' ? '' : musicLine;
    final subtitle = Fmt.cleanTitle(_str(json['subtitle']));

    var line = subtitle;
    if (line.isEmpty || line == 'Unknown') {
      line = music.isEmpty ? (kind == CollectionKind.album ? 'ALBUM' : 'PLAYLIST') : music;
    }

    return Collection(
      id: id,
      title: Fmt.cleanTitle(_str(json['title'])),
      kind: kind,
      subtitle: line,
      imageUrl: hires(_str(json['image'])),
      songCount: _int(more['song_count']) ?? _int(json['list_count']) ?? _int(json['count']),
      permaUrl: _str(json['perma_url']),
      permaToken: _token(json['perma_url']),
      language: _str(json['language']).isEmpty ? null : Fmt.cleanTitle(_str(json['language'])),
      year: _int(json['year']),
    );
  }

  Collection? _parseChannel(Map<String, dynamic> json) {
    final id = _str(json['id']);
    final title = Fmt.cleanTitle(_str(json['title']));
    if (id.isEmpty || title.isEmpty) return null;
    return Collection(
      id: id,
      title: title,
      kind: CollectionKind.genre,
      subtitle: Fmt.cleanTitle(_str(json['subtitle'])),
      imageUrl: hires(_str(json['image'])),
      permaUrl: _str(json['perma_url']),
      permaToken: _token(json['perma_url']),
    );
  }

  Collection? _parseArtistItem(Map<String, dynamic> json) {
    final id = _str(json['id'] ?? json['artistId']);
    final name = Fmt.cleanTitle(_str(json['title'] ?? json['name']));
    if (id.isEmpty || name.isEmpty) return null;
    final more = _map(json['more_info']);
    return Collection(
      id: id,
      title: name,
      kind: CollectionKind.artist,
      subtitle: Fmt.cleanTitle(_str(more['artist_name'] ?? json['subtitle'])),
      imageUrl: hires(_str(json['image'])),
      permaUrl: _str(json['perma_url']),
      artistId: id,
    );
  }

  /// The workhorse: normalises one catalogue song into a [Track].
  Track? _parseSong(Map<String, dynamic> json) {
    final id = _str(json['id']);
    if (id.isEmpty) return null;

    final more = _map(json['more_info']);
    final artistMap = _map(more['artistMap']);
    final primaries = _asList(artistMap['primary_artists']);
    final featured = _asList(artistMap['featured_artists']);

    final primaryNames = primaries.map((a) => Fmt.cleanTitle(_str(a['name']))).where(_notBlank).toList();
    final featuredNames = featured.map((a) => Fmt.cleanTitle(_str(a['name']))).where(_notBlank).toList();

    // `subtitle` is the human credit line, but it also carries album blurbs;
    // the artist map is the trustworthy source when it is populated.
    final subtitleLine = Fmt.cleanTitle(_str(json['subtitle']));
    final artist = primaryNames.isNotEmpty
        ? primaryNames.join(', ')
        : Fmt.primaryArtist(subtitleLine);
    final creditLine = {
      ...primaryNames,
      ...featuredNames,
    }.join(', ');

    final encrypted = _str(more['encrypted_media_url']);
    if (encrypted.isNotEmpty) rememberEncrypted(id, encrypted);

    // An entry can exist in `primary_artists` with a blank id/name; the model's
    // nullable `artistId` must stay null rather than become '' — callers use
    // `artistId != null` to decide whether "go to artist" is offered.
    final artistId = primaries.isEmpty ? '' : _str(primaries.first['id']);

    final durationSeconds = _int(more['duration']) ?? _int(json['duration']) ?? 0;

    return Track(
      id: id,
      title: Fmt.cleanTitle(_str(json['title'])),
      artist: artist.isEmpty ? 'Unknown' : artist,
      artistsFull: creditLine.isEmpty
          ? (subtitleLine.isEmpty ? null : subtitleLine)
          : creditLine,
      album: Fmt.cleanTitle(_str(more['album'])),
      imageUrl: hires(_str(json['image'])),
      duration: Duration(seconds: durationSeconds),
      streamUrl: null,
      bitrate: 320,
      has320: _bool(more['320kbps'], fallback: true),
      artistId: artistId.isEmpty ? null : artistId,
      albumId: _str(more['album_id']).isEmpty ? null : _str(more['album_id']),
      permaUrl: _str(json['perma_url']),
      year: _int(json['year']),
      language: _str(json['language']).isEmpty ? null : Fmt.cleanTitle(_str(json['language'])),
      hasLyrics: _bool(more['has_lyrics']),
      playCount: _int(json['play_count']),
    );
  }

  // ------------------------------------------------------------------ helpers

  /// `-150x150.jpg` → `-500x500.jpg`. The CDN serves any square size and the
  /// catalogue only ever advertises the thumbnail.
  static String hires(String url, {int size = 500}) {
    if (url.trim().isEmpty) return '';
    var clean = url.trim().replaceAll('http://', 'https://');
    clean = clean.replaceAllMapped(
      RegExp(r'(\d+)x(\d+)(\.(jpg|jpeg|png|webp))', caseSensitive: false),
      (match) => '${size}x$size${match.group(3)}',
    );
    return clean;
  }

  /// Swaps the rendition suffix: `…_96.mp4` → `…_320.mp4`.
  ///
  /// This is the rung that delivers the "320 kbps" promise, so it is pinned by
  /// `test/jiosaavn_parsing_test.dart`.
  @visibleForTesting
  static String rewriteBitrate(String url, int kbps) {
    final pattern = RegExp(r'_\d{1,3}\.(mp4|m4a|aac|mp3)$', caseSensitive: false);
    if (pattern.hasMatch(url)) {
      return url.replaceAllMapped(pattern, (m) => '_$kbps.${m.group(1)}');
    }
    // `.mp4` with no rendition marker: assume it is already the best master.
    return url;
  }

  /// DES-ECB / PKCS7 decryption of a catalogue media url.
  ///
  /// Public only so the crypto can be asserted offline (§`test/jiosaavn_parsing_test.dart`
  /// pins the fixture from `tool/des_check.dart`).
  @visibleForTesting
  static String? decryptMediaUrl(String input) {
    try {
      var normalized = input.replaceAll('-', '+').replaceAll('_', '/');
      final remainder = normalized.length % 4;
      if (remainder != 0) normalized += '=' * (4 - remainder);

      final data = base64.decode(normalized);
      if (data.isEmpty || data.length % 8 != 0) return null;

      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        ECBBlockCipher(DESedeEngine()),
      );
      // 3DES with three identical subkeys is single DES.
      cipher.init(
        false,
        PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
          KeyParameter(Uint8List.fromList([..._desKey, ..._desKey, ..._desKey])),
          null,
        ),
      );
      final clear = cipher.process(Uint8List.fromList(data));
      final text = utf8.decode(clear, allowMalformed: true);
      return text.isEmpty ? null : text;
    } catch (e) {
      debugPrint('DES decrypt failed: $e');
      return null;
    }
  }

  static Map<String, dynamic> _map(Object? raw) =>
      raw is Map ? raw.cast<String, dynamic>() : const {};

  static String _str(Object? raw, [String fallback = '']) {
    if (raw == null) return fallback;
    final s = raw.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static int? _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static bool _bool(Object? raw, {bool fallback = false}) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final v = raw.trim().toLowerCase();
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0' || v.isEmpty) return false;
    }
    return fallback;
  }

  static bool _notBlank(String value) => value.trim().isNotEmpty;

  static String? _token(Object? permaUrl) {
    final url = _str(permaUrl);
    if (url.isEmpty) return null;
    final parts = url.split('/')..removeWhere((p) => p.isEmpty);
    return parts.isEmpty ? null : parts.last;
  }
}

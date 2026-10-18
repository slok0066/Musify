import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/utils/formatters.dart';
import '../../services/media_cache.dart';
import '../../services/network_monitor.dart';
import '../../services/player/playback_service.dart';
import '../../services/settings_service.dart';
import '../datasources/artwork_client.dart';
import '../datasources/jiosaavn_client.dart';
import '../datasources/lyrics_client.dart';
import '../models/collection.dart';
import '../models/lyrics.dart';
import '../models/track.dart';

/// Everything the Home screen renders, fetched in one orchestrated pass.
class HomeFeed {
  const HomeFeed({
    this.trending = const [],
    this.charts = const [],
    this.playlists = const [],
    this.albums = const [],
    this.genres = const [],
    this.topSearches = const [],
    this.featuredHits = const [],
    this.isOffline = false,
    this.hasData = false,
  });

  final List<RailItem> trending;
  final List<RailItem> charts;
  final List<RailItem> playlists;
  final List<RailItem> albums;
  final List<Collection> genres;
  final List<Track> topSearches;
  final List<Track> featuredHits;

  /// True when the device has no transport — Home swaps its rails for the
  /// local vault instead of showing an error.
  final bool isOffline;

  /// False when every remote rail came back empty.
  final bool hasData;
}

/// The four search facets the Search screen filters between.
class SearchResults {
  const SearchResults({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.query = '',
  });

  final List<Track> songs;
  final List<Collection> albums;
  final List<Collection> artists;
  final List<Collection> playlists;
  final String query;

  bool get isEmpty =>
      songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  int get total => songs.length + albums.length + artists.length + playlists.length;
}

/// The library-backed facets Home needs when it is offline.
class OfflineFallback {
  const OfflineFallback({this.downloads = const [], this.history = const []});

  final List<Track> downloads;
  final List<Track> history;

  bool get isEmpty => downloads.isEmpty && history.isEmpty;
}

/// Orchestrates every remote catalogue and local byte in Musify.
///
/// · **Playback resolution waterfall** — offline file → stream cache →
///   JioSaavn 320 → 160 → 96 → direct URL. The player never has to know where
///   a track came from, and a dead rendition degrades instead of failing.
/// · **Home** — one `webapi.getLaunchData` call drives every rail.
/// · **Artwork** — JioSaavn thumbnails are silently upgraded to 1000 px when
///   Deezer or iTunes has a better cover.
class MusicRepository {
  MusicRepository({
    required JioSaavnClient saavn,
    required LyricsClient lyrics,
    required ArtworkClient artwork,
    required MediaCache cache,
    required SettingsService settings,
    required NetworkMonitor network,
  })  : _saavn = saavn,
        _lyrics = lyrics,
        _artwork = artwork,
        _cache = cache,
        _settings = settings,
        _network = network;

  final JioSaavnClient _saavn;
  final LyricsClient _lyrics;
  final ArtworkClient _artwork;
  final MediaCache _cache;
  final SettingsService _settings;
  final NetworkMonitor _network;

  // ------------------------------------------------------------ playability

  /// The quality tier to request right now: the Wi-Fi tier on an unmetered
  /// transport, the mobile tier otherwise.
  int get targetBitrate {
    final s = _settings.value;
    return _network.isUnmetered.value ? s.wifiQuality.kbps : s.mobileQuality.kbps;
  }

  /// Resolves a [Track] into something the engine can load.
  ///
  /// [prefetch] is used for the *next* queue entry: it stages the bytes without
  /// blocking playback, which is what makes transitions and crossfades
  /// instant. It never reports progress because nothing is waiting on it.
  Future<PlayableSource?> resolvePlayable(
    Track track, {
    ValueChanged<double?>? onProgress,
    bool prefetch = false,
  }) async {
    // 1. A real offline download always wins — it needs no network at all.
    final downloaded = _existingPath(track.localPath);
    if (downloaded != null) {
      return PlayableSource(path: downloaded, isLocalFile: true, bitrate: 320);
    }

    if (!_network.isOnline.value && !prefetch) {
      // Offline and not cached: let the caller show the offline message rather
      // than hanging on a DNS timeout.
      final cachedOnly = await _cachedOnlySource(track);
      return cachedOnly;
    }

    // 2. Walk the renditions from best to worst.
    final ladder = renditionLadder(target: targetBitrate, has320: track.has320);
    String? lastResortUrl;

    for (final kbps in ladder) {
      final url = await _saavn.resolveStreamUrl(track.id, preferredKbps: kbps);
      if (url == null || url.isEmpty) continue;

      final fileName = MediaCache.downloadFileName(songId: track.id, kbps: kbps);

      if (prefetch) {
        final staged = await _cache.prefetch(url: url, fileName: fileName);
        return PlayableSource(
          path: staged ?? url,
          isLocalFile: staged != null,
          bitrate: kbps,
        );
      }

      final staged = await _cache.ensure(
        url: url,
        fileName: fileName,
        onProgress: (progress) => onProgress?.call(progress.fraction),
      );

      if (staged != null) {
        return PlayableSource(path: staged, isLocalFile: true, bitrate: kbps);
      }
      lastResortUrl ??= url;
    }

    // 3. Nothing could be staged — hand the engine a raw URL and let SoLoud
    //    stream it directly. Slower to start, but it still plays.
    if (lastResortUrl != null) {
      return PlayableSource(path: lastResortUrl, isLocalFile: false, bitrate: 160);
    }
    return null;
  }

  /// The renditions worth trying, best first.
  ///
  /// A track the catalogue already flagged as `has320: false` skips the 320
  /// rung: on a slow connection that wasted round trip was a second of the
  /// user's life for a file that was never there.
  @visibleForTesting
  static List<int> renditionLadder({required int target, required bool has320}) {
    final wanted = <int>{target, 320, 160, 96};
    final out = wanted.where((kbps) => has320 || kbps < 320).toList()
      ..sort((a, b) => b.compareTo(a));
    return out.isEmpty ? const [96] : out;
  }

  /// Resolves [track] to a source that can be read **while it downloads**, for
  /// the progressive decoder. Nothing is waited for: the caller gets a
  /// [StreamSession] and pulls bytes out of it as it needs them.
  ///
  /// The order is deliberate:
  ///
  /// 1. any complete local copy — an offline download, then the stream cache;
  ///    both need no network at all and skip the whole-file decode that made
  ///    replays slow,
  /// 2. otherwise a live transfer over the best rendition the catalogue has.
  ///
  /// Returns `null` when nothing can be streamed; the caller then falls back to
  /// [resolvePlayable]'s staged download.
  Future<StreamSource?> openStream(Track track) async {
    final loopback = await _completeSession(track);
    if (loopback != null) return loopback;

    if (!_network.isOnline.value) return null;

    for (final kbps
        in renditionLadder(target: targetBitrate, has320: track.has320)) {
      final url = await _saavn.resolveStreamUrl(track.id, preferredKbps: kbps);
      if (url == null || url.isEmpty) continue;

      final fileName = MediaCache.downloadFileName(songId: track.id, kbps: kbps);
      final session = await _cache.openStream(url: url, fileName: fileName);
      if (session == null) continue;

      final total = session.total;
      if (total == null || total < 64 * 1024) {
        session.release();
        continue;
      }
      return StreamSource(session: session, url: url, bitrate: kbps);
    }
    return null;
  }

  /// A [StreamSource] over a complete local copy of [track], or `null`.
  Future<StreamSource?> _completeSession(Track track) async {
    final local = _existingPath(track.localPath);
    if (local != null) {
      final session = StreamSession.overFile(local);
      if (session != null) {
        return StreamSource(session: session, url: '', bitrate: 320);
      }
    }
    for (final kbps in const [320, 160, 96]) {
      final path = completedPathFor(track, kbps: kbps);
      if (path == null) continue;
      final session = StreamSession.overFile(path);
      if (session != null) {
        return StreamSource(session: session, url: '', bitrate: kbps);
      }
    }
    return null;
  }

  /// Path of a complete local copy of [track] — a download or a cache entry —
  /// or `null` when the file is not whole on disk.
  ///
  /// Used by the crossfader, which needs a file it can hand to the engine
  /// *right now*, and by [openStream]'s offline branch.
  String? completedPathFor(Track track, {int? kbps}) {
    final rates = kbps != null ? [kbps] : const [320, 160, 96];
    for (final rate in rates) {
      final fileName = MediaCache.downloadFileName(songId: track.id, kbps: rate);
      final path = _cache.downloadedPathFor(fileName) ??
          _cache.streamPathFor(fileName);
      if (path != null) return path;
    }
    return null;
  }

  /// Warms the cache for the head of a list the user is looking at, so the tap
  /// that follows starts in milliseconds instead of a full download.
  ///
  /// Fire-and-forget by design: it never blocks a screen, never throws, and
  /// `MediaCache` de-duplicates anything already in flight or on disk.
  void prefetchTracks(List<Track> tracks, {int count = 3}) {
    if (tracks.isEmpty || !_network.isOnline.value) return;
    for (final track in tracks.take(count)) {
      if (_existingPath(track.localPath) != null) continue;
      unawaited(
        () async {
          try {
            await resolvePlayable(track, prefetch: true);
          } catch (e) {
            debugPrint('Prefetch skipped for ${track.id}: $e');
          }
        }(),
      );
    }
  }

  Future<PlayableSource?> _cachedOnlySource(Track track) async {
    for (final kbps in const [320, 160, 96]) {
      final fileName = MediaCache.downloadFileName(songId: track.id, kbps: kbps);
      final local = _cache.downloadedPathFor(fileName);
      if (local != null) {
        return PlayableSource(path: local, isLocalFile: true, bitrate: kbps);
      }
    }
    return null;
  }

  String? _existingPath(String? path) {
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  // ------------------------------------------------------------------- home

  Future<HomeFeed> loadHome({bool refresh = false}) async {
    if (!_network.isOnline.value) {
      return HomeFeed(isOffline: true, hasData: false, genres: await genresOnly());
    }

    final payload = await _saavn.fetchLaunch(refresh: refresh);
    final topSearches = await _saavn.fetchTopSearches();
    final featuredHits = await _fetchFeaturedHits(payload);

    return HomeFeed(
      trending: payload.trending,
      charts: payload.charts,
      playlists: payload.playlists,
      albums: payload.albums,
      genres: payload.genres,
      topSearches: topSearches,
      featuredHits: featuredHits,
      isOffline: false,
      hasData: !payload.isEmpty || topSearches.isNotEmpty || featuredHits.isNotEmpty,
    );
  }

  Future<List<Track>> _fetchFeaturedHits(LaunchPayload payload) async {
    final hits = <Track>[];
    final seen = <String>{};

    void addTrack(Track? t) {
      if (t == null || t.id.isEmpty) return;
      if (seen.add(t.dedupeKey)) {
        hits.add(t);
      }
    }

    try {
      // 1. Fetch tracks from the top trending playlists/charts
      final collectionsToExamine = <Collection>[];
      for (final item in payload.trending) {
        if (item.isCollection && item.collection != null && collectionsToExamine.length < 2) {
          collectionsToExamine.add(item.collection!);
        }
      }
      for (final item in payload.charts) {
        if (item.isCollection && item.collection != null && collectionsToExamine.length < 4) {
          collectionsToExamine.add(item.collection!);
        }
      }

      for (final col in collectionsToExamine) {
        try {
          final detail = await _saavn.playlistDetail(col, maxTracks: 15);
          if (detail != null && detail.tracks.isNotEmpty) {
            for (final track in detail.tracks) {
              addTrack(track);
            }
          }
        } catch (_) {}
        if (hits.length >= 20) break;
      }

      // 2. Query latest trending songs directly from search if still needed
      if (hits.length < 15) {
        final queryResults = await _saavn.searchSongs('trending hits', limit: 25);
        for (final track in queryResults) {
          addTrack(track);
        }
      }

      // 3. Fallback: Include topSearches
      if (hits.length < 15) {
        final top = await _saavn.fetchTopSearches();
        for (final track in top) {
          addTrack(track);
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch featured hits: $e');
    }

    return hits;
  }

  /// The eight curated genre tiles, with a hard-coded fallback so Search is
  /// never an empty grid on first launch with no network.
  Future<List<Collection>> genresOnly() async {
    final payload = await _saavn.fetchLaunch();
    if (payload.genres.isNotEmpty) {
      return _orderGenres(payload.genres);
    }
    return defaultGenres;
  }

  /// The PRD's eight tiles, in order, matched against whatever the catalogue
  /// actually returned.
  static const List<Collection> defaultGenres = [
    Collection(
      id: 'g-phonk',
      title: 'DRIFT PHONK & BASS',
      kind: CollectionKind.genre,
      subtitle: 'PHONK',
      imageUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&auto=format&fit=crop&q=80',
    ),
    Collection(
      id: 'g-bollywood',
      title: 'BOLLYWOOD & INDI-POP',
      kind: CollectionKind.genre,
      subtitle: 'BOLLYWOOD',
      imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=600&auto=format&fit=crop&q=80',
    ),
    Collection(
      id: 'g-global',
      title: 'GLOBAL TOP 50',
      kind: CollectionKind.genre,
      subtitle: 'POP',
      imageUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=600&auto=format&fit=crop&q=80',
    ),
    Collection(
      id: 'g-lofi',
      title: 'LO-FI & STUDY BEATS',
      kind: CollectionKind.genre,
      subtitle: 'LO-FI',
      imageUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=600&auto=format&fit=crop&q=80',
    ),
    Collection(
      id: 'g-hiphop',
      title: 'HIP-HOP & RAP',
      kind: CollectionKind.genre,
      subtitle: 'HIP HOP',
      imageUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=600&auto=format&fit=crop&q=80',
    ),
    Collection(
      id: 'g-electronic',
      title: 'ELECTRONIC & SYNTH',
      kind: CollectionKind.genre,
      subtitle: 'EDM',
      imageUrl: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=600&auto=format&fit=crop&q=80',
    ),
    Collection(
      id: 'g-8d',
      title: '8D SPATIAL SHOWCASE',
      kind: CollectionKind.genre,
      subtitle: 'SPATIAL AUDIO',
      imageUrl: 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=600&auto=format&fit=crop&q=80',
    ),
    Collection(
      id: 'g-workout',
      title: 'WORKOUT & HIGH BPM',
      kind: CollectionKind.genre,
      subtitle: 'WORKOUT',
      imageUrl: 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=600&auto=format&fit=crop&q=80',
    ),
  ];

  /// Curated search phrases, index-aligned with [defaultGenres].
  static const List<String> _genreQueries = [
    'phonk drift',
    'bollywood hits',
    'top 50 global',
    'lofi study beats',
    'hip hop rap hits',
    'electronic synth',
    '8d audio',
    'workout music',
  ];

  /// Reorders the catalogue's `browse_discover` channels onto the PRD tiles,
  /// falling back to the curated list when a channel is missing.
  List<Collection> _orderGenres(List<Collection> available) {
    final byTitle = {
      for (final c in available) c.title.toLowerCase().trim(): c,
    };

    return List<Collection>.generate(defaultGenres.length, (i) {
      final curated = defaultGenres[i];
      final query = _genreQueries[i].toLowerCase();

      final match = byTitle[query] ??
          available.firstWhere(
            (c) => c.title.toLowerCase().contains(query.split(' ').first),
            orElse: () => curated,
          );

      final resolvedImage = match.imageUrl.isNotEmpty
          ? match.imageUrl
          : curated.imageUrl;

      return match.copyWith(
        // Keep the PRD's display title; the catalogue entry only supplies the
        // query phrase and artwork.
        title: curated.title,
        subtitle: curated.subtitle,
        kind: CollectionKind.genre,
        id: match.id,
        permaToken: match.permaToken,
        permaUrl: match.permaUrl,
        imageUrl: resolvedImage,
      );
    });
  }

  /// "Made For You" mixes derived from what this listener actually plays.
  Future<List<Collection>> dailyMixes(List<Track> history) async {
    if (history.isEmpty) {
      final payload = await _saavn.fetchLaunch();
      return payload.playlists
          .where((r) => r.isCollection)
          .map((r) => r.collection!)
          .take(4)
          .toList();
    }

    // Rank artists by how often they appear in the recent history.
    final counts = <String, int>{};
    for (final track in history) {
      final artist = track.artist.trim();
      if (artist.isEmpty || artist.toLowerCase() == 'unknown') continue;
      counts[artist] = (counts[artist] ?? 0) + 1;
    }

    final topArtists = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final mixes = <Collection>[];
    for (final entry in topArtists.take(4)) {
      final playlists = await _saavn.searchPlaylists(entry.key, limit: 4);
      if (playlists.isEmpty) continue;
      mixes.add(
        playlists.first.copyWith(
          kind: CollectionKind.mix,
          subtitle: 'MADE FOR YOU · ${entry.key.toUpperCase()}',
        ),
      );
    }

    if (mixes.isEmpty) {
      final payload = await _saavn.fetchLaunch();
      return payload.playlists
          .where((r) => r.isCollection)
          .map((r) => r.collection!)
          .take(4)
          .toList();
    }
    return mixes;
  }

  // ----------------------------------------------------------------- search

  Future<SearchResults> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const SearchResults();

    if (!_network.isOnline.value) {
      // Offline search still works, just only over what is on the device.
      return SearchResults(query: trimmed);
    }

    final results = await Future.wait([
      _saavn.searchSongs(trimmed, limit: 30),
      _saavn.searchAlbums(trimmed, limit: 12),
      _saavn.searchArtists(trimmed, limit: 12),
      _saavn.searchPlaylists(trimmed, limit: 12),
    ]);

    return SearchResults(
      query: trimmed,
      songs: Track.dedupe(results[0] as List<Track>),
      albums: results[1] as List<Collection>,
      artists: results[2] as List<Collection>,
      playlists: results[3] as List<Collection>,
    );
  }

  Future<List<String>> suggest(String query) => _saavn.suggest(query);

  Future<List<Track>> searchSongs(String query, {int page = 1}) =>
      _saavn.searchSongs(query, page: page, limit: 40);

  /// Voice-free convenience: songs matching a mood keyword for Home's quick
  /// filters.
  Future<List<Track>> moodTracks(String keyword) async {
    final songs = await _saavn.searchSongs(keyword, limit: 30);
    return Track.dedupe(songs);
  }

  // ----------------------------------------------------------------- detail

  Future<CollectionDetail?> loadCollection(Collection collection) async {
    switch (collection.kind) {
      case CollectionKind.album:
        return _saavn.albumDetail(collection);
      case CollectionKind.artist:
        return _saavn.artistDetail(collection);
      case CollectionKind.genre:
        return _saavn.genreDetail(collection);
      case CollectionKind.playlist:
      case CollectionKind.chart:
      case CollectionKind.mix:
      case CollectionKind.system:
        return _saavn.playlistDetail(collection);
    }
  }

  Future<CollectionDetail?> loadPlainPlaylist(String id, {String? title}) async {
    return _saavn.playlistDetail(
      Collection(
        id: id,
        title: title ?? 'PLAYLIST',
        kind: CollectionKind.playlist,
      ),
    );
  }

  /// Loads a chart/playlist that is useful for the genre detail screen even
  /// when the tile is one of the curated fallbacks.
  Future<CollectionDetail?> loadGenreByQuery(String query) async {
    return _saavn.searchPlaylists(query, limit: 6).then((playlists) {
      if (playlists.isEmpty) return null;
      return _saavn.playlistDetail(playlists.first, maxTracks: 60);
    });
  }

  // ---------------------------------------------------------------- artwork

  /// A 1000 px cover for a single track, used on the Now Playing screen where
  /// the extra resolution is actually visible.
  Future<String?> enhancedArtwork(Track track) async {
    if (track.album.isEmpty && track.artist.isEmpty) return null;
    final art = await _artwork.albumArt(
      album: track.album,
      artist: track.artist,
      title: track.title,
    );
    return art?.url;
  }

  Future<String?> enhancedArtistImage(String artist) async {
    final art = await _artwork.artistPortrait(artist);
    return art?.url;
  }

  // ---------------------------------------------------------------- lyrics

  Future<Lyrics?> lyricsFor(Track track) => _lyrics.fetch(track);

  // -------------------------------------------------------------- downloads

  /// Writes a permanent offline copy and returns the updated track.
  Future<Track?> downloadTrack(
    Track track, {
    ValueChanged<double?>? onProgress,
  }) async {
    final kbps = _settings.value.downloadQuality.kbps;
    final url = await _saavn.resolveStreamUrl(track.id, preferredKbps: kbps);
    if (url == null) return null;

    final fileName = MediaCache.downloadFileName(songId: track.id, kbps: kbps);
    final path = await _cache.ensure(
      url: url,
      fileName: fileName,
      kind: CacheEntryKind.download,
      onProgress: (progress) => onProgress?.call(progress.fraction),
    );
    if (path == null) return null;

    var size = 0;
    try {
      size = await File(path).length();
    } catch (_) {}

    return track.copyWith(localPath: path, bitrate: kbps, sizeBytes: size);
  }

  Future<void> deleteDownload(Track track) async {
    final path = track.localPath;
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } catch (e) {
        debugPrint('delete download failed: $e');
      }
    }
    // Also clean any stray rendition names for this song.
    for (final kbps in const [320, 160, 96]) {
      await _cache.deleteDownload(
        MediaCache.downloadFileName(songId: track.id, kbps: kbps),
      );
    }
  }

  Future<int> downloadsSizeBytes() => _cache.measureDownloads();

  Future<int> streamCacheSizeBytes() => _cache.measureCache();

  Future<int> clearStreamCache() => _cache.clearStreamCache();

  Future<int> deleteAllDownloads() => _cache.deleteAllDownloads();

  /// Small helper the UI uses for the "PLAYING FROM" label.
  static String sourceLabelFor(DateTime now) => 'MUSIFY';

  /// A friendly, non-technical reason string for a failed resolution.
  String unavailableReason(Track track) {
    if (!_network.isOnline.value) return 'OFFLINE — NOT DOWNLOADED';
    if (!track.has320) return 'NO PLAYABLE RENDITION';
    return 'TRACK UNAVAILABLE';
  }

  /// Formats the elapsed/total pair the Now Playing screen shows.
  String progressLabel(Duration position, Duration total) =>
      '${Fmt.duration(position)} / ${Fmt.duration(total)}';
}

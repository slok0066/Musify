import 'dart:math' as math;

import '../models/collection.dart';
import '../models/track.dart';
import '../models/user_playlist.dart';
import '../sources/local_store.dart';

/// Library filters exposed by the Library screen's pill row.
enum LibraryFilter { all, playlists, liked, downloaded, albums, artists }

/// Sort orders offered by the Library screen's sort control.
enum LibrarySort { recentlyPlayed, recentlyAdded, alphabetical }

/// A single row in the Library — either a user playlist or a system
/// collection, so one list widget can render both.
class LibraryEntry {
  const LibraryEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.isSystem,
    this.imageUrl,
    this.mosaic = const [],
    this.trackCount = 0,
    this.playlist,
    this.systemKind,
    this.lastPlayedAt,
  });

  final String id;
  final String title;
  final String subtitle;

  /// System collections (Liked Songs, Downloads, Recently Cached) cannot be
  /// renamed or deleted.
  final bool isSystem;
  final String? imageUrl;
  final List<String> mosaic;
  final int trackCount;
  final UserPlaylist? playlist;
  final CollectionKind? systemKind;
  final DateTime? lastPlayedAt;
}

/// Read/write façade over the local boxes.
///
/// All reads are synchronous (Hive keeps its boxes in memory), all writes are
/// awaited so the caller knows the change is durable before it reports success.
class LibraryRepository {
  LibraryRepository(this._store);

  final LocalStore _store;

  // ------------------------------------------------------------------ reads

  List<Track> liked() => _store.readLiked();

  int _likedRevision = -1;
  Set<String> _likedIds = const {};
  Set<String> _likedDedupeKeys = const {};

  /// Whether [trackId] is in Liked Songs.
  ///
  /// The player asks this on every 250 ms tick, so the id set is cached and only
  /// rebuilt when the store reports a change — decoding every liked track's map
  /// four times a second is a stutter waiting to happen.
  bool isLiked(String trackId, [String? dedupeKey]) {
    final revision = _store.revision.value;
    if (revision != _likedRevision) {
      _likedRevision = revision;
      final tracks = _store.readLiked();
      _likedIds = {for (final track in tracks) track.id};
      _likedDedupeKeys = {
        for (final track in tracks)
          if (track.dedupeKey.isNotEmpty) track.dedupeKey
      };
    }
    if (_likedIds.contains(trackId)) return true;
    if (dedupeKey != null && dedupeKey.isNotEmpty) {
      return _likedDedupeKeys.contains(dedupeKey);
    }
    return false;
  }

  List<UserPlaylist> playlists() => _store.readPlaylists();

  UserPlaylist? playlistById(String id) {
    for (final p in _store.readPlaylists()) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<Track> downloads() => _store.readDownloads();

  bool isDownloaded(String trackId) =>
      _store.readDownloads().any((t) => t.id == trackId);

  List<Track> history() => _store.readHistory();

  List<String> recentSearches() => _store.readSearches();

  List<Collection> recentCollections() {
    final raw = _store.readRecentCollections();
    final out = <Collection>[];
    for (final map in raw) {
      final id = map['id']?.toString() ?? '';
      final title = map['title']?.toString() ?? '';
      if (id.isEmpty || title.isEmpty) continue;
      out.add(
        Collection(
          id: id,
          title: title,
          kind: CollectionKind.system,
          subtitle: map['subtitle']?.toString() ?? '',
          imageUrl: map['imageUrl']?.toString() ?? '',
          songCount: map['songCount'] is num
              ? (map['songCount'] as num).toInt()
              : null,
          permaUrl: map['permaUrl']?.toString(),
        ),
      );
    }
    return out;
  }

  /// Albums and artists are *derived* from likes, downloads and history —
  /// the user never has to file them manually.
  List<Collection> albums({bool downloadedOnly = false}) {
    final source = downloadedOnly
        ? downloads()
        : [...liked(), ...downloads(), ...history()];

    final seen = <String, Collection>{};
    for (final track in source) {
      if (track.album.isEmpty) continue;
      final key = '${track.album.toLowerCase()}|${track.artist.toLowerCase()}';
      final existing = seen[key];
      if (existing != null) {
        seen[key] = existing.copyWith(songCount: (existing.songCount ?? 0) + 1);
        continue;
      }
      seen[key] = Collection(
        id: track.albumId ?? key,
        title: track.album,
        kind: CollectionKind.album,
        subtitle: track.artist,
        imageUrl: track.imageUrl,
        songCount: 1,
        year: track.year,
      );
    }
    return seen.values.toList();
  }

  List<Collection> artists({bool downloadedOnly = false}) {
    final source = downloadedOnly
        ? downloads()
        : [...liked(), ...downloads(), ...history()];

    final seen = <String, Collection>{};
    for (final track in source) {
      final name = track.artist.trim();
      if (name.isEmpty || name.toLowerCase() == 'unknown') continue;
      final key = name.toLowerCase();
      final existing = seen[key];
      if (existing != null) {
        seen[key] = existing.copyWith(songCount: (existing.songCount ?? 0) + 1);
        continue;
      }
      seen[key] = Collection(
        id: track.artistId ?? key,
        title: name,
        kind: CollectionKind.artist,
        subtitle: track.album,
        imageUrl: track.imageUrl,
        songCount: 1,
        artistId: track.artistId,
      );
    }
    return seen.values.toList();
  }

  /// The rolling stream cache as a browsable list — "Recently Cached".
  List<Track> recentlyCached() {
    final played = history();
    final downloaded = downloads().map((t) => t.id).toSet();
    return played.where((t) => !downloaded.contains(t.id)).toList();
  }

  /// Rows for the Library, already filtered and sorted.
  List<LibraryEntry> entries({
    required LibraryFilter filter,
    required LibrarySort sort,
    String query = '',
  }) {
    final entries = <LibraryEntry>[];

    if (filter == LibraryFilter.all ||
        filter == LibraryFilter.liked ||
        filter == LibraryFilter.playlists) {
      final likedTracks = liked();
      final ownPlaylists = playlists();

      entries.add(
        LibraryEntry(
          id: '__liked__',
          title: 'LIKED SONGS',
          subtitle: '${likedTracks.length} TRACKS',
          isSystem: true,
          systemKind: CollectionKind.system,
          mosaic: likedTracks.take(4).map((t) => t.imageUrl).where((u) => u.isNotEmpty).toList(),
          imageUrl: likedTracks.isNotEmpty ? likedTracks.first.imageUrl : null,
          trackCount: likedTracks.length,
        ),
      );

      if (filter != LibraryFilter.liked) {
        for (final playlist in ownPlaylists) {
          entries.add(
            LibraryEntry(
              id: playlist.id,
              title: playlist.name.toUpperCase(),
              subtitle: '${playlist.length} TRACKS · PLAYLIST',
              isSystem: false,
              playlist: playlist,
              mosaic: playlist.mosaicArtwork,
              imageUrl: null,
              trackCount: playlist.length,
            ),
          );
        }
      }
    }

    if (filter == LibraryFilter.all || filter == LibraryFilter.downloaded) {
      final dl = downloads();
      entries.add(
        LibraryEntry(
          id: '__downloads__',
          title: 'OFFLINE VAULT',
          subtitle: '${dl.length} TRACKS · 100% OFFLINE',
          isSystem: true,
          systemKind: CollectionKind.system,
          mosaic: dl.take(4).map((t) => t.imageUrl).where((u) => u.isNotEmpty).toList(),
          imageUrl: dl.isNotEmpty ? dl.first.imageUrl : null,
          trackCount: dl.length,
        ),
      );
    }

    if (filter == LibraryFilter.albums) {
      for (final album in albums()) {
        entries.add(
          LibraryEntry(
            id: album.id,
            title: album.title.toUpperCase(),
            subtitle: '${album.subtitle} · ALBUM',
            isSystem: false,
            imageUrl: album.imageUrl,
            trackCount: album.songCount ?? 0,
            systemKind: CollectionKind.album,
          ),
        );
      }
    }

    if (filter == LibraryFilter.artists) {
      for (final artist in artists()) {
        entries.add(
          LibraryEntry(
            id: artist.id,
            title: artist.title.toUpperCase(),
            subtitle: 'ARTIST',
            isSystem: false,
            imageUrl: artist.imageUrl,
            trackCount: artist.songCount ?? 0,
            systemKind: CollectionKind.artist,
          ),
        );
      }
    }

    var result = entries;
    if (query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      result = result.where((e) => e.title.toLowerCase().contains(q)).toList();
    }

    switch (sort) {
      case LibrarySort.alphabetical:
        result.sort((a, b) => a.title.compareTo(b.title));
      case LibrarySort.recentlyAdded:
        // System collections stay pinned to the top, matching Spotify's model.
        result.sort((a, b) {
          if (a.isSystem != b.isSystem) return a.isSystem ? -1 : 1;
          return 0;
        });
      case LibrarySort.recentlyPlayed:
        result.sort((a, b) {
          if (a.isSystem != b.isSystem) return a.isSystem ? -1 : 1;
          return (b.trackCount).compareTo(a.trackCount);
        });
    }

    return result;
  }

  // ----------------------------------------------------------------- writes

  Future<bool> toggleLike(Track track) async {
    final current = [..._store.readLiked()];
    final index = current.indexWhere((t) =>
        t.id == track.id ||
        (t.dedupeKey == track.dedupeKey && track.dedupeKey.isNotEmpty));
    if (index >= 0) {
      current.removeAt(index);
      await _store.writeLiked(current);
      return false;
    }
    current.insert(0, track.copyWith(addedAt: DateTime.now()));
    await _store.writeLiked(current);
    return true;
  }

  Future<void> like(Track track) async {
    if (isLiked(track.id, track.dedupeKey)) return;
    final current = [..._store.readLiked()];
    current.insert(0, track.copyWith(addedAt: DateTime.now()));
    await _store.writeLiked(current);
  }

  Future<void> unlike(String trackId) async {
    final current = [..._store.readLiked()]..removeWhere((t) => t.id == trackId);
    await _store.writeLiked(current);
  }

  /// Replaces a stored track everywhere it appears — used after a download
  /// completes so `localPath` is not lost by the next write.
  Future<void> upsertEverywhere(Track track) async {
    Future<void> patch(List<Track> list, Future<void> Function(List<Track>) write) async {
      final index = list.indexWhere((t) => t.id == track.id);
      if (index < 0) return;
      final merged = track.copyWith(
        addedAt: list[index].addedAt,
        lastPlayedAt: list[index].lastPlayedAt,
      );
      list[index] = merged;
      await write(list);
    }

    await patch(_store.readLiked(), _store.writeLiked);
    await patch(_store.readHistory(), _store.writeHistory);

    final playlists = _store.readPlaylists();
    var touched = false;
    for (var i = 0; i < playlists.length; i++) {
      final p = playlists[i];
      final index = p.tracks.indexWhere((t) => t.id == track.id);
      if (index < 0) continue;
      final tracks = [...p.tracks];
      tracks[index] = track.copyWith(addedAt: p.tracks[index].addedAt);
      playlists[i] = p.copyWith(tracks: tracks, updatedAt: DateTime.now());
      touched = true;
    }
    if (touched) await _store.writePlaylists(playlists);
  }

  Future<void> recordDownload(Track track) async {
    final current = _store.readDownloads();
    final index = current.indexWhere((t) => t.id == track.id);
    if (index >= 0) {
      current[index] = track;
    } else {
      current.insert(0, track);
    }
    await _store.writeDownloads(current);
    await upsertEverywhere(track);
  }

  Future<void> removeDownloadRecord(String trackId) async {
    final current = _store.readDownloads()..removeWhere((t) => t.id == trackId);
    await _store.writeDownloads(current);
  }

  Future<void> removeAllDownloadRecords() async {
    await _store.writeDownloads(const []);
  }

  Future<void> recordPlay(Track track) async {
    await _store.pushHistory(track);
  }

  Future<void> recordSearch(String query) => _store.pushSearch(query);

  Future<void> removeSearch(String query) => _store.removeSearch(query);

  Future<void> clearSearches() => _store.clearSearches();

  Future<void> recordCollection(Collection collection) async {
    await _store.pushRecentCollection({
      'id': collection.id,
      'title': collection.title,
      'subtitle': collection.subtitle,
      'imageUrl': collection.imageUrl,
      'songCount': collection.songCount,
      'permaUrl': collection.permaUrl,
    });
  }

  // ---------------------------------------------------------------- playlists

  Future<UserPlaylist> createPlaylist({
    required String name,
    String description = '',
  }) async {
    final now = DateTime.now();
    final playlist = UserPlaylist(
      id: _newId(),
      name: name.trim().isEmpty ? 'Untitled Playlist' : name.trim(),
      description: description.trim(),
      createdAt: now,
      updatedAt: now,
    );
    final current = [..._store.readPlaylists()];
    current.insert(0, playlist);
    await _store.writePlaylists(current);
    return playlist;
  }

  Future<void> renamePlaylist(
    String playlistId, {
    String? name,
    String? description,
  }) async {
    final current = [..._store.readPlaylists()];
    final index = current.indexWhere((p) => p.id == playlistId);
    if (index < 0) return;
    current[index] = current[index].copyWith(
      name: name?.trim().isEmpty == true ? current[index].name : name,
      description: description ?? current[index].description,
      updatedAt: DateTime.now(),
    );
    await _store.writePlaylists(current);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final current = [..._store.readPlaylists()]..removeWhere((p) => p.id == playlistId);
    await _store.writePlaylists(current);
  }

  Future<void> addToPlaylist(String playlistId, Track track) async {
    final current = [..._store.readPlaylists()];
    final index = current.indexWhere((p) => p.id == playlistId);
    if (index < 0) return;
    final playlist = current[index];
    if (playlist.tracks.any((t) => t.id == track.id)) return;
    current[index] = playlist.copyWith(
      tracks: [...playlist.tracks, track.copyWith(addedAt: DateTime.now())],
      updatedAt: DateTime.now(),
    );
    await _store.writePlaylists(current);
  }

  Future<void> addAllToPlaylist(String playlistId, List<Track> tracks) async {
    final current = [..._store.readPlaylists()];
    final index = current.indexWhere((p) => p.id == playlistId);
    if (index < 0) return;
    final playlist = current[index];
    final existing = playlist.tracks.map((t) => t.id).toSet();
    final additions = tracks.where((t) => !existing.contains(t.id)).toList();
    if (additions.isEmpty) return;
    current[index] = playlist.copyWith(
      tracks: [...playlist.tracks, ...additions],
      updatedAt: DateTime.now(),
    );
    await _store.writePlaylists(current);
  }

  Future<void> removeFromPlaylist(String playlistId, String trackId) async {
    final current = [..._store.readPlaylists()];
    final index = current.indexWhere((p) => p.id == playlistId);
    if (index < 0) return;
    final playlist = current[index];
    current[index] = playlist.copyWith(
      tracks: playlist.tracks.where((t) => t.id != trackId).toList(),
      updatedAt: DateTime.now(),
    );
    await _store.writePlaylists(current);
  }

  Future<void> reorderPlaylist(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final current = [..._store.readPlaylists()];
    final index = current.indexWhere((p) => p.id == playlistId);
    if (index < 0) return;
    final playlist = current[index];
    final tracks = [...playlist.tracks];
    if (oldIndex < 0 || oldIndex >= tracks.length) return;
    var target = newIndex;
    if (target < 0) target = 0;
    if (target >= tracks.length) target = tracks.length - 1;
    final moved = tracks.removeAt(oldIndex);
    tracks.insert(target, moved);
    current[index] = playlist.copyWith(tracks: tracks, updatedAt: DateTime.now());
    await _store.writePlaylists(current);
  }

  /// Batch import used by the URL importer.
  Future<UserPlaylist> createPlaylistWith(
    String name,
    List<Track> tracks, {
    String description = '',
  }) async {
    final now = DateTime.now();
    final playlist = UserPlaylist(
      id: _newId(),
      name: name,
      description: description,
      tracks: Track.dedupe(tracks),
      createdAt: now,
      updatedAt: now,
    );
    final current = _store.readPlaylists();
    current.insert(0, playlist);
    await _store.writePlaylists(current);
    return playlist;
  }

  static String _newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = math.Random().nextInt(1 << 20).toRadixString(36);
    return 'pl-$stamp-$salt';
  }

  Map<String, dynamic> exportPayload() => _store.exportAll();

  Future<void> wipe() => _store.wipeLibrary();
}

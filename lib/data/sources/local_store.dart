import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/track.dart';
import '../models/user_playlist.dart';

/// Local persistence for the Library.
///
/// Everything the user owns — liked songs, playlists, downloads, listening
/// history and recent searches — lives in flat Hive boxes holding plain maps
/// and primitives. No adapters, no code generation, no migrations to run: the
/// boxes are forward/backward compatible by construction, and a corrupt entry
/// is skipped rather than crashing the Library.
class LocalStore {
  static const String likedBox = 'musify.liked';
  static const String playlistsBox = 'musify.playlists';
  static const String downloadsBox = 'musify.downloads';
  static const String historyBox = 'musify.history';
  static const String searchesBox = 'musify.searches';
  static const String collectionsBox = 'musify.collections';

  static const int _maxHistory = 20;
  static const int _maxSearches = 15;

  Box<dynamic>? _liked;
  Box<dynamic>? _playlists;
  Box<dynamic>? _downloads;
  Box<dynamic>? _history;
  Box<dynamic>? _searches;
  Box<dynamic>? _collections;

  /// Set when a box could not be opened or a write failed. The session keeps
  /// working — every value also lives in memory — but nothing written after
  /// this point survives a restart, and the UI can say so instead of pretending
  /// the change stuck.
  bool get storageWarning => _storageWarning;
  bool _storageWarning = false;

  /// `'<box>/<key>' → value` for the boxes that are not available on disk.
  final Map<String, Object?> _memory = {};

  /// Bumped on every mutation. Cubits listen to this instead of polling, so a
  /// like made on the lock screen repaints the Library and the Now Playing
  /// heart in the same frame.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void _bump() => revision.value++;

  bool get isReady =>
      _liked != null &&
      _playlists != null &&
      _downloads != null &&
      _history != null &&
      _searches != null &&
      _collections != null;

  /// Opens every box. Called once from a guarded, time-boxed startup step, so
  /// a slow or locked disk degrades to an empty Library instead of a hang.
  ///
  /// A box that refuses to open — a crash mid-write, a file the current schema
  /// rejects — is reset once before it is written off, because "the whole
  /// Library silently stopped saving" is a far worse failure than losing a box
  /// that could not be read anyway.
  Future<void> init() async {
    try {
      await Hive.initFlutter('musify');
    } catch (e) {
      // No path from the platform: the boxes below will fail too, and every
      // read/write then goes through this session's memory instead.
      _noteStorageFailure('Hive.initFlutter', e);
    }
    _liked = await _openBox(likedBox);
    _playlists = await _openBox(playlistsBox);
    _downloads = await _openBox(downloadsBox);
    _history = await _openBox(historyBox);
    _searches = await _openBox(searchesBox);
    _collections = await _openBox(collectionsBox);
  }

  Future<Box<dynamic>?> _openBox(String name) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await Hive.openBox<dynamic>(name);
      } catch (e) {
        _noteStorageFailure('open box "$name"', e);
        if (attempt == 0) {
          try {
            await Hive.deleteBoxFromDisk(name);
          } catch (inner) {
            debugPrint('LocalStore could not reset box "$name": $inner');
          }
        }
      }
    }
    return null;
  }

  /// Reads a box key, falling back to this session's in-memory copy.
  ///
  /// A missing box must never look like an empty library: silently reading `[]`
  /// is exactly what makes a tapped heart look like it "does nothing".
  Object? _readBox(String box, Box<dynamic>? handle, String key) {
    if (handle != null) {
      try {
        return handle.get(key);
      } catch (e) {
        _noteStorageFailure('read $box/$key', e);
      }
    }
    return _memory['$box/$key'];
  }

  Future<void> _writeBox(
    String box,
    Box<dynamic>? handle,
    String key,
    Object? value,
  ) async {
    // Memory first: the UI reads back through [_readBox] in the same frame.
    _memory['$box/$key'] = value;
    if (handle == null) {
      _noteStorageFailure('open $box', 'box unavailable');
      return;
    }
    try {
      await handle.put(key, value);
    } catch (e) {
      _noteStorageFailure('write $box/$key', e);
    }
  }

  void _noteStorageFailure(String what, Object error) {
    _storageWarning = true;
    debugPrint('LocalStore $what failed: $error');
  }

  /// One line for the fault report: enough to tell a storage failure from a UI
  /// one without a debugger.
  String diagnostics() {
    final open = <String>[
      if (_liked != null) 'liked',
      if (_playlists != null) 'playlists',
      if (_downloads != null) 'downloads',
      if (_history != null) 'history',
      if (_searches != null) 'searches',
      if (_collections != null) 'collections',
    ].join(',');
    return 'STORAGE: ${_storageWarning ? 'DEGRADED' : 'OK'} '
        '(ready=${isReady ? 'yes' : 'no'}, boxes=[$open], '
        'liked=${readLiked().length}, downloads=${readDownloads().length})';
  }

  // -------------------------------------------------------------------- liked

  List<Track> readLiked() => Track.listFrom(_readBox(likedBox, _liked, 'items'));

  Future<void> writeLiked(List<Track> tracks) async {
    await _writeBox(likedBox, _liked, 'items', Track.listTo(tracks));
    _bump();
  }

  // ---------------------------------------------------------------- playlists

  List<UserPlaylist> readPlaylists() {
    final raw = _readBox(playlistsBox, _playlists, 'items');
    if (raw is! List) return <UserPlaylist>[];
    final out = <UserPlaylist>[];
    for (final entry in raw) {
      final playlist = UserPlaylist.fromMap(entry);
      if (playlist != null) out.add(playlist);
    }
    return out;
  }

  Future<void> writePlaylists(List<UserPlaylist> playlists) async {
    await _writeBox(
      playlistsBox,
      _playlists,
      'items',
      playlists.map((p) => p.toMap()).toList(),
    );
    _bump();
  }

  // ---------------------------------------------------------------- downloads

  List<Track> readDownloads() =>
      Track.listFrom(_readBox(downloadsBox, _downloads, 'items'))
          .where((t) => t.isDownloaded)
          .toList();

  Future<void> writeDownloads(List<Track> tracks) async {
    await _writeBox(downloadsBox, _downloads, 'items', Track.listTo(tracks));
    _bump();
  }

  // ------------------------------------------------------------------ history

  /// Most-recent-first listening history.
  List<Track> readHistory() =>
      Track.listFrom(_readBox(historyBox, _history, 'items'));

  Future<void> pushHistory(Track track) async {
    final current = readHistory();
    // A track is identified by catalogue id, and re-playing must *move* the
    // entry to the top rather than duplicate it.
    final next = <Track>[
      track.copyWith(lastPlayedAt: DateTime.now()),
      ...current.where((t) => t.id != track.id),
    ].take(_maxHistory).toList();
    await _writeBox(historyBox, _history, 'items', Track.listTo(next));
    _bump();
  }

  Future<void> writeHistory(List<Track> tracks) async {
    await _writeBox(historyBox, _history, 'items', Track.listTo(tracks));
    _bump();
  }

  // ----------------------------------------------------------------- searches

  List<String> readSearches() {
    final raw = _readBox(searchesBox, _searches, 'items');
    if (raw is! List) return <String>[];
    return raw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
  }

  Future<void> pushSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final current = readSearches();
    final next = <String>[q, ...current.where((s) => s.toLowerCase() != q.toLowerCase())]
        .take(_maxSearches)
        .toList();
    await _writeBox(searchesBox, _searches, 'items', next);
  }

  Future<void> removeSearch(String query) async {
    final next = readSearches().where((s) => s != query).toList();
    await _writeBox(searchesBox, _searches, 'items', next);
  }

  Future<void> clearSearches() async {
    await _writeBox(searchesBox, _searches, 'items', <String>[]);
  }

  // ------------------------------------------------- lately played collections

  /// The four most recent albums/playlists, used by the Home quick grid.
  List<Map<String, dynamic>> readRecentCollections() {
    final raw = _readBox(collectionsBox, _collections, 'items');
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<void> pushRecentCollection(Map<String, dynamic> collection) async {
    final id = collection['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final current = readRecentCollections();
    final next = <Map<String, dynamic>>[
      collection,
      ...current.where((c) => c['id']?.toString() != id),
    ].take(8).toList();
    await _writeBox(collectionsBox, _collections, 'items', next);
  }

  // ------------------------------------------------------------------- backup

  Map<String, dynamic> exportAll() => {
    'version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'liked': Track.listTo(readLiked()),
    'playlists': readPlaylists().map((p) => p.toMap()).toList(),
    'downloads': Track.listTo(readDownloads()),
    'history': Track.listTo(readHistory()),
    'searches': readSearches(),
    'recentCollections': readRecentCollections(),
  };

  /// Restores an exported backup. Unknown keys and malformed rows are ignored,
  /// so a partial or hand-edited file still imports what it can.
  Future<void> importAll(Map<String, dynamic> payload) async {
    final liked = Track.listFrom(payload['liked']);
    if (liked.isNotEmpty) await writeLiked(liked);

    final rawPlaylists = payload['playlists'];
    if (rawPlaylists is List) {
      final playlists = <UserPlaylist>[];
      for (final entry in rawPlaylists) {
        final p = UserPlaylist.fromMap(entry);
        if (p != null) playlists.add(p);
      }
      if (playlists.isNotEmpty) await writePlaylists(playlists);
    }

    final history = Track.listFrom(payload['history']);
    if (history.isNotEmpty) await writeHistory(history);

    final rawSearches = payload['searches'];
    if (rawSearches is List) {
      final searches = rawSearches
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .take(_maxSearches)
          .toList();
      await _writeBox(searchesBox, _searches, 'items', searches);
    }
  }

  Future<void> wipeLibrary() async {
    _memory.clear();
    for (final handle in [
      _liked,
      _playlists,
      _downloads,
      _history,
      _searches,
      _collections,
    ]) {
      try {
        await handle?.clear();
      } catch (e) {
        _noteStorageFailure('clear box', e);
      }
    }
  }
}

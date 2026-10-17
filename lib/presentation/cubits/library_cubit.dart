import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/playlist_importer.dart';
import '../../data/models/collection.dart';
import '../../data/models/track.dart';
import '../../data/models/user_playlist.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/music_repository.dart';
import '../../data/sources/local_store.dart';
import '../../services/backup_service.dart';

/// Compact Swiss list or 2-column artwork grid.
enum LibraryLayout { list, grid }

/// A scanned playlist waiting for a destination (see `scanPlaylist`).
///
/// The import used to file itself the moment matching finished; holding the
/// result here is what lets the sheet offer "new playlist" *or* "add to an
/// existing one" instead of silently guessing.
class PendingImport extends Equatable {
  const PendingImport({
    required this.name,
    required this.provider,
    required this.tracks,
    required this.scanned,
  });

  /// Playlist title read off the source page, used as the suggested name.
  final String name;

  /// `YOUTUBE`, `SPOTIFY` or `SOURCE`.
  final String provider;

  /// Entries that matched the 320 kbps JioSaavn catalogue, de-duplicated.
  final List<Track> tracks;

  /// Entries the source page listed, matched or not.
  final int scanned;

  int get unmatched => (scanned - tracks.length).clamp(0, scanned);

  String get summary => '$scanned SCANNED // ${tracks.length} MATCHED'
      '${unmatched > 0 ? ' // $unmatched SKIPPED' : ''}';

  @override
  List<Object?> get props => [name, provider, scanned, tracks.length];
}

class LibraryState extends Equatable {
  const LibraryState({
    this.filter = LibraryFilter.all,
    this.sort = LibrarySort.recentlyPlayed,
    this.layout = LibraryLayout.list,
    this.entries = const [],
    this.liked = const [],
    this.downloads = const [],
    this.cached = const [],
    this.playlists = const [],
    this.albums = const [],
    this.artists = const [],
    this.query = '',
    this.inFlight = const {},
    this.importProgress,
    this.pendingImport,
    this.toast,
  });

  final LibraryFilter filter;
  final LibrarySort sort;
  final LibraryLayout layout;
  final List<LibraryEntry> entries;
  final List<Track> liked;
  final List<Track> downloads;
  final List<Track> cached;
  final List<UserPlaylist> playlists;
  final List<Collection> albums;
  final List<Collection> artists;
  final String query;

  /// trackId → download progress (0.0–1.0, `null` while unknown).
  final Map<String, double?> inFlight;
  final ImportProgress? importProgress;
  final PendingImport? pendingImport;

  /// Transient one-shot message the screen shows in a snackbar.
  final String? toast;

  bool get isEmpty => entries.isEmpty;

  bool get importing => importProgress != null &&
      importProgress!.phase != ImportPhase.done &&
      importProgress!.phase != ImportPhase.failed;

  LibraryState copyWith({
    LibraryFilter? filter,
    LibrarySort? sort,
    LibraryLayout? layout,
    List<LibraryEntry>? entries,
    List<Track>? liked,
    List<Track>? downloads,
    List<Track>? cached,
    List<UserPlaylist>? playlists,
    List<Collection>? albums,
    List<Collection>? artists,
    String? query,
    Map<String, double?>? inFlight,
    ImportProgress? importProgress,
    bool clearImport = false,
    PendingImport? pendingImport,
    bool clearPendingImport = false,
    String? toast,
    bool clearToast = false,
  }) {
    return LibraryState(
      filter: filter ?? this.filter,
      sort: sort ?? this.sort,
      layout: layout ?? this.layout,
      entries: entries ?? this.entries,
      liked: liked ?? this.liked,
      downloads: downloads ?? this.downloads,
      cached: cached ?? this.cached,
      playlists: playlists ?? this.playlists,
      albums: albums ?? this.albums,
      artists: artists ?? this.artists,
      query: query ?? this.query,
      inFlight: inFlight ?? this.inFlight,
      importProgress: clearImport ? null : (importProgress ?? this.importProgress),
      pendingImport:
          clearPendingImport ? null : (pendingImport ?? this.pendingImport),
      toast: clearToast ? null : (toast ?? this.toast),
    );
  }

  @override
  List<Object?> get props => [
    filter,
    sort,
    layout,
    entries,
    liked,
    downloads,
    cached,
    playlists,
    albums,
    artists,
    query,
    inFlight,
    importProgress,
    pendingImport,
    toast,
  ];
}

/// Owns the Library: liked songs, custom playlists, the offline vault and the
/// external playlist importer.
///
/// Every read is synchronous (Hive keeps its boxes in memory), so the Library
/// paints in the first frame and never shows a spinner — even offline.
class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit({
    required LibraryRepository library,
    required MusicRepository music,
    required LocalStore store,
    required BackupService backup,
    PlaylistImporter? importer,
  })  : _library = library,
        _music = music,
        _store = store,
        _backup = backup,
        _importer = importer,
        super(const LibraryState()) {
    _store.revision.addListener(_reload);
    _reload();
  }

  final LibraryRepository _library;
  final MusicRepository _music;
  final LocalStore _store;
  final BackupService _backup;
  final PlaylistImporter? _importer;

  final Map<String, double?> _inFlight = {};

  /// One storage warning per session is a diagnostic; two is nagging.
  bool _warnedAboutStorage = false;

  // ------------------------------------------------------------------ reads

  void _reload() {
    if (isClosed) return;
    emit(
      state.copyWith(
        entries: _library.entries(filter: state.filter, sort: state.sort, query: state.query),
        liked: _library.liked(),
        downloads: _library.downloads(),
        cached: _library.recentlyCached(),
        playlists: _library.playlists(),
        albums: _library.albums(),
        artists: _library.artists(),
        inFlight: Map<String, double?>.unmodifiable(_inFlight),
      ),
    );
  }

  void setFilter(LibraryFilter filter) {
    if (filter == state.filter) return;
    emit(state.copyWith(filter: filter, entries: _library.entries(filter: filter, sort: state.sort, query: state.query)));
  }

  void setSort(LibrarySort sort) {
    if (sort == state.sort) return;
    emit(state.copyWith(sort: sort, entries: _library.entries(filter: state.filter, sort: sort, query: state.query)));
  }

  void toggleLayout() {
    emit(
      state.copyWith(
        layout: state.layout == LibraryLayout.list ? LibraryLayout.grid : LibraryLayout.list,
      ),
    );
  }

  void setQuery(String query) {
    emit(
      state.copyWith(
        query: query,
        entries: _library.entries(filter: state.filter, sort: state.sort, query: query),
      ),
    );
  }

  UserPlaylist? playlistById(String id) => _library.playlistById(id);

  // --------------------------------------------------------------- playlists

  Future<UserPlaylist?> createPlaylist({required String name, String description = ''}) async {
    if (name.trim().isEmpty) {
      _toast('PLAYLIST NEEDS A NAME');
      return null;
    }
    final playlist = await _library.createPlaylist(name: name, description: description);
    _reload();
    _toast('CREATED // ${playlist.name.toUpperCase()}');
    return playlist;
  }

  Future<void> renamePlaylist(String id, {String? name, String? description}) async {
    await _library.renamePlaylist(id, name: name, description: description);
    _reload();
    _toast('PLAYLIST UPDATED');
  }

  Future<void> deletePlaylist(String id) async {
    await _library.deletePlaylist(id);
    _reload();
    _toast('PLAYLIST DELETED');
  }

  Future<void> addToPlaylist(String playlistId, Track track) async {
    await _library.addToPlaylist(playlistId, track);
    _reload();
    _toast('ADDED TO PLAYLIST');
  }

  Future<void> addAllToPlaylist(String playlistId, List<Track> tracks) async {
    await _library.addAllToPlaylist(playlistId, tracks);
    _reload();
    _toast('${tracks.length} TRACKS ADDED');
  }

  Future<void> removeFromPlaylist(String playlistId, String trackId) async {
    await _library.removeFromPlaylist(playlistId, trackId);
    _reload();
  }

  Future<void> reorderPlaylist(String playlistId, int oldIndex, int newIndex) async {
    await _library.reorderPlaylist(playlistId, oldIndex, newIndex);
    _reload();
  }

  // -------------------------------------------------------------- liked songs

  /// Flips the heart and **verifies the write by reading the store back**.
  ///
  /// The confirmation used to be optimistic: it announced success as long as
  /// no exception was thrown, so a like that never stuck still said "ADDED TO
  /// LIKED SONGS" and the heart stayed empty. Re-reading makes the message
  /// describe what the Library will actually show.
  Future<bool> toggleLike(Track track) async {
    final bool liked;
    try {
      liked = await _library.toggleLike(track);
    } catch (e) {
      debugPrint('toggleLike failed for ${track.id}: $e');
      _toast('COULD NOT UPDATE LIKED SONGS');
      _reload();
      return false;
    }

    final stored = _library.isLiked(track.id, track.dedupeKey);
    final warning = _store.storageWarning && !_warnedAboutStorage;
    if (warning) _warnedAboutStorage = true;

    if (stored != liked) {
      // Wrote, read back something else: storage is the problem, not the tap.
      _toast(_store.storageWarning
          ? 'ONLY FOR THIS SESSION // LOCAL STORAGE UNAVAILABLE'
          : 'COULD NOT SAVE THAT LIKE — SEE COPY REPORT');
      _reload();
      return stored;
    }

    _reload();

    final count = _library.liked().length;
    final base = liked
        ? 'LIKED // $count ${count == 1 ? 'TRACK' : 'TRACKS'}'
        : 'REMOVED FROM LIKED SONGS // $count LEFT';
    // A like that will not survive the next launch has to say so in the same
    // breath as the confirmation, not in a second snackbar the user never sees.
    _toast(warning ? '$base // NOT SAVED: STORAGE UNAVAILABLE' : base);
    return liked;
  }

  Future<void> like(Track track) async {
    await _library.like(track);
    _reload();
    _toast('ADDED TO LIKED SONGS');
  }

  Future<void> unlike(String trackId) async {
    await _library.unlike(trackId);
    _reload();
  }

  // ---------------------------------------------------------------- downloads

  Future<bool> download(Track track) async {
    if (_inFlight.containsKey(track.id)) return false;
    _inFlight[track.id] = null;
    _reload();
    _toast('DOWNLOADING // ${track.title.toUpperCase()}');

    try {
      final updated = await _music.downloadTrack(
        track,
        onProgress: (fraction) {
          if (isClosed) return;
          _inFlight[track.id] = fraction;
          _reload();
        },
      );
      if (updated == null) {
        _toast('DOWNLOAD FAILED');
        return false;
      }
      await _library.recordDownload(updated);
      _toast('SAVED OFFLINE // 320 KBPS');
      return true;
    } catch (e) {
      debugPrint('Download failed for ${track.id}: $e');
      _toast('DOWNLOAD FAILED');
      return false;
    } finally {
      _inFlight.remove(track.id);
      _reload();
    }
  }

  Future<void> downloadAll(List<Track> tracks) async {
    var done = 0;
    for (final track in tracks) {
      if (_library.isDownloaded(track.id)) continue;
      final ok = await download(track);
      if (ok) done++;
    }
    _toast(done == 0 ? 'NOTHING NEW TO DOWNLOAD' : '$done TRACKS SAVED OFFLINE');
  }

  Future<void> deleteDownload(Track track) async {
    await _music.deleteDownload(track);
    await _library.removeDownloadRecord(track.id);
    _toast('DOWNLOAD REMOVED');
  }

  Future<void> deleteAllDownloads() async {
    final freed = await _music.deleteAllDownloads();
    await _library.removeAllDownloadRecords();
    _toast('FREED ${_mb(freed)}');
  }

  bool isDownloading(String trackId) => _inFlight.containsKey(trackId);

  // ------------------------------------------------------------------ import

  /// Reads a public YouTube / Spotify playlist URL and matches every entry
  /// against JioSaavn, creating a local playlist out of the hits.
  /// Reads the playlist page and re-matches every entry, then **stops**: the
  /// result is parked in [LibraryState.pendingImport] and the sheet asks the
  /// user where it should go. Importing used to save silently, so a scan that
  /// finished was indistinguishable from one that never filed anything.
  Future<void> scanPlaylist(String url) async {
    final importer = _importer;
    if (importer == null) {
      _toast('IMPORTER UNAVAILABLE');
      return;
    }

    if (state.importing) return;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    emit(state.copyWith(importProgress: const ImportProgress.reading()));
    try {
      final source = await importer.read(trimmed, (progress) {
        if (!isClosed) emit(state.copyWith(importProgress: progress));
      });

      if (source == null || source.entries.isEmpty) {
        emit(state.copyWith(clearImport: true));
        _toast('COULD NOT READ THAT PLAYLIST — CHECK THE LINK');
        return;
      }

      final matched = await importer.match(source.entries, (progress) {
        if (!isClosed) emit(state.copyWith(importProgress: progress));
      });
      if (isClosed) return;

      if (matched.isEmpty) {
        emit(state.copyWith(clearImport: true));
        _toast('NO MATCHES ON JIOSAAVN FOR THAT PLAYLIST');
        return;
      }

      final provider = source.provider;
      emit(
        state.copyWith(
          clearImport: true,
          pendingImport: PendingImport(
            name: source.name,
            provider: provider,
            tracks: matched,
            scanned: source.entries.length,
          ),
        ),
      );
      _toast('SCAN COMPLETE // PICK A DESTINATION');
    } catch (e) {
      debugPrint('Import failed: $e');
      if (isClosed) return;
      emit(state.copyWith(clearImport: true));
      _toast('IMPORT FAILED');
    }
  }

  /// `SAVE AS NEW PLAYLIST` from the import sheet. Writes, then re-reads the
  /// store so the confirmation reports what actually landed.
  Future<void> commitPendingAsPlaylist([String? name]) async {
    final pending = state.pendingImport;
    if (pending == null) return;
    final title = (name ?? pending.name).trim();
    if (title.isEmpty) return;

    try {
      final playlist = await _library.createPlaylistWith(
        title,
        pending.tracks,
        description: 'IMPORTED FROM ${pending.provider}',
      );
      _reload();
      final stored = _library.playlistById(playlist.id)?.tracks.length ?? 0;
      emit(state.copyWith(clearPendingImport: true));
      _toast(stored == 0
          ? 'PLAYLIST SAVED BUT STORAGE IS NOT ANSWERING — SEE COPY REPORT'
          : 'SAVED "$title" // $stored TRACKS');
    } catch (e) {
      debugPrint('Import save failed: $e');
      _toast('COULD NOT SAVE THAT PLAYLIST');
    }
  }

  /// `ADD TO …` from the import sheet: files the scanned tracks into a playlist
  /// the user already owns, instead of creating another one.
  Future<void> commitPendingIntoPlaylist(String playlistId) async {
    final pending = state.pendingImport;
    if (pending == null) return;

    final target = _library.playlistById(playlistId);
    if (target == null) {
      _toast('THAT PLAYLIST IS GONE');
      return;
    }

    try {
      await _library.addAllToPlaylist(playlistId, pending.tracks);
      _reload();
      final after = _library.playlistById(playlistId)?.tracks.length ?? 0;
      emit(state.copyWith(clearPendingImport: true));
      _toast('ADDED TO ${target.name.toUpperCase()} // $after TRACKS');
    } catch (e) {
      debugPrint('Import merge failed: $e');
      _toast('COULD NOT ADD TO THAT PLAYLIST');
    }
  }

  void discardPendingImport() {
    if (state.pendingImport == null) return;
    emit(state.copyWith(clearPendingImport: true));
    _toast('IMPORT DISCARDED');
  }

  // ------------------------------------------------------------------ backup

  /// Writes a `.json` backup and returns its path, or `null` on failure.
  Future<String?> exportBackup() async {
    final path = await _backup.exportToFile();
    _toast(path == null ? 'EXPORT FAILED' : 'BACKUP WRITTEN TO DOCUMENTS');
    return path;
  }

  Future<BackupResult> importBackup(String json) async {
    final result = await _backup.importFromJson(json);
    _toast(result.message.toUpperCase());
    return result;
  }

  // ------------------------------------------------------------------- toast

  /// Public entry point so any sheet can raise the same snackbar channel.
  void showToast(String message) => _toast(message);

  void _toast(String message) {
    if (isClosed) return;
    emit(state.copyWith(toast: message));
  }

  /// The screen calls this after showing the snackbar so it never repeats.
  void consumeToast() {
    if (isClosed) return;
    emit(state.copyWith(clearToast: true));
  }

  static String _mb(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return mb < 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.round()} MB';
  }

  @override
  Future<void> close() {
    _store.revision.removeListener(_reload);
    return super.close();
  }
}

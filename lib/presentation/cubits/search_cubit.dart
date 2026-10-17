import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/utils/debouncer.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/music_repository.dart';

/// Lifecycle of one search request.
enum SearchStatus { idle, loading, ready, empty, error }

/// The result-category pills.
enum SearchFacet { all, songs, artists, albums, playlists }

extension SearchFacetLabel on SearchFacet {
  String get label => switch (this) {
    SearchFacet.all => 'ALL',
    SearchFacet.songs => 'SONGS (320K)',
    SearchFacet.artists => 'ARTISTS',
    SearchFacet.albums => 'ALBUMS',
    SearchFacet.playlists => 'PLAYLISTS',
  };
}

class SearchState extends Equatable {
  const SearchState({
    this.query = '',
    this.committedQuery = '',
    this.status = SearchStatus.idle,
    this.results = const SearchResults(),
    this.facet = SearchFacet.all,
    this.recents = const [],
    this.suggestions = const [],
    this.loadingMore = false,
    this.canLoadMore = false,
    this.errorText,
  });

  final String query;

  /// The query the visible results belong to — the field can be ahead of it.
  final String committedQuery;
  final SearchStatus status;
  final SearchResults results;
  final SearchFacet facet;
  final List<String> recents;
  final List<String> suggestions;
  final bool loadingMore;
  final bool canLoadMore;
  final String? errorText;

  bool get isSearching => status == SearchStatus.loading;

  bool get hasResults => !results.isEmpty;

  /// The default genre grid shows when nothing has been typed.
  bool get showBrowser => query.trim().isEmpty;

  int get songCount => results.songs.length;

  SearchState copyWith({
    String? query,
    String? committedQuery,
    SearchStatus? status,
    SearchResults? results,
    SearchFacet? facet,
    List<String>? recents,
    List<String>? suggestions,
    bool? loadingMore,
    bool? canLoadMore,
    String? errorText,
    bool clearError = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      committedQuery: committedQuery ?? this.committedQuery,
      status: status ?? this.status,
      results: results ?? this.results,
      facet: facet ?? this.facet,
      recents: recents ?? this.recents,
      suggestions: suggestions ?? this.suggestions,
      loadingMore: loadingMore ?? this.loadingMore,
      canLoadMore: canLoadMore ?? this.canLoadMore,
      errorText: clearError ? null : (errorText ?? this.errorText),
    );
  }

  @override
  List<Object?> get props => [
    query,
    committedQuery,
    status,
    results,
    facet,
    recents,
    suggestions,
    loadingMore,
    canLoadMore,
    errorText,
  ];
}

/// Real-time search: one 350 ms-debounced request per typing burst, with the
/// last fifteen queries persisted for the focused state.
class SearchCubit extends Cubit<SearchState> {
  SearchCubit({
    required MusicRepository music,
    required LibraryRepository library,
  })  : _music = music,
        _library = library,
        super(const SearchState()) {
    _debouncer = Debouncer(duration: const Duration(milliseconds: 350));
    emit(state.copyWith(recents: _library.recentSearches()));
  }

  final MusicRepository _music;
  final LibraryRepository _library;
  late final Debouncer _debouncer;

  int _page = 1;
  int _requestToken = 0;

  // --------------------------------------------------------------- input

  void onQueryChanged(String value) {
    emit(state.copyWith(query: value, clearError: true));
    if (value.trim().isEmpty) {
      _debouncer.cancel();
      emit(
        state.copyWith(
          status: SearchStatus.idle,
          committedQuery: '',
          results: const SearchResults(),
          suggestions: const [],
          canLoadMore: false,
        ),
      );
      return;
    }
    _debouncer(() => _run(value.trim()));
  }

  /// Enter key, or tapping a suggestion: skip the debounce entirely.
  void submit([String? value]) {
    final query = (value ?? state.query).trim();
    if (query.isEmpty) return;
    if (value != null) emit(state.copyWith(query: query));
    _debouncer.runNow(() => _run(query));
  }

  void clear() {
    _debouncer.cancel();
    emit(
      state.copyWith(
        query: '',
        committedQuery: '',
        status: SearchStatus.idle,
        results: const SearchResults(),
        suggestions: const [],
        canLoadMore: false,
        facet: SearchFacet.all,
      ),
    );
  }

  void selectFacet(SearchFacet facet) {
    if (facet == state.facet) return;
    emit(state.copyWith(facet: facet));
  }

  // ------------------------------------------------------------- execution

  Future<void> _run(String query) async {
    final token = ++_requestToken;
    _page = 1;
    emit(state.copyWith(status: SearchStatus.loading, clearError: true));

    try {
      final results = await _music.search(query);
      if (isClosed || token != _requestToken) return;

      await _library.recordSearch(query);

      emit(
        state.copyWith(
          status: results.isEmpty ? SearchStatus.empty : SearchStatus.ready,
          committedQuery: query,
          results: results,
          recents: _library.recentSearches(),
          suggestions: _suggestionsFor(results, query),
          canLoadMore: results.songs.length >= 25,
        ),
      );
    } catch (e) {
      if (isClosed || token != _requestToken) return;
      emit(
        state.copyWith(
          status: SearchStatus.error,
          errorText: 'SEARCH FAILED — CHECK YOUR CONNECTION',
        ),
      );
    }
  }

  /// Page 2+ of the song facet, appended to what is already on screen.
  Future<void> loadMoreSongs() async {
    if (state.loadingMore || !state.canLoadMore) return;
    final query = state.committedQuery;
    if (query.isEmpty) return;

    emit(state.copyWith(loadingMore: true));
    try {
      final more = await _music.searchSongs(query, page: _page + 1);
      if (isClosed) return;
      if (more.isEmpty) {
        emit(state.copyWith(loadingMore: false, canLoadMore: false));
        return;
      }
      _page++;
      emit(
        state.copyWith(
          loadingMore: false,
          canLoadMore: more.length >= 25,
          results: SearchResults(
            query: query,
            songs: Track.dedupe([...state.results.songs, ...more]),
            albums: state.results.albums,
            artists: state.results.artists,
            playlists: state.results.playlists,
          ),
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loadingMore: false));
    }
  }

  /// Live completions derived from the results already in hand, so typing
  /// never costs a second round trip.
  List<String> _suggestionsFor(SearchResults results, String query) {
    final needle = query.toLowerCase();
    final out = <String>[];
    for (final track in results.songs) {
      final title = track.title;
      if (title.isEmpty) continue;
      if (!title.toLowerCase().contains(needle)) continue;
      if (out.contains(title)) continue;
      out.add(title);
      if (out.length == 6) break;
    }
    return out;
  }

  // -------------------------------------------------------------- recents

  Future<void> removeRecent(String query) async {
    await _library.removeSearch(query);
    if (isClosed) return;
    emit(state.copyWith(recents: _library.recentSearches()));
  }

  Future<void> clearRecents() async {
    await _library.clearSearches();
    if (isClosed) return;
    emit(state.copyWith(recents: const []));
  }

  @override
  Future<void> close() {
    _debouncer.dispose();
    return super.close();
  }
}

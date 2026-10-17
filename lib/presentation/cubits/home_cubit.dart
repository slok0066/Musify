import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/jiosaavn_client.dart';
import '../../data/models/collection.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/music_repository.dart';
import '../../data/sources/local_store.dart';
import '../../services/network_monitor.dart';

/// Where the Home feed is in its lifecycle.
enum HomeStatus { loading, ready, offline, error }

/// The header's quick filter pills.
enum HomeFilter { all, music, spatial, offline }

extension HomeFilterLabel on HomeFilter {
  String get label => switch (this) {
    HomeFilter.all => 'ALL',
    HomeFilter.music => 'MUSIC',
    HomeFilter.spatial => '8D SPATIAL PICKS',
    HomeFilter.offline => 'OFFLINE READY',
  };
}

/// What a Quick Access card should do when tapped.
enum QuickKind { liked, downloads, collection }

/// One of the six Spotify-style quick access cards.
class QuickCard extends Equatable {
  const QuickCard({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.imageUrl = '',
    this.mosaic = const [],
    this.collection,
  });

  final QuickKind kind;
  final String title;
  final String subtitle;
  final String imageUrl;
  final List<String> mosaic;
  final Collection? collection;

  @override
  List<Object?> get props => [kind, title, subtitle, imageUrl, collection];
}

class HomeState extends Equatable {
  const HomeState({
    this.status = HomeStatus.loading,
    this.feed = const HomeFeed(),
    this.mixes = const [],
    this.continueListening = const [],
    this.cachedTracks = const [],
    this.downloads = const [],
    this.liked = const [],
    this.quickCards = const [],
    this.spatialPicks = const [],
    this.filter = HomeFilter.all,
    this.refreshing = false,
    this.errorText,
  });

  final HomeStatus status;
  final HomeFeed feed;
  final List<Collection> mixes;
  final List<Track> continueListening;
  final List<Track> cachedTracks;
  final List<Track> downloads;
  final List<Track> liked;
  final List<QuickCard> quickCards;
  final List<Track> spatialPicks;
  final HomeFilter filter;
  final bool refreshing;
  final String? errorText;

  bool get isOffline => status == HomeStatus.offline;

  /// Recently played rail, newest first — the engine's history already is.
  List<Track> get continueRail => continueListening;

  List<RailItem> get trending => feed.trending;

  List<RailItem> get charts => feed.charts;

  List<RailItem> get albums => feed.albums;

  List<RailItem> get playlists => feed.playlists;

  List<Collection> get genres => feed.genres;

  List<Track> get topSearches => feed.topSearches;

  HomeState copyWith({
    HomeStatus? status,
    HomeFeed? feed,
    List<Collection>? mixes,
    List<Track>? continueListening,
    List<Track>? cachedTracks,
    List<Track>? downloads,
    List<Track>? liked,
    List<QuickCard>? quickCards,
    List<Track>? spatialPicks,
    HomeFilter? filter,
    bool? refreshing,
    String? errorText,
    bool clearError = false,
  }) {
    return HomeState(
      status: status ?? this.status,
      feed: feed ?? this.feed,
      mixes: mixes ?? this.mixes,
      continueListening: continueListening ?? this.continueListening,
      cachedTracks: cachedTracks ?? this.cachedTracks,
      downloads: downloads ?? this.downloads,
      liked: liked ?? this.liked,
      quickCards: quickCards ?? this.quickCards,
      spatialPicks: spatialPicks ?? this.spatialPicks,
      filter: filter ?? this.filter,
      refreshing: refreshing ?? this.refreshing,
      errorText: clearError ? null : (errorText ?? this.errorText),
    );
  }

  @override
  List<Object?> get props => [
    status,
    feed,
    mixes,
    continueListening,
    cachedTracks,
    downloads,
    liked,
    quickCards,
    spatialPicks,
    filter,
    refreshing,
    errorText,
  ];
}

/// Loads the Home screen: one launch call for the rails, one history read for
/// the personalised parts, and a local-only fallback when there is no network.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit({
    required MusicRepository music,
    required LibraryRepository library,
    required LocalStore store,
    required NetworkMonitor network,
  })  : _music = music,
        _library = library,
        _store = store,
        _network = network,
        super(const HomeState()) {
    _store.revision.addListener(_onLibraryChanged);
    _network.isOnline.addListener(_onOnlineChanged);
  }

  final MusicRepository _music;
  final LibraryRepository _library;
  final LocalStore _store;
  final NetworkMonitor _network;

  bool _loading = false;
  bool _spatialLoading = false;

  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    _loading = true;

    _emitLocal();
    emit(state.copyWith(refreshing: refresh, clearError: true));

    try {
      final feed = await _music.loadHome(refresh: refresh);
      final mixes = feed.isOffline
          ? const <Collection>[]
          : await _music.dailyMixes(state.continueListening);

      if (isClosed) return;
      emit(
        state.copyWith(
          status: feed.isOffline ? HomeStatus.offline : HomeStatus.ready,
          feed: feed,
          mixes: mixes,
          quickCards: _buildCards(feed: feed, mixes: mixes),
          refreshing: false,
          clearError: true,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: HomeStatus.error,
          refreshing: false,
          errorText: 'COULD NOT REACH THE CATALOGUE',
        ),
      );
    } finally {
      _loading = false;
    }
  }

  /// Pull-to-refresh: the same load, but with the catalogue cache bypassed.
  Future<void> refresh() => load(refresh: true);

  void setFilter(HomeFilter filter) {
    if (filter == state.filter) return;
    emit(state.copyWith(filter: filter));
    if (filter == HomeFilter.spatial) unawaited(loadSpatialPicks());
  }

  /// Called when the transport changes: coming back online reloads the rails.
  void onConnectivityChanged() {
    if (_network.isOnline.value && state.status == HomeStatus.offline) {
      unawaited(load());
    }
  }

  /// The `8D SPATIAL PICKS` filter asks the catalogue for spatial-audio
  /// renditions once, then keeps them for the session.
  Future<void> loadSpatialPicks() async {
    if (state.spatialPicks.isNotEmpty || _spatialLoading) return;
    _spatialLoading = true;
    try {
      final picks = await _music.moodTracks('8d audio');
      if (isClosed) return;
      emit(state.copyWith(spatialPicks: picks));
    } catch (_) {
      // A dead spatial query simply leaves the rail empty.
    } finally {
      _spatialLoading = false;
    }
  }

  void _onOnlineChanged() {
    if (isClosed) return;
    onConnectivityChanged();
  }

  void _onLibraryChanged() {
    if (isClosed) return;
    _emitLocal();
    emit(state.copyWith(quickCards: _buildCards(feed: state.feed, mixes: state.mixes)));
  }

  /// Re-reads everything that lives on the device — never touches the network.
  void _emitLocal() {
    final liked = _library.liked();
    final downloads = _library.downloads();
    final history = _library.history();
    emit(
      state.copyWith(
        liked: liked,
        downloads: downloads,
        continueListening: history.take(20).toList(),
        cachedTracks: _library.recentlyCached().take(30).toList(),
        quickCards: _buildCards(feed: state.feed, mixes: state.mixes),
      ),
    );
  }

  /// Liked Songs + Offline Vault + the four most recent collections, exactly
  /// six cards as the PRD's 2×3 grid requires.
  List<QuickCard> _buildCards({required HomeFeed feed, required List<Collection> mixes}) {
    final cards = <QuickCard>[
      QuickCard(
        kind: QuickKind.liked,
        title: 'LIKED SONGS',
        subtitle: '${state.liked.length} TRACKS',
        mosaic: state.liked.take(4).map((t) => t.imageUrl).toList(),
      ),
      QuickCard(
        kind: QuickKind.downloads,
        title: 'OFFLINE VAULT',
        subtitle: '${state.downloads.length} TRACKS',
        mosaic: state.downloads.take(4).map((t) => t.imageUrl).toList(),
      ),
    ];

    final recents = _library.recentCollections();
    for (final collection in recents) {
      if (cards.length >= 6) break;
      cards.add(
        QuickCard(
          kind: QuickKind.collection,
          title: collection.title,
          subtitle: collection.subtitle.isEmpty
              ? (collection.songCount == null ? 'PLAYLIST' : '${collection.songCount} TRACKS')
              : collection.subtitle,
          imageUrl: collection.imageUrl,
          collection: collection,
        ),
      );
    }

    // Pad from the live catalogue so the grid is never half empty.
    if (cards.length < 6) {
      final pool = <RailItem>[
        ...mixes.map((c) => RailItem.ofCollection(c)),
        ...feed.playlists,
        ...feed.albums,
        ...feed.trending.where((r) => r.isCollection),
      ];
      for (final item in pool) {
        if (cards.length >= 6) break;
        final collection = item.collection;
        if (collection == null) continue;
        if (cards.any((c) => c.collection?.id == collection.id)) continue;
        cards.add(
          QuickCard(
            kind: QuickKind.collection,
            title: collection.title,
            subtitle: collection.subtitle.isEmpty ? collection.kindLabel : collection.subtitle,
            imageUrl: collection.imageUrl,
            collection: collection,
          ),
        );
      }
    }

    return cards;
  }

  @override
  Future<void> close() {
    _store.revision.removeListener(_onLibraryChanged);
    _network.isOnline.removeListener(_onOnlineChanged);
    return super.close();
  }
}

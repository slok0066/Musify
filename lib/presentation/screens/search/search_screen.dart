import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/collection.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../services/service_locator.dart';
import '../../cubits/navigation_cubit.dart';
import '../../cubits/player_cubit.dart';
import '../../cubits/search_cubit.dart';
import '../../navigation.dart';
import '../../widgets/collection_cards.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/state_placeholders.dart';
import '../../widgets/swiss_artwork.dart';
import '../../widgets/track_list_tile.dart';
import '../../widgets/track_options_sheet.dart';

/// `02 // SEARCH` — one 350 ms-debounced request per typing burst.
///
/// The default state is a browser (recent queries + the eight genre tiles), so
/// the tab is never an empty box, and every result row is the same Swiss row the
/// rest of the app plays from.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SearchCubit>(
      create: (_) => locator<SearchCubit>(),
      child: const _SearchView(),
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView();

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<Collection> _genres = MusicRepository.defaultGenres;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadGenres();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadGenres() async {
    try {
      final genres = await locator<MusicRepository>().genresOnly();
      if (!mounted || genres.isEmpty) return;
      setState(() => _genres = genres);
    } catch (_) {
      // The curated eight are already on screen.
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final cubit = context.read<SearchCubit>();
    final remaining = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 600) cubit.loadMoreSongs();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SearchCubit, SearchState>(
      listenWhen: (previous, next) => previous.query != next.query,
      listener: (context, state) {
        if (_controller.text != state.query) {
          _controller.text = state.query;
          _controller.selection = TextSelection.collapsed(offset: state.query.length);
        }
      },
      builder: (context, state) {
        return Column(
          children: [
            ScreenHeader(
              tab: AppTab.search,
              subtitle: state.committedQuery.isEmpty
                  ? 'Tracks, artists, albums and playlists'
                  : 'Results for “${state.committedQuery}”',
              actions: Column(
                children: [
                  _SearchField(controller: _controller),
                  const SizedBox(height: SwissGrid.sm),
                  if (state.status == SearchStatus.ready || state.status == SearchStatus.loading)
                    PillStrip(
                      padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
                      children: [
                        for (final facet in SearchFacet.values)
                          SwissPill(
                            label: facet.label,
                            selected: state.facet == facet,
                            dense: true,
                            onTap: () => context.read<SearchCubit>().selectFacet(facet),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: _Results(
                state: state,
                genres: _genres,
                controller: _scroll,
                onQuery: (value) {
                  _controller.text = value;
                  _controller.selection = TextSelection.collapsed(offset: value.length);
                  context.read<SearchCubit>().submit(value);
                },
                searchField: _controller,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final hasText = widget.controller.text.isNotEmpty;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
        border: Border.all(color: t.hairline, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: t.inkMuted),
          const SizedBox(width: SwissGrid.sm),
          Expanded(
            child: TextField(
              controller: widget.controller,
              style: SwissType.body.copyWith(color: t.ink),
              cursorColor: t.accent,
              cursorWidth: 1.5,
              textInputAction: TextInputAction.search,
              onChanged: (value) {
                setState(() {});
                context.read<SearchCubit>().onQueryChanged(value);
              },
              onSubmitted: (value) => context.read<SearchCubit>().submit(value),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: 'Search tracks, artists, acoustics...',
                hintStyle: SwissType.bodySm.copyWith(color: t.inkFaint),
              ),
            ),
          ),
          if (hasText)
            GestureDetector(
              onTap: () {
                widget.controller.clear();
                setState(() {});
                context.read<SearchCubit>().clear();
              },
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: t.surfaceSunken,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, size: 14, color: t.inkMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.state,
    required this.genres,
    required this.controller,
    required this.onQuery,
    required this.searchField,
  });

  final SearchState state;
  final List<Collection> genres;
  final ScrollController controller;
  final ValueChanged<String> onQuery;
  final TextEditingController searchField;

  @override
  Widget build(BuildContext context) {
    if (state.showBrowser) {
      return _Browser(genres: genres, recents: state.recents, onQuery: onQuery);
    }

    switch (state.status) {
      case SearchStatus.idle:
        return _Browser(genres: genres, recents: state.recents, onQuery: onQuery);
      case SearchStatus.loading:
        return const _LoadingList();
      case SearchStatus.error:
        return SingleChildScrollView(
          child: MusifyStatePanel(
            index: 'ERR // SEARCH',
            title: 'Search failed',
            message: state.errorText ?? 'CHECK YOUR CONNECTION',
            icon: Icons.cloud_off,
            actionLabel: 'RETRY',
            onAction: () => context.read<SearchCubit>().submit(),
          ),
        );
      case SearchStatus.empty:
        return SingleChildScrollView(
          child: MusifyStatePanel(
            index: '00 // NO MATCHES',
            title: 'Nothing found',
            message: 'No songs, albums, artists or playlists matched '
                '“${state.committedQuery}”. Try a shorter query.',
            icon: Icons.search_off,
            actionLabel: 'CLEAR SEARCH',
            onAction: () {
              searchField.clear();
              context.read<SearchCubit>().clear();
            },
          ),
        );
      case SearchStatus.ready:
        return _ResultList(state: state, controller: controller);
    }
  }
}

class _Browser extends StatelessWidget {
  const _Browser({required this.genres, required this.recents, required this.onQuery});

  final List<Collection> genres;
  final List<String> recents;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: SwissGrid.xxl),
      children: [
        if (recents.isNotEmpty) ...[
          SectionHeader(
            index: '01',
            title: 'RECENT QUERIES',
            trailing: TextButton(
              onPressed: () => context.read<SearchCubit>().clearRecents(),
              child: Text(
                'CLEAR',
                style: SwissType.micro.copyWith(
                  color: t.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
            child: Row(
              children: [
                for (final query in recents.take(8))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _RecentChip(
                      query: query,
                      onTap: () => onQuery(query),
                      onRemove: () => context.read<SearchCubit>().removeRecent(query),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: SwissGrid.md),
        ],
        SectionHeader(
          index: recents.isEmpty ? '01' : '02',
          title: 'BROWSE GENRES',
          subtitle: 'EXPLORE BY CATEGORY',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
          child: GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: genres.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: SwissGrid.md,
              crossAxisSpacing: SwissGrid.md,
              childAspectRatio: 0.86,
            ),
            itemBuilder: (context, i) => CollectionGridTile(
              title: genres[i].title,
              subtitle: genres[i].subtitle,
              imageUrl: genres[i].imageUrl,
              ordinal: '${i + 1}'.padLeft(2, '0'),
              onTap: () => openCollection(context, genres[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Haptics.tap();
          onTap();
        },
        borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
            border: Border.all(color: t.hairline, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 13, color: t.inkMuted),
              const SizedBox(width: 5),
              Text(
                query,
                style: SwissType.bodyXs.copyWith(
                  color: t.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  Haptics.tap();
                  onRemove();
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(Icons.close, size: 12, color: t.inkFaint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.state, required this.controller});

  final SearchState state;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final songs = state.results.songs;
    final player = context.read<PlayerCubit>();

    void play(Track track) => player.playTrack(
          track,
          context: songs,
          source: 'SEARCH',
        );

    final facet = state.facet;
    final showSongs = facet == SearchFacet.all || facet == SearchFacet.songs;
    final showArtists = facet == SearchFacet.all || facet == SearchFacet.artists;
    final showAlbums = facet == SearchFacet.all || facet == SearchFacet.albums;
    final showPlaylists = facet == SearchFacet.all || facet == SearchFacet.playlists;

    final visibleAlbums = showAlbums ? state.results.albums : const <Collection>[];
    final visibleArtists = showArtists ? state.results.artists : const <Collection>[];
    final visiblePlaylists = showPlaylists ? state.results.playlists : const <Collection>[];
    final visibleSongs = showSongs ? songs : const <Track>[];

    return ListView(
      controller: controller,
      padding: const EdgeInsets.only(bottom: SwissGrid.xxl),
      children: [
        if (facet == SearchFacet.all && songs.isNotEmpty)
          _TopResult(
            track: songs.first,
            onPlay: () => play(songs.first),
            queueContext: songs,
          ),
        if (visibleSongs.isNotEmpty) ...[
          SectionHeader(
            index: '01',
            title: 'MATCHED TRACKS',
            subtitle: '${state.results.songs.length}${state.canLoadMore ? '+' : ''} MATCHES',
          ),
          for (var i = 0; i < visibleSongs.take(30).length; i++)
            TrackListTile(
              track: visibleSongs[i],
              index: i,
              showArtwork: true,
              showBitrate: false,
              showDivider: false,
              artworkSize: 52,
              padding: const EdgeInsets.symmetric(
                horizontal: SwissGrid.gutter,
                vertical: 8,
              ),
              isCurrent: player.state.track?.id == visibleSongs[i].id,
              isPlaying: player.state.isPlaying,
              onTap: () => play(visibleSongs[i]),
              onOptions: () => showTrackOptions(context, visibleSongs[i], source: 'SEARCH', queueContext: songs),
            ),
          if (facet == SearchFacet.songs)
            _LoadMore(
              canLoadMore: state.canLoadMore,
              loading: state.loadingMore,
              onLoad: () => context.read<SearchCubit>().loadMoreSongs(),
            ),
        ],
        if (visibleArtists.isNotEmpty) _CollectionRail(index: '02', title: 'ARTISTS', items: visibleArtists, round: true),
        if (visibleAlbums.isNotEmpty) _CollectionRail(index: '03', title: 'ALBUMS', items: visibleAlbums),
        if (visiblePlaylists.isNotEmpty) _CollectionRail(index: '04', title: 'PLAYLISTS', items: visiblePlaylists),
        if (visibleSongs.isEmpty &&
            visibleArtists.isEmpty &&
            visibleAlbums.isEmpty &&
            visiblePlaylists.isEmpty)
          const MusifyStatePanel(
            index: '00 // EMPTY FACET',
            title: 'Nothing in this facet',
            message: 'Switch back to ALL to see everything this query matched.',
          ),
      ],
    );
  }
}

class _TopResult extends StatelessWidget {
  const _TopResult({
    required this.track,
    required this.onPlay,
    this.queueContext = const [],
  });

  final Track track;
  final VoidCallback onPlay;
  final List<Track> queueContext;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(SwissGrid.gutter, SwissGrid.md, SwissGrid.gutter, SwissGrid.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOP RESULT',
                style: SwissType.label.copyWith(
                  color: t.inkMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: t.surfaceRaised,
                  borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
                  border: Border.all(color: t.hairline),
                ),
                child: Text(
                  'MATCH 99.4%',
                  style: SwissType.micro.copyWith(
                    color: t.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SwissGrid.sm),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.surfaceRaised,
              border: Border.all(color: t.hairline, width: 1),
              borderRadius: BorderRadius.circular(SwissTokens.radius),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwissArtwork(
                      imageUrl: track.imageUrl,
                      size: 72,
                      radius: 12,
                      placeholderIcon: Icons.music_note,
                    ),
                    const SizedBox(width: SwissGrid.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SwissBadge(
                                text: '8D SPATIAL',
                                color: t.accent,
                              ),
                              if (track.isDownloaded) ...[
                                const SizedBox(width: 4),
                                SwissBadge(text: 'OFFLINE', color: t.positive),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            track.title,
                            style: SwissType.displaySm.copyWith(
                              color: t.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.displayArtist,
                            style: SwissType.bodyXs.copyWith(color: t.inkMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            Fmt.durationShort(track.duration),
                            style: SwissType.micro.copyWith(color: t.inkFaint),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    InkWell(
                      onTap: () {
                        Haptics.tap();
                        onPlay();
                      },
                      borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
                          boxShadow: [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow, size: 16, color: t.surfaceSunken),
                            const SizedBox(width: 4),
                            Text(
                              'Play Now',
                              style: SwissType.bodySm.copyWith(
                                color: t.surfaceSunken,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        Haptics.tap();
                        showTrackOptions(
                          context,
                          track,
                          source: 'SEARCH // TOP RESULT',
                          queueContext: queueContext,
                        );
                      },
                      borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: t.surfaceSunken,
                          borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
                          border: Border.all(color: t.hairline),
                        ),
                        child: Icon(Icons.playlist_add, size: 17, color: t.ink),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'FLAC · 24-BIT',
                      style: SwissType.micro.copyWith(
                        color: t.inkFaint,
                        fontSize: 10,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      icon: Icon(Icons.info_outline, size: 16, color: t.inkFaint),
                      splashRadius: 16,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: EdgeInsets.zero,
                      onPressed: () => showTrackOptions(
                        context,
                        track,
                        source: 'SEARCH // TOP RESULT',
                        queueContext: queueContext,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionRail extends StatelessWidget {
  const _CollectionRail({required this.index, required this.title, required this.items, this.round = false});

  final String index;
  final String title;
  final List<Collection> items;
  final bool round;

  @override
  Widget build(BuildContext context) {
    return SwissRail(
      index: index,
      title: title,
      height: round ? 206 : 214,
      children: [
        for (final item in items)
          CollectionRailCard(
            collection: item,
            onTap: () => openCollection(context, item),
          ),
      ],
    );
  }
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({required this.canLoadMore, required this.loading, required this.onLoad});

  final bool canLoadMore;
  final bool loading;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(SwissGrid.gutter, SwissGrid.lg, SwissGrid.gutter, SwissGrid.md),
      child: canLoadMore || loading
          ? Row(
              children: [
                Expanded(
                  child: TactileKeycap(
                    onPressed: loading ? null : onLoad,
                    height: 42,
                    width: double.infinity,
                    child: Text(loading ? 'LOADING…' : 'LOAD MORE SONGS'),
                  ),
                ),
              ],
            )
          : Text('END OF RESULTS', style: SwissType.micro.copyWith(color: t.inkFaint)),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(SwissGrid.gutter),
      children: [
        for (var i = 0; i < 8; i++) ...[
          Row(
            children: [
              const SwissSkeleton(width: 46, height: 46),
              const SizedBox(width: SwissGrid.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwissSkeleton(height: 12, width: 180 + (i % 3) * 40),
                    const SizedBox(height: 6),
                    SwissSkeleton(height: 9, width: 110 + (i % 2) * 30),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SwissGrid.lg),
        ],
      ],
    );
  }
}

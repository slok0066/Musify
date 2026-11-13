import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../data/models/collection.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/library_repository.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../services/service_locator.dart';
import '../../cubits/library_cubit.dart';
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

/// `02 // SEARCH` — Clean, minimal Spotify / Apple-style search experience.
///
/// Features a capsule search bar, an asymmetric 2-column "Made for you" grid,
/// and live "Recently Played" tracks with verified badges and heart toggles.
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
      // The curated fallbacks are already in place.
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final cubit = context.read<SearchCubit>();
    final remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 600) cubit.loadMoreSongs();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SearchCubit, SearchState>(
      listenWhen: (previous, next) => previous.query != next.query,
      listener: (context, state) {
        if (_controller.text != state.query) {
          _controller.text = state.query;
          _controller.selection =
              TextSelection.collapsed(offset: state.query.length);
        }
      },
      builder: (context, state) {
        final isSearching = state.committedQuery.isNotEmpty ||
            (state.status == SearchStatus.ready ||
                state.status == SearchStatus.loading);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
                  child: _SearchField(controller: _controller),
                ),
                if (isSearching) ...[
                  const SizedBox(height: 10),
                  PillStrip(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SwissGrid.gutter),
                    children: [
                      for (final facet in SearchFacet.values)
                        SwissPill(
                          label: facet.label,
                          selected: state.facet == facet,
                          dense: true,
                          onTap: () =>
                              context.read<SearchCubit>().selectFacet(facet),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: _Results(
                    state: state,
                    genres: _genres,
                    controller: _scroll,
                    onQuery: (value) {
                      _controller.text = value;
                      _controller.selection =
                          TextSelection.collapsed(offset: value.length);
                      context.read<SearchCubit>().submit(value);
                    },
                    searchField: _controller,
                  ),
                ),
              ],
            ),
          ),
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
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E22),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 22,
            color: Colors.white.withValues(alpha: 0.60),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              style: const TextStyle(
                fontFamily: 'PlusJakartaSans',
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: t.accent,
              cursorWidth: 1.5,
              textInputAction: TextInputAction.search,
              onChanged: (value) {
                setState(() {});
                context.read<SearchCubit>().onQueryChanged(value);
              },
              onSubmitted: (value) =>
                  context.read<SearchCubit>().submit(value),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: 'Search',
                hintStyle: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          if (hasText)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.controller.clear();
                setState(() {});
                context.read<SearchCubit>().clear();
              },
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 16, color: Colors.white),
              ),
            )
          else
            Icon(
              Icons.mic_none_rounded,
              size: 22,
              color: Colors.white.withValues(alpha: 0.60),
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

/// The modern, aesthetic browse view matching the screenshot:
/// 1. "Made for you" asymmetric 2-column masonry grid
/// 2. "Recently Played" list with verified badges and heart toggles
class _Browser extends StatelessWidget {
  const _Browser({
    required this.genres,
    required this.recents,
    required this.onQuery,
  });

  final List<Collection> genres;
  final List<String> recents;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final library = locator<LibraryRepository>();
    final liveHistory = library.history();
    final displayHistory = liveHistory.take(5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SwissGrid.gutter,
        4,
        SwissGrid.gutter,
        SwissGrid.xxl,
      ),
      children: [
        // 1. "Made for you" Header
        const Text(
          'Made for you',
          style: TextStyle(
            fontFamily: 'PlusJakartaSans',
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 14),

        // 2. Asymmetric 2-Column Masonry Grid
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Tall Violet card (195px) + Compact Coral card (130px)
            Expanded(
              child: Column(
                children: [
                  _MadeForYouCard(
                    title: 'Weekly Mix',
                    subtitle: 'English & all hits',
                    color: const Color(0xFF6C3BE8),
                    height: 195,
                    isMultiAvatar: true,
                    avatarUrls: const [
                      'https://c.saavncdn.com/artists/The_Weeknd_002_20241003071400_500x500.jpg',
                      'https://c.saavncdn.com/artists/Ariana_Grande_007_20260616180049_500x500.jpg',
                      'https://c.saavncdn.com/artists/Khalid_001_20241021124245_500x500.jpg',
                    ],
                    onTap: () {
                      openCollection(
                        context,
                        const Collection(
                          id: '__weekly_mix__',
                          title: 'Weekly Mix',
                          kind: CollectionKind.mix,
                          subtitle: 'ENGLISH & ALL MUSIC // RANDOM MIX',
                          imageUrl:
                              'https://c.saavncdn.com/artists/The_Weeknd_002_20241003071400_500x500.jpg',
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _MadeForYouCard(
                    title: 'Omah Lay',
                    subtitle: '19 songs',
                    color: const Color(0xFFE85A35),
                    height: 130,
                    isMultiAvatar: false,
                    assetPath: 'assets/artists/omah_lay.png',
                    avatarUrls: const [
                      'https://c.saavncdn.com/artists/Omah_lay_000_20231120091242_500x500.jpg',
                    ],
                    onTap: () => openArtist(context, name: 'Omah Lay'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Right Column: Compact Lavender card (130px) + Tall Orange card (195px)
            Expanded(
              child: Column(
                children: [
                  _MadeForYouCard(
                    title: 'Ariana Grande',
                    subtitle: '24 songs',
                    color: const Color(0xFF9B6CE8),
                    height: 130,
                    isMultiAvatar: false,
                    assetPath: 'assets/artists/ariana_grande.png',
                    avatarUrls: const [
                      'https://c.saavncdn.com/artists/Ariana_Grande_007_20260616180049_500x500.jpg',
                    ],
                    onTap: () => openArtist(context, name: 'Ariana Grande'),
                  ),
                  const SizedBox(height: 12),
                  _MadeForYouCard(
                    title: 'Chill Out',
                    subtitle: '30 songs',
                    color: const Color(0xFFFF6231),
                    height: 195,
                    isMultiAvatar: true,
                    avatarUrls: const [
                      'https://c.saavncdn.com/artists/The_Weeknd_002_20241003071400_500x500.jpg',
                      'https://c.saavncdn.com/artists/Omah_lay_000_20231120091242_500x500.jpg',
                      'https://c.saavncdn.com/artists/Khalid_001_20241021124245_500x500.jpg',
                    ],
                    onTap: () {
                      openCollection(
                        context,
                        const Collection(
                          id: '1079336813',
                          title: 'Chill Out',
                          kind: CollectionKind.mix,
                          subtitle: 'CHILL // LO-FI & RELAX',
                          imageUrl:
                              'https://c.saavncdn.com/editorial/ChillMaaro-LoFiMix_20260403095103.jpg',
                          songCount: 30,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),

        // 3. "Recently Played" Section (only when real history exists)
        if (displayHistory.isNotEmpty) ...[
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recently Played',
                style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.read<NavigationCubit>().select(AppTab.library),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Text(
                    'View all',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      color: Colors.white.withValues(alpha: 0.60),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 4. Recently Played Track List
          BlocBuilder<LibraryCubit, LibraryState>(
            builder: (context, libState) {
              final player = context.read<PlayerCubit>();
              return Column(
                children: [
                  for (var i = 0; i < displayHistory.length; i++)
                    _RecentTrackTile(
                      track: displayHistory[i],
                      isLiked: libState.liked.any((t) => t.id == displayHistory[i].id),
                      onTap: () {
                        player.playTrack(
                          displayHistory[i],
                          context: displayHistory,
                          source: 'SEARCH // RECENTLY PLAYED',
                        );
                      },
                      onToggleLike: () {
                        context.read<LibraryCubit>().toggleLike(displayHistory[i]);
                      },
                    ),
                ],
              );
            },
          ),
        ],

        // 5. Recent Search Chips (if any exist)
        if (recents.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RECENT SEARCHES',
                style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              GestureDetector(
                onTap: () => context.read<SearchCubit>().clearRecents(),
                child: Text(
                  'CLEAR',
                  style: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final query in recents.take(6))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _RecentChip(
                      query: query,
                      onTap: () => onQuery(query),
                      onRemove: () =>
                          context.read<SearchCubit>().removeRecent(query),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A "Made for you" card with concentric circles, sparkle icon, and overlapping avatars.
class _MadeForYouCard extends StatelessWidget {
  const _MadeForYouCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.height,
    required this.isMultiAvatar,
    required this.avatarUrls,
    required this.onTap,
    this.assetPath,
  });

  final String title;
  final String subtitle;
  final Color color;
  final double height;
  final bool isMultiAvatar;
  final List<String> avatarUrls;
  final VoidCallback onTap;
  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Stack(
            children: [
              // Subtle ambient concentric rings for tall multi-avatar cards
              if (isMultiAvatar)
                Positioned(
                  bottom: -36,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 115,
                          height: 115,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Card Content: Header & Titles
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sparkle Starburst Icon
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Avatars (Tall Card: 3 overlapping circles)
              if (isMultiAvatar)
                Positioned(
                  bottom: 14,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < avatarUrls.take(3).length; i++)
                        Transform.translate(
                          offset: Offset(i == 0 ? 0 : -10.0 * i, 0),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: avatarUrls[i],
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.white24,
                                  child: const Icon(Icons.person,
                                      size: 20, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              // Cutout Asset on Right (matches design reference)
              else if (assetPath != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: 104,
                  height: height,
                  child: Image.asset(
                    assetPath!,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomRight,
                    errorBuilder: (_, __, ___) => avatarUrls.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: avatarUrls.first,
                            fit: BoxFit.cover,
                          )
                        : const SizedBox.shrink(),
                  ),
                )
              // Compact Card: Circular Cutout Avatar on Right
              else if (avatarUrls.isNotEmpty)
                Positioned(
                  right: -8,
                  bottom: -6,
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: avatarUrls.first,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.white24,
                          child: const Icon(Icons.person,
                              size: 32, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A track tile in the "Recently Played" list matching the user screenshot:
/// [Artwork] [Title, Artist ✓] [Heart]
class _RecentTrackTile extends StatelessWidget {
  const _RecentTrackTile({
    required this.track,
    required this.isLiked,
    required this.onTap,
    required this.onToggleLike,
  });

  final Track track;
  final bool isLiked;
  final VoidCallback onTap;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Haptics.tap();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              // Square Album Artwork (52x52, radius 12)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: CachedNetworkImage(
                    imageUrl: track.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF202024),
                      child: const Icon(Icons.music_note,
                          color: Colors.white54, size: 24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Title & Artist + Verified Checkmark
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      style: const TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.displayArtist,
                            style: TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Favorite Heart Button (Filled if liked, outline if not)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Haptics.tap();
                  onToggleLike();
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 22,
                    color: isLiked
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Haptics.tap();
          onTap();
        },
        borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E22),
            borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                query,
                style: const TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Icon(Icons.close,
                    size: 13, color: Colors.white.withValues(alpha: 0.40)),
              ),
            ],
          ),
        ),
      ),
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

class _ResultList extends StatefulWidget {
  const _ResultList({required this.state, required this.controller});

  final SearchState state;
  final ScrollController controller;

  @override
  State<_ResultList> createState() => _ResultListState();
}

class _ResultListState extends State<_ResultList> {
  static const int _initialLimit = 8;
  static const int _pageSize = 10;
  int _visibleLimit = _initialLimit;

  @override
  void didUpdateWidget(covariant _ResultList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.committedQuery != widget.state.committedQuery) {
      _visibleLimit = _initialLimit;
    }
  }

  void _onShowMore() {
    setState(() {
      _visibleLimit += _pageSize;
    });
    final state = widget.state;
    if ((_visibleLimit >= state.results.songs.length - 2 ||
            _visibleLimit >= state.results.songs.length) &&
        state.canLoadMore &&
        !state.loadingMore) {
      context.read<SearchCubit>().loadMoreSongs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final songs = state.results.songs;
    final player = context.read<PlayerCubit>();

    void play(Track track) => player.playTrack(
          track,
          context: songs,
          source: 'SEARCH',
        );

    final facet = state.facet;
    final showSongs = facet == SearchFacet.all || facet == SearchFacet.songs;
    final showArtists =
        facet == SearchFacet.all || facet == SearchFacet.artists;
    final showAlbums = facet == SearchFacet.all || facet == SearchFacet.albums;
    final showPlaylists =
        facet == SearchFacet.all || facet == SearchFacet.playlists;

    final visibleAlbums =
        showAlbums ? state.results.albums : const <Collection>[];
    final visibleArtists =
        showArtists ? state.results.artists : const <Collection>[];
    final visiblePlaylists =
        showPlaylists ? state.results.playlists : const <Collection>[];
    final visibleSongs = showSongs ? songs : const <Track>[];
    final displayedSongs = visibleSongs.take(_visibleLimit).toList();

    return ListView(
      controller: widget.controller,
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
            subtitle:
                '${displayedSongs.length} OF ${state.results.songs.length}${state.canLoadMore ? '+' : ''} MATCHES',
          ),
          BlocBuilder<PlayerCubit, PlayerState>(
            buildWhen: (previous, next) =>
                previous.track?.id != next.track?.id ||
                previous.isPlaying != next.isPlaying,
            builder: (context, playerState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < displayedSongs.length; i++)
                    TrackListTile(
                      track: displayedSongs[i],
                      index: i,
                      showArtwork: true,
                      showBitrate: false,
                      showDivider: false,
                      artworkSize: 52,
                      padding: const EdgeInsets.symmetric(
                        horizontal: SwissGrid.gutter,
                        vertical: 8,
                      ),
                      isCurrent: playerState.track?.id == displayedSongs[i].id,
                      isPlaying: playerState.isPlaying,
                      onTap: () => play(displayedSongs[i]),
                      onOptions: () => showTrackOptions(
                        context,
                        displayedSongs[i],
                        source: 'SEARCH',
                        queueContext: songs,
                      ),
                    ),
                ],
              );
            },
          ),
          if (_visibleLimit < visibleSongs.length ||
              state.canLoadMore ||
              state.loadingMore)
            _ShowMoreButton(
              loading: state.loadingMore,
              onPressed: _onShowMore,
            ),
        ],
        if (visibleArtists.isNotEmpty)
          _CollectionRail(
            index: '02',
            title: 'ARTISTS',
            items: visibleArtists,
            round: true,
          ),
        if (visibleAlbums.isNotEmpty)
          _CollectionRail(
            index: '03',
            title: 'ALBUMS',
            items: visibleAlbums,
          ),
        if (visiblePlaylists.isNotEmpty)
          _CollectionRail(
            index: '04',
            title: 'PLAYLISTS',
            items: visiblePlaylists,
          ),
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
      padding: const EdgeInsets.fromLTRB(
        SwissGrid.gutter,
        SwissGrid.md,
        SwissGrid.gutter,
        SwissGrid.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOP RESULT',
            style: SwissType.label.copyWith(
              color: t.inkMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: SwissType.title.copyWith(
                              color: t.ink,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            track.artist,
                            style: SwissType.bodySm.copyWith(
                              color: t.inkMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                      borderRadius:
                          BorderRadius.circular(SwissTokens.radiusFull),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius:
                              BorderRadius.circular(SwissTokens.radiusFull),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                size: 18, color: t.accentInk),
                            const SizedBox(width: 4),
                            Text(
                              'Play Now',
                              style: SwissType.label.copyWith(
                                color: t.accentInk,
                                fontWeight: FontWeight.w700,
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
                      borderRadius:
                          BorderRadius.circular(SwissTokens.radiusFull),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: t.surfaceSunken,
                          borderRadius:
                              BorderRadius.circular(SwissTokens.radiusFull),
                          border: Border.all(color: t.hairline),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.more_horiz, size: 16, color: t.ink),
                            const SizedBox(width: 4),
                            Text(
                              'OPTIONS',
                              style: SwissType.micro.copyWith(
                                color: t.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
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
  const _CollectionRail({
    required this.index,
    required this.title,
    required this.items,
    this.round = false,
  });

  final String index;
  final String title;
  final List<Collection> items;
  final bool round;

  @override
  Widget build(BuildContext context) {
    return SwissRail(
      index: index,
      title: title,
      height: 252,
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

class _ShowMoreButton extends StatelessWidget {
  const _ShowMoreButton({
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SwissGrid.gutter,
        SwissGrid.md,
        SwissGrid.gutter,
        SwissGrid.sm,
      ),
      child: TactileKeycap(
        onPressed: loading ? null : onPressed,
        height: 42,
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.ink,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'LOADING MORE…',
                style: SwissType.label.copyWith(
                  color: t.ink,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ] else ...[
              Text(
                'SHOW MORE RESULTS',
                style: SwissType.label.copyWith(
                  color: t.ink,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: t.inkMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

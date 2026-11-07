import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../data/datasources/jiosaavn_client.dart';
import '../../../data/models/collection.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../services/service_locator.dart';
import '../../cubits/home_cubit.dart';
import '../../cubits/navigation_cubit.dart';
import '../../cubits/player_cubit.dart';
import '../../navigation.dart';
import '../../widgets/collection_cards.dart';
import '../../widgets/mountain_atmosphere_hero.dart';
import '../../widgets/state_placeholders.dart';
import '../../widgets/swiss_artwork.dart';
import '../../widgets/track_list_tile.dart';
import '../../widgets/track_options_sheet.dart';

/// `01 // HOME` — the launch feed.
///
/// One orchestrated catalogue call drives the rails; everything personal
/// (Continue Listening, Liked Songs, the Offline Vault, Daily Mixes) is read
/// synchronously off the device, so the screen paints instantly and still works
/// with the radio off.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<HomeCubit>(
      create: (_) => locator<HomeCubit>()..load(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        final loading =
            state.status == HomeStatus.loading && !state.feed.hasData;

        return RefreshIndicator(
          color: SwissTokens.of(context).accent,
          backgroundColor: SwissTokens.of(context).surface,
          onRefresh: () => context.read<HomeCubit>().refresh(),
          child: _Body(state: state, loading: loading),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.loading});

  final HomeState state;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<HomeCubit>();

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: MountainAtmosphereHero(
            refreshing: state.refreshing,
            onRefresh: state.refreshing ? null : cubit.refresh,
          ),
        ),
        if (state.status == HomeStatus.offline)
          SliverToBoxAdapter(
            child: OfflineStrip(
              onRetry: cubit.refresh,
              note: '${state.downloads.length} DOWNLOADED TRACKS AVAILABLE',
            ),
          ),
        if (state.status == HomeStatus.error && !state.feed.hasData)
          SliverToBoxAdapter(
            child: MusifyStatePanel(
              index: 'ERR // CATALOGUE',
              title: 'Could not reach JioSaavn',
              message:
                  'The catalogue did not answer. Your downloads and history are '
                  'still here — retry when the signal improves.',
              icon: Icons.cloud_off,
              actionLabel: 'RETRY',
              onAction: cubit.refresh,
            ),
          ),
        if (loading) ...[
          const SliverToBoxAdapter(
              child: RailSkeleton(count: 3, index: '', title: 'LOADING')),
          const SliverToBoxAdapter(
              child: RailSkeleton(count: 3, index: '', title: 'LOADING')),
        ],
        if (!loading) ...[
          if (state.filter == HomeFilter.all ||
              state.filter == HomeFilter.offline)
            SliverToBoxAdapter(child: _QuickSongRail(state: state)),
          ..._sections(context, state),
          const SliverToBoxAdapter(child: SizedBox(height: SwissGrid.xl)),
        ],
      ],
    );
  }

  /// Which rails are visible. Every pill owns a **scoped view**: the effect of
  /// a tap has to land above the fold, because a filter whose only change is a
  /// rail three screens down reads as a button that did nothing.
  ///
  /// **Every widget returned here must be a sliver** — that is why rails go
  /// through [SliverRail] and not [SwissRail]. See [SliverRail] for the failure
  /// mode this prevents (`RenderConstrainedBox` is not a `RenderSliver`).
  List<Widget> _sections(BuildContext context, HomeState state) {
    switch (state.filter) {
      case HomeFilter.all:
        return _allSections(context, state);
      case HomeFilter.music:
        return _musicSections(context, state);
      case HomeFilter.spatial:
        return _spatialSections(context, state);
      case HomeFilter.offline:
        return _offlineSections(context, state);
    }
  }

  /// `ALL` — the complete feed, at home in a stream.
  List<Widget> _allSections(BuildContext context, HomeState state) {
    final artists = _extractArtists(state);

    return [
      if (state.mixes.isNotEmpty)
        _rail(
          'MADE FOR YOU',
          [
            for (final mix in state.mixes)
              CollectionRailCard(
                collection: mix,
                onTap: () => openCollection(context, mix),
              ),
          ],
        ),
      if (artists.isNotEmpty)
        _artistRail(context, artists),
      ..._catalogueSections(context, state),
    ];
  }

  /// `MUSIC` — the catalogue, straight up: songs you can play right now, plus
  /// every browse rail. The personal rails (Continue Listening, Daily Mixes,
  /// the quick grid) stay in [HomeFilter.all] so this filter genuinely trims.
  List<Widget> _musicSections(BuildContext context, HomeState state) {
    final player = context.read<PlayerCubit>();
    final songs = state.topSearches.isNotEmpty
        ? state.topSearches
        : state.trending
            .where((item) => item.isTrack)
            .map((item) => item.track!)
            .toList();

    if (songs.isEmpty && !state.feed.hasData) {
      return [
        SliverToBoxAdapter(
          child: MusifyStatePanel(
            index: '',
            title: 'The catalogue is out of reach',
            message: 'Musify could not load any songs. Reconnect and pull to '
                'refresh — everything you downloaded stays playable under '
                'OFFLINE READY.',
            icon: Icons.wifi_off,
            actionLabel: 'RETRY',
            onAction: context.read<HomeCubit>().refresh,
          ),
        ),
      ];
    }

    return [
      _rail(
        'ALL MUSIC',
        [
          for (final track in songs.take(20))
            TrackCard(
              track: track,
              caption: track.displayArtist,
              onTap: () =>
                  player.playTrack(track, context: songs, source: 'ALL MUSIC'),
              onOptions: () => showTrackOptions(context, track, source: 'ALL MUSIC'),
            ),
        ],
      ),
      ..._catalogueSections(context, state),
    ];
  }

  /// `8D SPATIAL PICKS` — the spatial rail first, with the orbit explained and
  /// a switch to arm 8D before choosing a song. If the spatial query comes back
  /// empty, the rail falls back to playable catalogue tracks: every song in the
  /// catalogue can be rendered in 8D, so the filter must never dead-end.
  List<Widget> _spatialSections(BuildContext context, HomeState state) {
    final player = context.read<PlayerCubit>();
    final fallback = <Track>[
      ...state.topSearches,
      ...state.trending.where((item) => item.isTrack).map((item) => item.track!),
    ];
    final picks = Track.dedupe(
      state.spatialPicks.isNotEmpty ? state.spatialPicks : fallback,
    );
    final querying = state.spatialPicks.isEmpty;

    return [
      _rail(
        '8D SPATIAL PICKS',
        [
          for (final track in picks.take(20))
            TrackCard(
              track: track,
              caption: track.displayArtist,
              onTap: () => player.playTrack(track,
                  context: picks, source: '8D SPATIAL'),
              onOptions: () =>
                  showTrackOptions(context, track, source: '8D SPATIAL'),
            ),
        ],
        trailing: const _SpatialArmSwitch(),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: SwissGrid.md)),
      SliverToBoxAdapter(
        child: sectionHeader(
          '',
          'WHAT IS 8D?',
          null,
        ),
      ),
      const SliverToBoxAdapter(child: _SpatialBlurb()),
      if (picks.isNotEmpty && !querying)
        _rail(
          'MORE TO ORBIT',
          [
            for (final item in state.trending.take(12))
              RailItemCard(
                item: item,
                onOpenCollection: (collection) =>
                    openCollection(context, collection),
                onPlayTrack: (raw) => _playRailItem(context, state.trending, raw),
              ),
          ],
        ),
    ];
  }

  /// `OFFLINE READY` — everything playable with the radio off: downloads first.
  List<Widget> _offlineSections(BuildContext context, HomeState state) {
    final player = context.read<PlayerCubit>();
    final downloads = state.downloads;

    if (downloads.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: MusifyStatePanel(
            index: '',
            title: 'Nothing saved offline yet',
            message: 'Tap DOWNLOAD on any track — or DOWNLOAD EVERY TRACK on a '
                'playlist — and it plays here with the network switched off.',
            icon: Icons.offline_pin_outlined,
            actionLabel: 'OPEN LIBRARY',
            onAction: () => context.read<NavigationCubit>().select(AppTab.library),
          ),
        ),
      ];
    }

    return [
      _rail(
        'OFFLINE VAULT',
        [
          for (final track in downloads.take(16))
            TrackCard(
              track: track,
              onTap: () => player.playTrack(track,
                  context: downloads, source: 'OFFLINE VAULT'),
              onOptions: () =>
                  showTrackOptions(context, track, source: 'OFFLINE VAULT'),
            ),
        ],
      ),
    ];
  }

  /// Trending / Charts / New Releases / Genres / Mood Playlists — shared by the
  /// `ALL` and `MUSIC` filters.
  List<Widget> _catalogueSections(
    BuildContext context,
    HomeState state,
  ) {
    return [
      _rail(
        'TRENDING NOW',
        [
          for (final item in state.trending)
            RailItemCard(
              item: item,
              onOpenCollection: (collection) =>
                  openCollection(context, collection),
              onPlayTrack: (raw) => _playRailItem(context, state.trending, raw),
            ),
        ],
      ),
      _rail(
        'TOP CHARTS',
        [
          for (final item in state.charts)
            RailItemCard(
              item: item,
              onOpenCollection: (collection) =>
                  openCollection(context, collection),
              onPlayTrack: (raw) => _playRailItem(context, state.charts, raw),
            ),
        ],
      ),
      _rail(
        'NEW RELEASES',
        [
          for (final item in state.albums)
            RailItemCard(
              item: item,
              onOpenCollection: (collection) =>
                  openCollection(context, collection),
              onPlayTrack: (raw) => _playRailItem(context, state.albums, raw),
            ),
        ],
      ),
      _rail(
        'MOOD PLAYLISTS',
        [
          for (final item in state.playlists)
            RailItemCard(
              item: item,
              onOpenCollection: (collection) =>
                  openCollection(context, collection),
              onPlayTrack: (raw) =>
                  _playRailItem(context, state.playlists, raw),
            ),
        ],
      ),
    ];
  }

  Widget _artistRail(BuildContext context, List<_ArtistItem> artists) {
    return SliverRail(
      index: '',
      title: 'FAVORITE ARTISTS',
      subtitle: null,
      height: 228,
      children: [
        for (final artist in artists)
          _ArtistCircleCard(
            key: ValueKey(artist.name),
            name: artist.name,
            artistId: artist.artistId,
            initialImageUrl: artist.imageUrl,
            onTap: (resolvedPhoto) => openArtist(
              context,
              name: artist.name,
              id: artist.artistId,
              imageUrl: resolvedPhoto,
            ),
          ),
      ],
    );
  }

  List<_ArtistItem> _extractArtists(HomeState state) {
    final artists = <_ArtistItem>[];
    final seen = <String>{};

    void add(String? name, String? artistId, {String? artistImageUrl}) {
      if (name == null) return;
      final clean = name.trim();
      if (clean.isEmpty || clean.toLowerCase() == 'unknown') return;
      final primary = clean.split(',').first.split('&').first.trim();
      if (primary.isEmpty) return;
      final key = primary.toLowerCase();
      if (seen.add(key)) {
        artists.add(_ArtistItem(
          name: primary,
          artistId: artistId,
          imageUrl: artistImageUrl ?? '',
        ));
      }
    }

    // 1. Prioritize collections that are already artist profiles
    for (final item in state.trending) {
      if (item.collection != null &&
          item.collection!.kind == CollectionKind.artist) {
        add(item.collection!.title,
            item.collection!.artistId ?? item.collection!.id,
            artistImageUrl: item.collection!.imageUrl);
      }
    }
    // 2. User listening history (continueListening)
    for (final t in state.continueListening) {
      add(t.artist, t.artistId);
    }
    // 3. User liked songs
    for (final t in state.liked) {
      add(t.artist, t.artistId);
    }
    // 4. Downloads
    for (final t in state.downloads) {
      add(t.artist, t.artistId);
    }
    // 5. Featured hits
    for (final t in state.featuredHits) {
      add(t.artist, t.artistId);
    }
    // 6. Trending tracks
    for (final item in state.trending) {
      if (item.isTrack && item.track != null) {
        add(item.track!.artist, item.track!.artistId);
      }
    }
    // 7. Top searches
    for (final t in state.topSearches) {
      add(t.artist, t.artistId);
    }

    return artists.take(15).toList();
  }

  static Widget _rail(
    String title,
    List<Widget> children, {
    Widget? trailing,
    double? height,
  }) =>
      SliverRail(
        index: '',
        title: title,
        subtitle: null,
        trailing: trailing,
        height: height ?? 252,
        children: children,
      );

  void _playRailItem(BuildContext context, List<RailItem> rail, Object? raw) {
    if (raw is! Track) return;
    final queue = rail.where((r) => r.isTrack).map((r) => r.track!).toList();
    context.read<PlayerCubit>().playTrack(raw, context: queue, source: 'HOME');
  }

  static Widget sectionHeader(String index, String title, String? subtitle) =>
      SectionHeader(index: index, title: title, subtitle: subtitle);
}

class _ArtistItem {
  final String name;
  final String? artistId;
  final String imageUrl;

  const _ArtistItem({
    required this.name,
    this.artistId,
    required this.imageUrl,
  });
}

class _ArtistCircleCard extends StatefulWidget {
  const _ArtistCircleCard({
    required this.name,
    this.artistId,
    this.initialImageUrl = '',
    required this.onTap,
    super.key,
  });

  final String name;
  final String? artistId;
  final String initialImageUrl;
  final ValueChanged<String?> onTap;

  @override
  State<_ArtistCircleCard> createState() => _ArtistCircleCardState();
}

class _ArtistCircleCardState extends State<_ArtistCircleCard> {
  static final Map<String, String> _artistPhotoCache = {};
  String _resolvedUrl = '';

  @override
  void initState() {
    super.initState();
    _resolvePhoto();
  }

  @override
  void didUpdateWidget(_ArtistCircleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) {
      _resolvePhoto();
    }
  }

  void _resolvePhoto() {
    final key = widget.name.toLowerCase().trim();
    if (_artistPhotoCache.containsKey(key)) {
      _resolvedUrl = _artistPhotoCache[key]!;
      return;
    }

    if (widget.initialImageUrl.isNotEmpty) {
      _resolvedUrl = widget.initialImageUrl;
      _artistPhotoCache[key] = widget.initialImageUrl;
      return;
    }

    _resolvedUrl = '';

    Future.microtask(() async {
      try {
        final music = locator<MusicRepository>();
        final portrait = await music.enhancedArtistImage(widget.name);
        if (portrait != null && portrait.isNotEmpty) {
          _artistPhotoCache[key] = portrait;
          if (mounted) setState(() => _resolvedUrl = portrait);
          return;
        }

        final saavn = locator<JioSaavnClient>();
        final results = await saavn.searchArtists(widget.name, limit: 1);
        if (results.isNotEmpty && results.first.imageUrl.isNotEmpty) {
          _artistPhotoCache[key] = results.first.imageUrl;
          if (mounted) setState(() => _resolvedUrl = results.first.imageUrl);
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return SizedBox(
      width: 184,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          widget.onTap(_resolvedUrl.isNotEmpty ? _resolvedUrl : null);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: t.hairline,
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: SwissArtwork(
                  imageUrl: _resolvedUrl,
                  circular: true,
                  size: 176,
                  placeholderIcon: Icons.person_outline,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.name,
              textAlign: TextAlign.center,
              style: SwissType.bodySm.copyWith(
                color: t.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// `8D ON / ENABLE 8D` — arms the spatial engine from the rail itself, so the
/// 8D filter is one tap plus one tap instead of a hunt inside the player.
class _SpatialArmSwitch extends StatelessWidget {
  const _SpatialArmSwitch();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (previous, next) => previous.is8D != next.is8D,
      builder: (context, state) => TactileKeycap(
        height: 30,
        tooltip: state.is8D
            ? 'Turn the 8D orbit off'
            : 'Turn the 8D orbit on for everything you play',
        onPressed: () => context.read<PlayerCubit>().set8D(!state.is8D),
        child: Text(
          state.is8D ? '8D ON' : 'ENABLE 8D',
          style: SwissType.micro.copyWith(
            color: state.is8D
                ? SwissTokens.of(context).accent
                : SwissTokens.of(context).inkMuted,
          ),
        ),
      ),
    );
  }
}

/// Two lines on what the orbit does and what it needs.
class _SpatialBlurb extends StatelessWidget {
  const _SpatialBlurb();

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SwissGrid.gutter,
        SwissGrid.sm,
        SwissGrid.gutter,
        0,
      ),
      child: RecessedWell(
        padding: const EdgeInsets.all(SwissGrid.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '8D RENDERS THE TRACK IN REAL TIME: THE SOUND ORBITS YOUR HEAD, THE '
              'REAR HALF LOW-PASSED AND SOAKED IN REVERB.',
              style: SwissType.micro.copyWith(color: t.inkMuted, height: 1.5),
            ),
            const SizedBox(height: SwissGrid.sm),
            Text(
              'HEADPHONES RECOMMENDED // ORBIT SPEED AND REVERB ARE TUNED IN '
              'SETTINGS ▸ 8D CALIBRATION',
              style: SwissType.micro.copyWith(color: t.inkFaint, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// A wide landscape rectangular card showing the full song poster artwork.
class SongRectangleCard extends StatelessWidget {
  const SongRectangleCard({
    required this.track,
    required this.onTap,
    this.onOptions,
    this.width,
    super.key,
  });

  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onOptions;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final highResUrl = JioSaavnClient.hires(track.imageUrl, size: 500);

    return RepaintBoundary(
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.tap();
            onTap();
          },
          onLongPress: () {
            Haptics.commit();
            onOptions?.call();
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: t.hairline, width: 1.2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Full Crystal-Clear High-Resolution Poster Artwork
                  highResUrl.isEmpty
                      ? Container(
                          color: t.surfaceSunken,
                          child: Center(
                            child: Icon(Icons.music_note, color: t.inkFaint, size: 48),
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: highResUrl,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          fadeInDuration: const Duration(milliseconds: 150),
                          memCacheWidth: 600,
                          memCacheHeight: 800,
                          maxWidthDiskCache: 720,
                          maxHeightDiskCache: 960,
                          placeholder: (context, _) => Container(
                            color: t.surfaceSunken,
                            child: Center(
                              child: Icon(Icons.music_note, color: t.inkFaint, size: 40),
                            ),
                          ),
                          errorWidget: (context, _, __) => Container(
                            color: t.surfaceSunken,
                            child: Center(
                              child: Icon(Icons.music_note, color: t.inkFaint, size: 40),
                            ),
                          ),
                        ),

                // Ambient Gradient Overlay for depth and text legibility
                // Kept clean: Top 45% has 0 tint so artwork is completely clear!
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.45, 0.78, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.35),
                        Colors.black.withValues(alpha: 0.90),
                      ],
                    ),
                  ),
                ),


                // Bottom Strip: Song Title, Artist and Play Pill
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title,
                              style: SwissType.bodySm.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.9),
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              track.displayArtist,
                              style: SwissType.micro.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.9),
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      BlocBuilder<PlayerCubit, PlayerState>(
                        buildWhen: (previous, next) =>
                            previous.track?.id != next.track?.id ||
                            previous.isPlaying != next.isPlaying,
                        builder: (context, playerState) {
                          final player = context.read<PlayerCubit>();
                          final isCurrent = playerState.track?.id == track.id;
                          final isPlaying = isCurrent && playerState.isPlaying;

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Haptics.tap();
                              if (isCurrent) {
                                player.togglePlayPause();
                              } else {
                                onTap();
                              }
                            },
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: t.accent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: t.hairline,
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 22,
                                  color: t.accentInk,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}

/// Auto-sliding wide poster banner carousel showing latest famous songs.
class _QuickSongRail extends StatefulWidget {
  const _QuickSongRail({required this.state});

  final HomeState state;

  @override
  State<_QuickSongRail> createState() => _QuickSongRailState();
}

class _QuickSongRailState extends State<_QuickSongRail> {
  static const int _virtualItemCount = 10000;
  static const Duration _autoSlideDuration = Duration(milliseconds: 3800);

  late final PageController _pageController;
  Timer? _timer;
  int _activePage = 0;
  bool _isUserScrolling = false;

  List<Track> _extractFamousSongs() {
    final songs = <Track>[];
    final seen = <String>{};

    void add(Track? t) {
      if (t == null) return;
      if (t.imageUrl.trim().isEmpty) return;
      if (seen.add(t.dedupeKey)) songs.add(t);
    }

    // 1. Live dynamically fetched latest featured hits from catalogue!
    for (final t in widget.state.featuredHits) {
      add(t);
    }
    // 2. Latest trending catalogue items if tracks
    for (final item in widget.state.trending) {
      if (item.isTrack) add(item.track);
    }
    // 3. Top charts items if tracks
    for (final item in widget.state.charts) {
      if (item.isTrack) add(item.track);
    }
    // 4. Real-time top searches
    for (final t in widget.state.topSearches) {
      add(t);
    }
    // 5. Offline fallback only if songs is still empty
    if (songs.isEmpty) {
      for (final t in widget.state.continueListening) {
        add(t);
      }
      for (final t in widget.state.cachedTracks) {
        add(t);
      }
    }

    return songs.take(20).toList();
  }

  @override
  void initState() {
    super.initState();
    final songs = _extractFamousSongs();
    final initialPage = songs.isNotEmpty
        ? (_virtualItemCount ~/ 2) - ((_virtualItemCount ~/ 2) % songs.length)
        : 0;

    _pageController = PageController(
      viewportFraction: 0.78,
      initialPage: initialPage,
    );
    _activePage = initialPage;
    _startTimer();
  }

  @override
  void didUpdateWidget(_QuickSongRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.featuredHits != widget.state.featuredHits) {
      setState(() {});
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_autoSlideDuration, (_) {
      if (!mounted || _isUserScrolling || !_pageController.hasClients) return;
      final songs = _extractFamousSongs();
      if (songs.length <= 1) return;

      final nextPage = (_pageController.page?.round() ?? _activePage) + 1;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final songs = _extractFamousSongs();

    if (songs.isEmpty) return const SizedBox.shrink();

    final player = context.read<PlayerCubit>();
    final displayIndex = _activePage % songs.length;
    final dotCount = songs.length.clamp(1, 8);

    return Padding(
      padding: const EdgeInsets.only(top: SwissGrid.md, bottom: SwissGrid.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
            child: Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LedDot(active: true, size: 6),
                    const SizedBox(width: 8),
                    Text(
                      'FEATURED HITS',
                      style: SwissType.label.copyWith(
                        color: t.ink,
                        letterSpacing: 1.2,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: SwissGrid.sm),

          // Auto-sliding Taller Poster Carousel
          SizedBox(
            height: 404,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification) {
                  _isUserScrolling = true;
                  _pauseTimer();
                } else if (notification is ScrollEndNotification) {
                  _isUserScrolling = false;
                  _startTimer();
                }
                return false;
              },
              child: PageView.builder(
                controller: _pageController,
                itemCount: songs.length > 1 ? _virtualItemCount : 1,
                onPageChanged: (index) {
                  setState(() {
                    _activePage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final track = songs[index % songs.length];
                  return SongRectangleCard(
                    track: track,
                    onTap: () => player.playTrack(
                      track,
                      context: songs,
                      source: 'FEATURED HITS',
                    ),
                    onOptions: () => showTrackOptions(
                      context,
                      track,
                      source: 'FEATURED HITS',
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Sliding Indicator Dots
          if (songs.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < dotCount; i++) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    width: (displayIndex % dotCount) == i ? 18 : 6,
                    height: 5,
                    decoration: BoxDecoration(
                      color: (displayIndex % dotCount) == i
                          ? t.accent
                          : t.inkFaint.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  if (i != dotCount - 1) const SizedBox(width: 5),
                ],
              ],
            ),
        ],
      ),
    );
  }
}



import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/datasources/jiosaavn_client.dart';
import '../../../data/models/collection.dart';
import '../../../data/models/track.dart';
import '../../../services/service_locator.dart';
import '../../../services/settings_service.dart';
import '../../cubits/home_cubit.dart';
import '../../cubits/navigation_cubit.dart';
import '../../cubits/player_cubit.dart';
import '../../cubits/settings_cubit.dart';
import '../../navigation.dart';
import '../../widgets/collection_cards.dart';
import '../../widgets/screen_header.dart';
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

        return Column(
          children: [
            ScreenHeader(
              tab: AppTab.home,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TactileIconKeycap(
                    icon: SwissTokens.of(context).isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    size: 36,
                    iconSize: 18,
                    ghost: true,
                    tooltip: SwissTokens.of(context).isDark
                        ? 'Switch to Light Theme'
                        : 'Switch to Dark Theme',
                    onPressed: () {
                      final isDark = SwissTokens.of(context).isDark;
                      context.read<SettingsCubit>().setTheme(
                            isDark
                                ? ChassisTheme.alabaster
                                : ChassisTheme.carbon,
                          );
                    },
                  ),
                  const SizedBox(width: 4),
                  TactileIconKeycap(
                    icon: Icons.tune,
                    size: 36,
                    iconSize: 18,
                    ghost: true,
                    tooltip: 'Settings & Equalizer',
                    onPressed: () =>
                        context.read<NavigationCubit>().select(AppTab.settings),
                  ),
                  const SizedBox(width: 4),
                  TactileIconKeycap(
                    icon: Icons.sync,
                    size: 36,
                    iconSize: 18,
                    ghost: true,
                    tooltip: 'Reload the feed',
                    onPressed: state.refreshing
                        ? null
                        : () => context.read<HomeCubit>().refresh(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: SwissTokens.of(context).accent,
                backgroundColor: SwissTokens.of(context).surface,
                onRefresh: () => context.read<HomeCubit>().refresh(),
                child: _Body(state: state, loading: loading),
              ),
            ),
          ],
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
              child: RailSkeleton(count: 3, index: '01', title: 'LOADING')),
          const SliverToBoxAdapter(
              child: RailSkeleton(count: 3, index: '02', title: 'LOADING')),
          const SliverToBoxAdapter(child: _GridSkeleton()),
        ],
        if (!loading) ...[
          if (state.filter == HomeFilter.all ||
              state.filter == HomeFilter.offline)
            SliverToBoxAdapter(child: _QuickGrid(state: state)),
          ..._sections(context, state),
          const SliverToBoxAdapter(child: _AudioOutputStrip()),
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
    final player = context.read<PlayerCubit>();

    return [
      _rail(
        '02',
        'CONTINUE LISTENING',
        'PICKED UP WHERE YOU LEFT OFF',
        [
          for (final track in state.continueListening.take(12))
            TrackCard(
              track: track,
              caption: Fmt.durationShort(track.duration),
              onTap: () => player.playTrack(track,
                  context: state.continueListening,
                  source: 'CONTINUE LISTENING'),
              onOptions: () => showTrackOptions(context, track,
                  source: 'CONTINUE LISTENING'),
            ),
        ],
      ),
      if (state.mixes.isNotEmpty)
        _rail(
          '03',
          'MADE FOR YOU',
          'DAILY MIXES BUILT FROM YOUR HISTORY',
          [
            for (final mix in state.mixes)
              CollectionRailCard(
                collection: mix,
                onTap: () => openCollection(context, mix),
              ),
          ],
        ),
      ..._catalogueSections(context, state, first: state.mixes.isEmpty ? '04' : '05'),
      if (state.cachedTracks.isNotEmpty)
        _rail(
          '09',
          'RECENTLY CACHED',
          'THE ROLLING 500 MB STREAM CACHE',
          [
            for (final track in state.cachedTracks.take(12))
              TrackCard(
                track: track,
                caption: 'CACHED',
                onTap: () => player.playTrack(track,
                    context: state.cachedTracks, source: 'STREAM CACHE'),
                onOptions: () =>
                    showTrackOptions(context, track, source: 'STREAM CACHE'),
              ),
          ],
        ),
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
            index: '00 // NO CATALOGUE',
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
        '01',
        'ALL MUSIC',
        '${songs.length} TRACKS READY TO PLAY',
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
      ..._catalogueSections(context, state, first: '05'),
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
        '01',
        '8D SPATIAL PICKS',
        picks.isEmpty
            ? 'SCANNING THE CATALOGUE…'
            : '${picks.length} PICKS // TAP A SONG, THEN THE 8D KEYCAP',
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
          '02',
          'WHAT IS 8D?',
          querying
              ? 'EVERY TRACK CAN BE RENDERED LIVE'
              : 'THE ORBIT, EXPLAINED',
        ),
      ),
      const SliverToBoxAdapter(child: _SpatialBlurb()),
      if (picks.isNotEmpty && !querying)
        _rail(
          '03',
          'MORE TO ORBIT',
          'THE REST OF THE CATALOGUE',
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

  /// `OFFLINE READY` — everything playable with the radio off: downloads first,
  /// then the rolling cache. With nothing saved yet it explains how to get
  /// there instead of showing two empty rails.
  List<Widget> _offlineSections(BuildContext context, HomeState state) {
    final player = context.read<PlayerCubit>();
    final downloads = state.downloads;
    final cached = state.cachedTracks;

    if (downloads.isEmpty && cached.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: MusifyStatePanel(
            index: '00 // OFFLINE READY',
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
      if (downloads.isNotEmpty)
        _rail(
          '01',
          'OFFLINE VAULT',
          '${downloads.length} TRACKS // 100% ON DEVICE',
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
      if (cached.isNotEmpty)
        _rail(
          '02',
          'RECENTLY CACHED',
          '${cached.length} TRACKS THAT PLAY WITHOUT A NETWORK',
          [
            for (final track in cached.take(16))
              TrackCard(
                track: track,
                onTap: () => player.playTrack(track,
                    context: cached, source: 'STREAM CACHE'),
                onOptions: () =>
                    showTrackOptions(context, track, source: 'STREAM CACHE'),
              ),
          ],
        ),
    ];
  }

  /// Trending / Charts / New Releases / Genres / Mood Playlists — shared by the
  /// `ALL` and `MUSIC` filters. [first] is the ordinal the caller has reached,
  /// so the numbering never repeats across views.
  List<Widget> _catalogueSections(
    BuildContext context,
    HomeState state, {
    required String first,
  }) {
    final start = int.tryParse(first) ?? 5;
    String ord(int offset) => (start + offset).toString().padLeft(2, '0');

    return [
      _rail(
        ord(0),
        'TRENDING NOW',
        'WHAT INDIA IS PLAYING TODAY',
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
        ord(1),
        'TOP CHARTS',
        'THE WEEKLY LADDER',
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
        ord(2),
        'NEW RELEASES',
        'FRESH ALBUMS AND SINGLES',
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
      const SliverToBoxAdapter(child: SizedBox(height: SwissGrid.md)),
      SliverToBoxAdapter(
          child: sectionHeader(ord(3), 'BROWSE GENRES', 'EIGHT CURATED TILES')),
      SliverToBoxAdapter(child: _GenreGrid(genres: state.genres)),
      _rail(
        ord(4),
        'MOOD PLAYLISTS',
        'CURATED BY THE CATALOGUE',
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

  static Widget _rail(
    String index,
    String title,
    String? subtitle,
    List<Widget> children, {
    Widget? trailing,
  }) =>
      SliverRail(
        index: index,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
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

/// The 2×3 quick-access grid: Liked Songs, the Offline Vault and the four most
/// recent collections.
class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    if (state.quickCards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SwissGrid.gutter,
        SwissGrid.lg,
        SwissGrid.gutter,
        SwissGrid.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'JUMP BACK IN',
                style: SwissType.label.copyWith(
                  color: SwissTokens.of(context).ink,
                  letterSpacing: 1.2,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${state.quickCards.length} ITEMS',
                style: SwissType.micro.copyWith(
                  color: SwissTokens.of(context).inkFaint,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: SwissGrid.md),
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.quickCards.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: SwissGrid.sm,
              crossAxisSpacing: SwissGrid.sm,
              mainAxisExtent: 62,
            ),
            itemBuilder: (context, i) =>
                _QuickCardTile(card: state.quickCards[i]),
          ),
        ],
      ),
    );
  }
}

class _QuickCardTile extends StatelessWidget {
  const _QuickCardTile({required this.card});

  final QuickCard card;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        switch (card.kind) {
          case QuickKind.liked:
            openCollection(
              context,
              Collection(
                id: '__liked__',
                title: 'LIKED SONGS',
                kind: CollectionKind.system,
                subtitle: card.subtitle,
                imageUrl: card.imageUrl,
              ),
              tracks: context.read<HomeCubit>().state.liked,
            );
          case QuickKind.downloads:
            openCollection(
              context,
              Collection(
                id: '__downloads__',
                title: 'OFFLINE VAULT',
                kind: CollectionKind.system,
                subtitle: card.subtitle,
                imageUrl: card.imageUrl,
              ),
              tracks: context.read<HomeCubit>().state.downloads,
            );
          case QuickKind.collection:
            final collection = card.collection;
            if (collection != null) openCollection(context, collection);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          border: Border.all(color: t.hairline, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: card.mosaic.isNotEmpty
                        ? MosaicArtwork(urls: card.mosaic, size: 44, radius: 8)
                        : SwissArtwork(imageUrl: card.imageUrl, size: 44, radius: 8),
                  ),
                  if (card.kind == QuickKind.liked)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.accent.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Icon(Icons.favorite, size: 18, color: t.ink),
                        ),
                      ),
                    ),
                  if (card.kind == QuickKind.downloads)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.accent.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Icon(Icons.download_for_offline, size: 18, color: t.ink),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.title,
                    style: SwissType.bodySm.copyWith(
                      color: t.ink,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    card.subtitle,
                    style: SwissType.micro.copyWith(color: t.inkMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioOutputStrip extends StatelessWidget {
  const _AudioOutputStrip();

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SwissGrid.gutter,
        vertical: SwissGrid.sm,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.hairline, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: t.surfaceSunken,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.headphones, size: 18, color: t.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Direct Audio Stream',
                    style: SwissType.bodySm.copyWith(
                      color: t.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Lossless 32-bit / 384kHz · Studio Master',
                    style: SwissType.micro.copyWith(color: t.inkMuted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: t.surfaceSunken,
                borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
                border: Border.all(color: t.hairline),
              ),
              child: Text(
                'DIRECT',
                style: SwissType.micro.copyWith(
                  color: t.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreGrid extends StatelessWidget {
  const _GenreGrid({required this.genres});

  final List<Collection> genres;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(SwissGrid.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SwissSkeleton(height: 11, width: 120),
          const SizedBox(height: SwissGrid.md),
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: SwissGrid.md,
              crossAxisSpacing: SwissGrid.md,
              childAspectRatio: 0.86,
            ),
            itemBuilder: (_, __) => const SwissSkeleton(height: 180),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../data/datasources/jiosaavn_client.dart';
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
        ],
        if (!loading) ...[
          if (state.filter == HomeFilter.all ||
              state.filter == HomeFilter.offline)
            SliverToBoxAdapter(child: _QuickSongRail(state: state)),
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
      if (state.mixes.isNotEmpty)
        _rail(
          '02',
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
      ..._catalogueSections(context, state, first: state.mixes.isEmpty ? '02' : '03'),
      if (state.cachedTracks.isNotEmpty)
        _rail(
          '08',
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
      _rail(
        ord(3),
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

/// A sleek rectangular song card that slides horizontally.
class SongRectangleCard extends StatelessWidget {
  const SongRectangleCard({
    required this.track,
    required this.onTap,
    this.onOptions,
    this.width = 250,
    super.key,
  });

  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onOptions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return SizedBox(
      width: width,
      height: 68,
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.hairline, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SwissArtwork(
                  imageUrl: track.imageUrl,
                  size: 52,
                  radius: 10,
                  placeholderIcon: Icons.music_note,
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
                      track.title,
                      style: SwissType.bodySm.copyWith(
                        color: t.ink,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.displayArtist,
                      style: SwissType.micro.copyWith(
                        color: t.inkMuted,
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: t.surfaceSunken,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.hairline, width: 0.8),
                ),
                child: Center(
                  child: Icon(Icons.play_arrow_rounded, size: 18, color: t.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal sliding rail of rectangular song cards.
class _QuickSongRail extends StatelessWidget {
  const _QuickSongRail({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerCubit>();
    final candidateTracks = state.continueListening.isNotEmpty
        ? state.continueListening
        : (state.topSearches.isNotEmpty
            ? state.topSearches
            : state.trending
                .where((item) => item.isTrack)
                .map((item) => item.track!)
                .toList());

    if (candidateTracks.isEmpty) return const SizedBox.shrink();

    final songs = candidateTracks.take(16).toList();

    return Padding(
      padding: const EdgeInsets.only(top: SwissGrid.md, bottom: SwissGrid.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
            child: Row(
              children: [
                Text(
                  'QUICK PICKS',
                  style: SwissType.label.copyWith(
                    color: SwissTokens.of(context).ink,
                    letterSpacing: 1.2,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  'SLIDE FOR MORE',
                  style: SwissType.micro.copyWith(
                    color: SwissTokens.of(context).accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SwissGrid.sm),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
              itemCount: songs.length,
              separatorBuilder: (_, __) => const SizedBox(width: SwissGrid.sm),
              itemBuilder: (context, i) {
                final track = songs[i];
                return SongRectangleCard(
                  track: track,
                  onTap: () => player.playTrack(
                    track,
                    context: songs,
                    source: 'QUICK PICKS',
                  ),
                  onOptions: () => showTrackOptions(
                    context,
                    track,
                    source: 'QUICK PICKS',
                  ),
                );
              },
            ),
          ),
        ],
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


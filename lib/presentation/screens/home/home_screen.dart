import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
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

    return Container(
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
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
                        filterQuality: FilterQuality.high,
                        fadeInDuration: const Duration(milliseconds: 150),
                        maxWidthDiskCache: 1200,
                        maxHeightDiskCache: 1200,
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

                // Top Badge: Featured Hit Indicator
                Positioned(
                  top: 12,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.60),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_fire_department_rounded, size: 13, color: t.accent),
                        const SizedBox(width: 4),
                        Text(
                          'FEATURED HIT',
                          style: SwissType.micro.copyWith(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
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
                            previous.isPlaying != next.isPlaying ||
                            previous.is8D != next.is8D ||
                            previous.shuffle != next.shuffle,
                        builder: (context, playerState) {
                          final player = context.read<PlayerCubit>();
                          final isCurrent = playerState.track?.id == track.id;
                          final isPlaying = isCurrent && playerState.isPlaying;
                          final is8D = playerState.is8D;
                          final isShuffle = playerState.shuffle;

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Shuffle button
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  Haptics.tap();
                                  player.toggleShuffle();
                                },
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: isShuffle
                                        ? t.accent
                                        : Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isShuffle
                                          ? t.accent
                                          : Colors.white.withValues(alpha: 0.25),
                                      width: 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.shuffle,
                                      size: 16,
                                      color: isShuffle ? t.accentInk : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // 8D Audio button
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  Haptics.commit();
                                  player.set8D(!is8D);
                                },
                                child: Container(
                                  height: 34,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: is8D
                                        ? t.accent
                                        : Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(17),
                                    border: Border.all(
                                      color: is8D
                                          ? t.accent
                                          : Colors.white.withValues(alpha: 0.25),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.surround_sound,
                                        size: 15,
                                        color: is8D ? t.accentInk : Colors.white,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '8D',
                                        style: SwissType.micro.copyWith(
                                          color: is8D ? t.accentInk : Colors.white,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // Flat Clean Play / Pause button (NO GLOW, NO GRADIENT)
                              GestureDetector(
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
                              ),
                            ],
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


import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/collection.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/library_repository.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../services/service_locator.dart';
import '../../cubits/collection_cubit.dart';
import '../../cubits/library_cubit.dart';
import '../../cubits/player_cubit.dart';
import '../../navigation.dart';
import '../../widgets/collection_cards.dart';
import '../../widgets/state_placeholders.dart';
import '../../widgets/swiss_artwork.dart';
import '../../widgets/track_list_tile.dart';
import '../../widgets/track_options_sheet.dart';
import '../../widgets/track_prefetch.dart';

/// Every collection in Musify — album, playlist, chart, mix, genre, artist —
/// plus the two local ones (Liked Songs, Offline Vault), which arrive with their
/// tracks already in hand and never touch the network.
class CollectionDetailScreen extends StatelessWidget {
  const CollectionDetailScreen({
    required this.collection,
    this.tracks,
    super.key,
  });

  final Collection collection;

  /// Non-null turns this screen into a local-only list.
  final List<Track>? tracks;

  @override
  Widget build(BuildContext context) {
    final local = tracks;
    if (local != null) {
      return _LocalCollection(collection: collection, tracks: local);
    }

    return BlocProvider<CollectionCubit>(
      create: (_) => CollectionCubit(
        music: locator<MusicRepository>(),
        library: locator<LibraryRepository>(),
        collection: collection,
      ),
      child: _RemoteCollection(seed: collection),
    );
  }
}

/// Liked Songs and the Offline Vault: the list is already on the device, so the
/// screen is complete on the first frame and refreshes itself whenever the
/// library changes.
class _LocalCollection extends StatelessWidget {
  const _LocalCollection({required this.collection, required this.tracks});

  final Collection collection;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        final live = switch (collection.id) {
          '__liked__' => state.liked,
          '__downloads__' => state.downloads,
          _ => tracks,
        };
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              SwissBackBar(
                  title: collection.title, subtitle: 'LOCAL // ON DEVICE'),
              Expanded(
                child: TrackPrefetch(
                  tracks: live,
                  count: 1,
                  child: _CollectionBody(
                    collection: collection.copyWith(songCount: live.length),
                    tracks: live,
                    local: true,
                    onRefresh: null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RemoteCollection extends StatelessWidget {
  const _RemoteCollection({required this.seed});

  final Collection seed;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CollectionCubit, CollectionState>(
      builder: (context, state) {
        final collection = state.collection ?? seed;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              SwissBackBar(
                title: collection.title,
                subtitle: collection.kindLabel,
              ),
              Expanded(
                child: switch (state.status) {
                  CollectionStatus.loading => const _DetailSkeleton(),
                  CollectionStatus.error => _CollectionBody(
                      collection: collection,
                      tracks: const [],
                      errorText:
                          state.errorText ?? 'COULD NOT LOAD THIS COLLECTION',
                      onRefresh: () => context.read<CollectionCubit>().load(),
                    ),
                  CollectionStatus.empty => _CollectionBody(
                      collection: collection,
                      tracks: const [],
                      errorText: state.errorText ??
                          'NOTHING PLAYABLE IN THIS COLLECTION',
                      onRefresh: () => context.read<CollectionCubit>().load(),
                    ),
                  CollectionStatus.ready => TrackPrefetch(
                      tracks: state.tracks,
                      child: _CollectionBody(
                        collection: collection,
                        tracks: state.tracks,
                        description: state.description,
                        artistBio: state.artistBio,
                        similarArtists: state.similarArtists,
                        onRefresh: () => context.read<CollectionCubit>().load(),
                      ),
                    ),
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Kicks a best-effort cache warm-up for the head of a list the user just
/// opened — see [TrackPrefetch].
class _CollectionBody extends StatelessWidget {
  const _CollectionBody({
    required this.collection,
    required this.tracks,
    this.description,
    this.artistBio,
    this.similarArtists = const [],
    this.errorText,
    this.onRefresh,
    this.local = false,
  });

  final Collection collection;
  final List<Track> tracks;
  final String? description;
  final String? artistBio;
  final List<Collection> similarArtists;
  final String? errorText;
  final VoidCallback? onRefresh;
  final bool local;

  Duration get _total =>
      tracks.fold(Duration.zero, (sum, track) => sum + track.duration);

  int get _downloadedCount => tracks.where((t) => t.isDownloaded).length;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final player = context.read<PlayerCubit>();
    final library = context.read<LibraryCubit>();

    final mosaic = tracks
        .map((track) => track.imageUrl)
        .where((url) => url.isNotEmpty)
        .take(4)
        .toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: SwissGrid.xxl),
      children: [
        // ---------------------------------------------------------- hero plate
        Padding(
          padding: const EdgeInsets.all(SwissGrid.gutter),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                child: collection.imageUrl.isEmpty && mosaic.length > 1
                    ? MosaicArtwork(urls: mosaic, size: 132)
                    : SwissArtwork(
                        imageUrl: collection.imageUrl,
                        size: 132,
                        circular: collection.isRound,
                        placeholderIcon: collection.isRound
                            ? Icons.person_outline
                            : Icons.album_outlined,
                      ),
              ),
              const SizedBox(width: SwissGrid.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      local ? 'ON DEVICE' : collection.kindLabel,
                      style: SwissType.label.copyWith(color: t.accent),
                    ),
                    const SizedBox(height: SwissGrid.xs),
                    Text(
                      collection.title,
                      style: SwissType.displaySm.copyWith(color: t.ink),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (collection.subtitle.isNotEmpty) ...[
                      const SizedBox(height: SwissGrid.xs),
                      Text(
                        collection.subtitle,
                        style: SwissType.bodyXs.copyWith(color: t.inkMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: SwissGrid.sm),
                    ArtworkBadgeRow(
                      children: [
                        SwissBadge(text: '${tracks.length} TRACKS'),
                        if (tracks.isNotEmpty)
                          SwissBadge(text: Fmt.duration(_total)),
                        if (_downloadedCount > 0)
                          SwissBadge(
                              text: '$_downloadedCount OFFLINE',
                              color: t.positive),
                        if (collection.year != null)
                          SwissBadge(text: '${collection.year}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ------------------------------------------------------------ controls
        Padding(
          padding: const EdgeInsets.fromLTRB(
              SwissGrid.gutter, 0, SwissGrid.gutter, SwissGrid.lg),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TactileKeycap(
                      accent: true,
                      glow: true,
                      height: 46,
                      width: double.infinity,
                      onPressed:
                          tracks.isEmpty ? null : () => _playAll(context),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow, size: 19, color: t.accentInk),
                          const SizedBox(width: SwissGrid.sm),
                          Text(
                            'PLAY',
                            style: SwissType.label.copyWith(
                              color: t.accentInk,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: SwissGrid.sm),
                  TactileIconKeycap(
                    icon: Icons.shuffle,
                    size: 46,
                    iconSize: 19,
                    tooltip: 'Shuffle',
                    onPressed: tracks.isEmpty
                        ? null
                        : () => _playAll(context, shuffle: true),
                  ),
                ],
              ),
              const SizedBox(height: SwissGrid.sm),
              Row(
                children: [
                  Expanded(
                    child: TactileKeycap(
                      height: 42,
                      width: double.infinity,
                      enabled: tracks.isNotEmpty,
                      onPressed: () => library.downloadAll(tracks),
                      child: const Text('DOWNLOAD ALL'),
                    ),
                  ),
                  const SizedBox(width: SwissGrid.sm),
                  TactileIconKeycap(
                    icon: Icons.queue_music,
                    size: 42,
                    iconSize: 18,
                    enabled: tracks.isNotEmpty,
                    tooltip: 'Add all to queue',
                    onPressed: () {
                      player.addAllToQueue(tracks);
                      library
                          .showToast('${tracks.length} TRACKS ADDED TO QUEUE');
                    },
                  ),
                  const SizedBox(width: SwissGrid.sm),
                  TactileIconKeycap(
                    icon: Icons.more_vert,
                    size: 42,
                    iconSize: 18,
                    enabled: tracks.isNotEmpty,
                    tooltip: 'Collection options',
                    onPressed: () => _showOptions(context),
                  ),
                ],
              ),
            ],
          ),
        ),

        // --------------------------------------------------------- description
        if ((description ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SwissGrid.gutter, 0, SwissGrid.gutter, SwissGrid.lg),
            child: SwissPanel(
              raised: true,
              padding: const EdgeInsets.all(SwissGrid.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LINER NOTES',
                      style: SwissType.label.copyWith(color: t.inkFaint)),
                  const SizedBox(height: SwissGrid.sm),
                  Text(
                    description!.trim(),
                    style: SwissType.bodySm.copyWith(color: t.inkMuted),
                  ),
                ],
              ),
            ),
          ),

        // ------------------------------------------------------------ tracklist
        if (errorText != null && tracks.isEmpty)
          MusifyStatePanel(
            index: 'ERR // COLLECTION',
            title: 'Nothing to play here',
            message: errorText!,
            icon: Icons.error_outline,
            actionLabel: onRefresh == null ? null : 'RETRY',
            onAction: onRefresh,
          )
        else if (tracks.isEmpty)
          const MusifyStatePanel(
            index: '00 // EMPTY',
            title: 'This collection is empty',
            message:
                'It has no playable renditions right now. Try another tile.',
          )
        else ...[
          SectionHeader(
            index: '01',
            title: 'TRACKLIST',
            subtitle:
                '${tracks.length} TRACKS // ${Fmt.duration(_total)} TOTAL',
            trailing: local
                ? null
                : TactileIconKeycap(
                    icon: Icons.add_to_photos_outlined,
                    size: 30,
                    iconSize: 15,
                    tooltip: 'Add all to a playlist',
                    onPressed: () => _addAllToPlaylist(context),
                  ),
          ),
          for (var i = 0; i < tracks.length; i++)
            TrackListTile(
              track: tracks[i],
              index: i,
              showArtwork: true,
              showDivider: false,
              artworkSize: 48.0,
              isCurrent: player.state.track?.id == tracks[i].id,
              isPlaying: player.state.isPlaying,
              onTap: () => player.playTrack(
                tracks[i],
                context: tracks,
                source: collection.title.toUpperCase(),
              ),
              onOptions: () => showTrackOptions(
                context,
                tracks[i],
                source: collection.title.toUpperCase(),
                queueContext: tracks,
              ),
            ),
        ],

        // ----------------------------------------------------------- artist bio
        if ((artistBio ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SwissGrid.gutter, SwissGrid.lg, SwissGrid.gutter, 0),
            child: SwissPanel(
              raised: true,
              padding: const EdgeInsets.all(SwissGrid.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ARTIST BIO',
                      style: SwissType.label.copyWith(color: t.inkFaint)),
                  const SizedBox(height: SwissGrid.sm),
                  Text(artistBio!.trim(),
                      style: SwissType.bodySm.copyWith(color: t.inkMuted)),
                ],
              ),
            ),
          ),

        if (similarArtists.isNotEmpty)
          SwissRail(
            index: similarArtists.length.toString().padLeft(2, '0'),
            title: 'SIMILAR ARTISTS',
            height: 206,
            children: [
              for (final artist in similarArtists)
                CollectionRailCard(
                  collection: artist,
                  onTap: () => openCollection(context, artist),
                ),
            ],
          ),
      ],
    );
  }

  /// Starts the whole collection. `source` is what the Now Playing header will
  /// show, so it always names the collection rather than the entry point.
  void _playAll(BuildContext context, {bool shuffle = false}) {
    if (tracks.isEmpty) return;
    context.read<PlayerCubit>().playCollection(
          tracks,
          shuffle: shuffle,
          source:
              '${collection.kindLabel} // ${collection.title.toUpperCase()}',
        );
  }

  Future<void> _addAllToPlaylist(BuildContext context) async {
    final library = context.read<LibraryCubit>();
    final playlists = library.state.playlists;
    final name = collection.title.trim().isNotEmpty
        ? collection.title.trim()
        : 'PLAYLIST';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return MusifySheetShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MusifySheetHeader(
                title: 'SAVE AS PLAYLIST',
                subtitle: '${tracks.length} TRACKS',
                trailing: TactileIconKeycap(
                  icon: Icons.close,
                  size: 30,
                  iconSize: 15,
                  hapticOnPress: false,
                  onPressed: () => Navigator.of(sheetContext).maybePop(),
                ),
              ),
              _SheetAction(
                icon: Icons.add,
                label: 'SAVE AS NEW PLAYLIST “$name”',
                onTap: () async {
                  Navigator.of(sheetContext).maybePop();
                  final playlist = await library.createPlaylist(name: name);
                  if (playlist != null) {
                    await library.addAllToPlaylist(playlist.id, tracks);
                  }
                },
              ),
              for (final playlist in playlists)
                _SheetAction(
                  icon: Icons.playlist_add,
                  label: 'ADD ALL TO ${playlist.name.toUpperCase()}',
                  onTap: () async {
                    Navigator.of(sheetContext).maybePop();
                    await library.addAllToPlaylist(playlist.id, tracks);
                  },
                ),
              const SizedBox(height: SwissGrid.sm),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showOptions(BuildContext context) async {
    final collectionUrl = collection.permaUrl;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => MusifySheetShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MusifySheetHeader(
              title: collection.title.toUpperCase(),
              subtitle: '${collection.kindLabel} // ${tracks.length} TRACKS',
              trailing: TactileIconKeycap(
                icon: Icons.close,
                size: 30,
                iconSize: 15,
                hapticOnPress: false,
                onPressed: () => Navigator.of(sheetContext).maybePop(),
              ),
            ),
            _SheetAction(
              icon: Icons.shuffle,
              label: 'SHUFFLE PLAY',
              onTap: () {
                Navigator.of(sheetContext).maybePop();
                _playAll(sheetContext, shuffle: true);
              },
            ),
            _SheetAction(
              icon: Icons.queue_music,
              label: 'ADD ALL TO QUEUE',
              onTap: () {
                Navigator.of(sheetContext).maybePop();
                context.read<PlayerCubit>().addAllToQueue(tracks);
                context
                    .read<LibraryCubit>()
                    .showToast('${tracks.length} TRACKS ADDED TO QUEUE');
              },
            ),
            _SheetAction(
              icon: Icons.download,
              label: 'DOWNLOAD THE WHOLE COLLECTION',
              onTap: () {
                Navigator.of(sheetContext).maybePop();
                context.read<LibraryCubit>().downloadAll(tracks);
              },
            ),
            _SheetAction(
              icon: Icons.playlist_add,
              label: 'SAVE AS A PLAYLIST',
              onTap: () {
                Navigator.of(sheetContext).maybePop();
                _addAllToPlaylist(context);
              },
            ),
            _SheetAction(
              icon: Icons.share_outlined,
              label: 'SHARE COLLECTION LINK',
              onTap: () async {
                Navigator.of(sheetContext).maybePop();
                try {
                  await SharePlus.instance.share(
                    ShareParams(
                      text:
                          '${collection.title}\n${collectionUrl ?? 'https://www.jiosaavn.com'}\n\nshared from Musify',
                      subject: collection.title,
                    ),
                  );
                } catch (_) {
                  // No share target on this device.
                }
              },
            ),
            const SizedBox(height: SwissGrid.sm),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

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
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SwissGrid.lg,
            vertical: SwissGrid.md + 2,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.hairline, width: 1)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: t.ink),
              const SizedBox(width: SwissGrid.md),
              Expanded(
                child: Text(
                  label,
                  style: SwissType.label.copyWith(color: t.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(SwissGrid.gutter),
      children: [
        Row(
          children: [
            const SwissSkeleton(width: 132, height: 132),
            const SizedBox(width: SwissGrid.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SwissSkeleton(height: 10, width: 70),
                  const SizedBox(height: SwissGrid.sm),
                  const SwissSkeleton(height: 22, width: 190),
                  const SizedBox(height: SwissGrid.sm),
                  const SwissSkeleton(height: 10, width: 130),
                  const SizedBox(height: SwissGrid.sm),
                  const SwissSkeleton(height: 16, width: 220),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: SwissGrid.lg),
        const SwissSkeleton(height: 46),
        const SizedBox(height: SwissGrid.lg),
        for (var i = 0; i < 10; i++) ...[
          Row(
            children: [
              const SwissSkeleton(width: 46, height: 46),
              const SizedBox(width: SwissGrid.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwissSkeleton(height: 12, width: 160 + (i % 4) * 30),
                    const SizedBox(height: 6),
                    SwissSkeleton(height: 9, width: 90 + (i % 3) * 25),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SwissGrid.md),
        ],
      ],
    );
  }
}

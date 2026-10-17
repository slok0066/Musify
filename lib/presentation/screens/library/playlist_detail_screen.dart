import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/track.dart';
import '../../../data/models/user_playlist.dart';
import '../../cubits/library_cubit.dart';
import '../../cubits/player_cubit.dart';
import '../../widgets/state_placeholders.dart';
import '../../widgets/swiss_artwork.dart';
import '../../widgets/track_list_tile.dart';
import '../../widgets/track_options_sheet.dart';
import '../../widgets/track_prefetch.dart';

/// A user playlist under the editor.
///
/// The screen holds only an id and reads the live library every frame, so a
/// track added from a sheet, a rename made elsewhere or a download that
/// completes all appear here instantly — with no second source of truth.
class PlaylistDetailScreen extends StatelessWidget {
  const PlaylistDetailScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        UserPlaylist? found;
        for (final candidate in state.playlists) {
          if (candidate.id == playlistId) {
            found = candidate;
            break;
          }
        }
        final playlist = found;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: playlist == null
              ? Column(
                  children: [
                    const SwissBackBar(title: 'PLAYLIST'),
                    Expanded(
                      child: ListView(
                        children: const [
                          MusifyStatePanel(
                            index: '404 // PLAYLIST',
                            title: 'This playlist is gone',
                            message:
                                'It was deleted on this device. Everything else in your '
                                'library is untouched.',
                            icon: Icons.delete_outline,
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : _PlaylistView(playlist: playlist),
        );
      },
    );
  }
}

class _PlaylistView extends StatelessWidget {
  const _PlaylistView({required this.playlist});

  final UserPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final player = context.read<PlayerCubit>();
    final library = context.read<LibraryCubit>();
    final tracks = playlist.tracks;

    return Column(
      children: [
        SwissBackBar(
          title: playlist.name.toUpperCase(),
          subtitle: 'PLAYLIST // ${tracks.length} TRACKS',
          trailing: TactileIconKeycap(
            icon: Icons.more_vert,
            size: 38,
            iconSize: 17,
            tooltip: 'Playlist options',
            onPressed: () => _options(context, tracks),
          ),
        ),
        Expanded(
          child: TrackPrefetch(
            tracks: tracks,
            child: ListView(
              padding: const EdgeInsets.only(bottom: SwissGrid.xxl),
            children: [
              Padding(
                padding: const EdgeInsets.all(SwissGrid.gutter),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 132,
                      height: 132,
                      child: playlist.mosaicArtwork.length > 1
                          ? MosaicArtwork(urls: playlist.mosaicArtwork, size: 132, radius: 16)
                          : playlist.mosaicArtwork.length == 1
                              ? SwissArtwork(
                                  imageUrl: playlist.mosaicArtwork.first,
                                  size: 132,
                                  radius: 16,
                                  placeholderIcon: Icons.queue_music_rounded,
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        t.accent.withValues(alpha: 0.28),
                                        t.surfaceRaised,
                                      ],
                                    ),
                                    border: Border.all(color: t.hairline, width: 1),
                                  ),
                                  child: Center(
                                    child: Icon(Icons.queue_music_rounded,
                                        size: 48, color: t.accent),
                                  ),
                                ),
                    ),
                    const SizedBox(width: SwissGrid.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('YOUR PLAYLIST',
                              style: SwissType.label.copyWith(color: t.accent)),
                          const SizedBox(height: SwissGrid.xs),
                          Text(
                            playlist.name,
                            style: SwissType.displaySm.copyWith(color: t.ink),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (playlist.description.isNotEmpty) ...[
                            const SizedBox(height: SwissGrid.xs),
                            Text(
                              playlist.description,
                              style:
                                  SwissType.micro.copyWith(color: t.inkFaint),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: SwissGrid.sm),
                          ArtworkBadgeRow(
                            children: [
                              SwissBadge(text: '${tracks.length} TRACKS'),
                              if (tracks.isNotEmpty)
                                SwissBadge(
                                    text: Fmt.duration(playlist.totalDuration)),
                              SwissBadge(
                                text:
                                    'UPDATED ${Fmt.compactCount(_ageDays(playlist))}D AGO',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
                            glow: tracks.isNotEmpty,
                            height: 46,
                            width: double.infinity,
                            onPressed: tracks.isEmpty
                                ? null
                                : () => player.playCollection(
                                      tracks,
                                      source:
                                          'PLAYLIST // ${playlist.name.toUpperCase()}',
                                    ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.play_arrow,
                                    size: 19, color: t.accentInk),
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
                          enabled: tracks.isNotEmpty,
                          tooltip: 'Shuffle',
                          onPressed: tracks.isEmpty
                              ? null
                              : () => player.playCollection(
                                    tracks,
                                    shuffle: true,
                                    source:
                                        'PLAYLIST // ${playlist.name.toUpperCase()}',
                                  ),
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
                            child: const Text('MAKE AVAILABLE OFFLINE'),
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
                            library.showToast(
                                '${tracks.length} TRACKS ADDED TO QUEUE');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (tracks.isEmpty)
                const MusifyStatePanel(
                  index: '00 // EMPTY PLAYLIST',
                  title: 'No tracks here yet',
                  message:
                      'Use the ⋮ menu on any song and pick ADD TO PLAYLIST — this list '
                      'and its mosaic cover build themselves.',
                  icon: Icons.playlist_add,
                )
              else ...[
                SectionHeader(
                  index: '01',
                  title: 'TRACKLIST',
                  subtitle: 'HOLD ⋮ ON A ROW TO REORDER, PLAY NEXT OR REMOVE',
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
                      source: 'PLAYLIST // ${playlist.name.toUpperCase()}',
                    ),
                    trailing: TactileIconKeycap(
                      icon: Icons.drag_handle,
                      size: 34,
                      iconSize: 15,
                      hapticOnPress: false,
                      tooltip: 'Row options',
                      onPressed: () => _rowOptions(context, tracks, i),
                    ),
                  ),
              ],
            ],
            ),
          ),
        ),
      ],
    );
  }

  static int _ageDays(UserPlaylist playlist) {
    final days = DateTime.now().difference(playlist.updatedAt).inDays;
    return days < 1 ? 1 : days;
  }

  Future<void> _rowOptions(
      BuildContext context, List<Track> tracks, int index) async {
    final library = context.read<LibraryCubit>();
    final player = context.read<PlayerCubit>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final t = SwissTokens.of(sheetContext);
        return MusifySheetShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MusifySheetHeader(
                title: tracks[index].title.toUpperCase(),
                subtitle: 'ROW ${index + 1} OF ${tracks.length}',
                trailing: TactileIconKeycap(
                  icon: Icons.close,
                  size: 30,
                  iconSize: 15,
                  hapticOnPress: false,
                  onPressed: () => Navigator.of(sheetContext).maybePop(),
                ),
              ),
              _Row(
                icon: Icons.play_arrow,
                label: 'PLAY NOW',
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  player.playTrack(
                    tracks[index],
                    context: tracks,
                    source: 'PLAYLIST // ${playlist.name.toUpperCase()}',
                  );
                },
              ),
              _Row(
                icon: Icons.arrow_upward,
                label: 'MOVE UP',
                enabled: index > 0,
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  library.reorderPlaylist(playlist.id, index, index - 1);
                },
              ),
              _Row(
                icon: Icons.arrow_downward,
                label: 'MOVE DOWN',
                enabled: index < tracks.length - 1,
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  library.reorderPlaylist(playlist.id, index, index + 1);
                },
              ),
              _Row(
                icon: Icons.playlist_play,
                label: 'PLAY NEXT',
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  player.playNext(tracks[index]);
                  library.showToast('QUEUED NEXT');
                },
              ),
              _Row(
                icon: Icons.info_outline,
                label: 'TRACK OPTIONS',
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  showTrackOptions(
                    context,
                    tracks[index],
                    source: 'PLAYLIST // ${playlist.name.toUpperCase()}',
                    queueContext: tracks,
                  );
                },
              ),
              _Row(
                icon: Icons.remove_circle_outline,
                label: 'REMOVE FROM THIS PLAYLIST',
                accent: t.danger,
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  library.removeFromPlaylist(playlist.id, tracks[index].id);
                  library
                      .showToast('REMOVED FROM ${playlist.name.toUpperCase()}');
                },
              ),
              const SizedBox(height: SwissGrid.sm),
            ],
          ),
        );
      },
    );
  }

  Future<void> _options(BuildContext context, List<Track> tracks) async {
    final library = context.read<LibraryCubit>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final t = SwissTokens.of(sheetContext);
        return MusifySheetShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MusifySheetHeader(
                title: playlist.name.toUpperCase(),
                subtitle: '${tracks.length} TRACKS // EDITABLE',
                trailing: TactileIconKeycap(
                  icon: Icons.close,
                  size: 30,
                  iconSize: 15,
                  hapticOnPress: false,
                  onPressed: () => Navigator.of(sheetContext).maybePop(),
                ),
              ),
              _Row(
                icon: Icons.queue_music,
                label: 'ADD ALL TO QUEUE',
                enabled: tracks.isNotEmpty,
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  context.read<PlayerCubit>().addAllToQueue(tracks);
                  library.showToast('${tracks.length} TRACKS ADDED TO QUEUE');
                },
              ),
              _Row(
                icon: Icons.download,
                label: 'MAKE ALL AVAILABLE OFFLINE',
                enabled: tracks.isNotEmpty,
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  library.downloadAll(tracks);
                },
              ),
              _Row(
                icon: Icons.shuffle,
                label: 'SHUFFLE PLAY',
                enabled: tracks.isNotEmpty,
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  context.read<PlayerCubit>().playCollection(
                        tracks,
                        shuffle: true,
                        source: 'PLAYLIST // ${playlist.name.toUpperCase()}',
                      );
                },
              ),
              _Row(
                icon: Icons.delete_outline,
                label: 'DELETE PLAYLIST',
                accent: t.danger,
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  library.deletePlaylist(playlist.id);
                  Navigator.of(context).maybePop();
                },
              ),
              const SizedBox(height: SwissGrid.sm),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final color = enabled ? (accent ?? t.ink) : t.inkFaint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled
            ? () {
                Haptics.tap();
                onTap();
              }
            : null,
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
              Icon(icon, size: 17, color: color),
              const SizedBox(width: SwissGrid.md),
              Expanded(
                child: Text(
                  label,
                  style: SwissType.label.copyWith(color: color),
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

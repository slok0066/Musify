import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';
import '../../data/models/collection.dart';
import '../../data/models/track.dart';
import '../cubits/library_cubit.dart';
import '../cubits/player_cubit.dart';
import '../navigation.dart';
import 'add_to_playlist_sheet.dart';
import 'swiss_artwork.dart';

/// The universal `⋮` sheet from PRD §3.3 — available on every song row, in the
/// Now Playing header, and from the mini-player.
Future<void> showTrackOptions(
  BuildContext context,
  Track track, {
  String? source,
  List<Track>? queueContext,
}) {
  final player = context.read<PlayerCubit>();
  final library = context.read<LibraryCubit>();
  final isCurrent = player.state.track?.id == track.id;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _TrackOptions(
      parentContext: context,
      track: track,
      source: source,
      queueContext: queueContext,
      isCurrent: isCurrent,
      isLiked: library.state.liked.any((t) =>
          t.id == track.id ||
          (t.dedupeKey == track.dedupeKey && track.dedupeKey.isNotEmpty)),
      isDownloaded: library.state.downloads.any((t) => t.id == track.id),
    ),
  );
}

class _TrackOptions extends StatelessWidget {
  const _TrackOptions({
    required this.parentContext,
    required this.track,
    required this.isCurrent,
    required this.isLiked,
    required this.isDownloaded,
    this.source,
    this.queueContext,
  });

  final BuildContext parentContext;
  final Track track;
  final bool isCurrent;
  final bool isLiked;
  final bool isDownloaded;
  final String? source;
  final List<Track>? queueContext;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final player = context.read<PlayerCubit>();
    final library = context.read<LibraryCubit>();

    void close() => Navigator.of(context).maybePop();

    return MusifySheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(track: track),
          Divider(height: 1, color: t.hairline),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Option(
                    icon: Icons.play_arrow,
                    label: isCurrent ? 'RESUME THIS TRACK' : 'PLAY NOW',
                    onTap: () {
                      close();
                      player.playTrack(
                        track,
                        context: queueContext,
                        source: source,
                      );
                    },
                  ),
                  _Option(
                    icon: Icons.playlist_play,
                    label: 'PLAY NEXT',
                    onTap: () {
                      close();
                      player.playNext(track);
                      library.showToast(
                          'QUEUED NEXT // ${track.title.toUpperCase()}');
                    },
                  ),
                  _Option(
                    icon: Icons.queue_music,
                    label: 'ADD TO QUEUE',
                    onTap: () {
                      close();
                      player.addToQueue(track);
                      library.showToast('ADDED TO QUEUE');
                    },
                  ),
                  _Option(
                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                    label: isLiked
                        ? 'REMOVE FROM LIKED SONGS'
                        : 'ADD TO LIKED SONGS',
                    accent: isLiked,
                    onTap: () async {
                      close();
                      await library.toggleLike(track);
                      player.sync();
                    },
                  ),
                  _Option(
                    icon: Icons.playlist_add,
                    label: 'ADD TO PLAYLIST',
                    onTap: () {
                      close();
                      showAddToPlaylist(parentContext, track);
                    },
                  ),
                  _Option(
                    icon: isDownloaded ? Icons.delete_outline : Icons.download,
                    label: isDownloaded
                        ? 'DELETE OFFLINE DOWNLOAD'
                        : 'DOWNLOAD FOR OFFLINE // 320 KBPS',
                    onTap: () {
                      close();
                      if (isDownloaded) {
                        library.deleteDownload(track);
                      } else {
                        library.download(track);
                      }
                    },
                  ),
                  if (track.artist.trim().isNotEmpty)
                    _Option(
                      icon: Icons.person_outline,
                      label: 'GO TO ARTIST',
                      onTap: () {
                        close();
                        openArtist(
                          parentContext,
                          id: track.artistId,
                          name: track.artist,
                          imageUrl: track.imageUrl,
                        );
                      },
                    ),
                  if (track.album.trim().isNotEmpty)
                    _Option(
                      icon: Icons.album_outlined,
                      label: 'GO TO ALBUM',
                      onTap: () {
                        close();
                        openCollection(
                          parentContext,
                          Collection(
                            id: track.albumId ?? track.album,
                            title: track.album,
                            kind: CollectionKind.album,
                            subtitle: track.artist,
                            imageUrl: track.imageUrl,
                          ),
                        );
                      },
                    ),
                  _Option(
                    icon: Icons.share_outlined,
                    label: 'SHARE TRACK LINK',
                    onTap: () {
                      close();
                      _share(track);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _share(Track track) async {
    final url = track.permaUrl ??
        'https://www.jiosaavn.com/song/${Uri.encodeComponent(track.title)}';
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '${track.title} — ${track.artist}\n$url\n\nshared from Musify',
          subject: track.title,
        ),
      );
    } catch (_) {
      // A device without a share target is not an error worth surfacing.
    }
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final color = accent ? t.accent : t.ink;

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
              Icon(icon, size: 17, color: color),
              const SizedBox(width: SwissGrid.md),
              Expanded(
                child: Text(
                  label,
                  style: SwissType.label.copyWith(
                    color: color,
                    letterSpacing: 1.1,
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

/// The header every Musify sheet opens with: artwork, ordinal tag and title.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(SwissGrid.lg),
      child: Row(
        children: [
          SwissArtwork(
              imageUrl: track.imageUrl,
              size: 52,
              placeholderIcon: Icons.music_note),
          const SizedBox(width: SwissGrid.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('TRACK OPTIONS',
                    style: SwissType.micro.copyWith(color: t.accent)),
                const SizedBox(height: 3),
                Text(
                  track.title,
                  style: SwissType.title.copyWith(color: t.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  style: SwissType.bodyXs.copyWith(color: t.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TactileIconKeycap(
            icon: Icons.close,
            size: 32,
            iconSize: 15,
            hapticOnPress: false,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// Shared chrome: Swiss panel, rounded top corners, safe-area bottom padding.
class MusifySheetShell extends StatelessWidget {
  const MusifySheetShell(
      {required this.child, this.maxHeightFactor = 0.86, super.key});

  final Widget child;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final height = MediaQuery.sizeOf(context).height * maxHeightFactor;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height, minWidth: double.infinity),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(32),
          ),
        ),
        child: SafeArea(top: false, child: child),
      ),
    );
  }
}

/// Reusable header for the lyrics / queue / sleep sheets.
class MusifySheetHeader extends StatelessWidget {
  const MusifySheetHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
          SwissGrid.lg, SwissGrid.md, SwissGrid.md, SwissGrid.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.accent,
            ),
          ),
          const SizedBox(width: SwissGrid.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: SwissType.label.copyWith(color: t.ink)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: SwissType.micro.copyWith(color: t.inkFaint),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

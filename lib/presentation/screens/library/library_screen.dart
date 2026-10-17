import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../data/datasources/playlist_importer.dart';
import '../../../data/models/collection.dart';
import '../../../data/models/user_playlist.dart';
import '../../../data/repositories/library_repository.dart';
import '../../cubits/library_cubit.dart';
import '../../cubits/navigation_cubit.dart';
import '../../navigation.dart';
import '../../widgets/collection_cards.dart';
import '../../widgets/import_url_sheet.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/state_placeholders.dart';
import '../../widgets/swiss_artwork.dart';
import '../../widgets/track_options_sheet.dart';

/// `03 // LIBRARY` — everything the listener owns.
///
/// Reads are synchronous, so the list is on screen in the first frame; the
/// importer and the download queue report into the same state object, which is
/// why their progress bars appear inside this screen and nowhere else.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, state) {
        final cubit = context.read<LibraryCubit>();
        final downloadsInFlight = state.inFlight.length;

        return Column(
          children: [
            ScreenHeader(
              tab: AppTab.library,
              subtitle: '${state.entries.length} items • '
                  '${state.liked.length} liked • ${state.downloads.length} offline',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TactileIconKeycap(
                    icon: Icons.add,
                    size: 40,
                    iconSize: 20,
                    tooltip: 'Create new playlist',
                    onPressed: () => _showCreatePlaylistDialog(context),
                  ),
                  const SizedBox(width: SwissGrid.sm),
                  TactileIconKeycap(
                    icon: Icons.link,
                    size: 40,
                    iconSize: 19,
                    tooltip: 'Import playlist',
                    onPressed: () => showImportUrlSheet(context),
                  ),
                  const SizedBox(width: SwissGrid.sm),
                  TactileIconKeycap(
                    icon: state.layout == LibraryLayout.list
                        ? Icons.view_module_outlined
                        : Icons.view_agenda_outlined,
                    size: 40,
                    iconSize: 18,
                    tooltip: state.layout == LibraryLayout.list
                        ? 'Grid view'
                        : 'List view',
                    onPressed: cubit.toggleLayout,
                  ),
                ],
              ),
              actions: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: t.surfaceRaised,
                        borderRadius:
                            BorderRadius.circular(SwissTokens.radiusFull),
                        border: Border.all(color: t.hairline, width: 1),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 16, color: t.inkMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _search,
                              style: SwissType.bodySm.copyWith(color: t.ink),
                              cursorColor: t.accent,
                              onChanged: cubit.setQuery,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                hintText: 'Filter your collection...',
                                hintStyle: SwissType.bodySm
                                    .copyWith(color: t.inkFaint),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: SwissGrid.sm),
                  TactileKeycap(
                    height: 38,
                    onPressed: () => cubit.setSort(_nextSort(state.sort)),
                    tooltip: 'Change sort order',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_sortTag(state.sort)),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_drop_down,
                            size: 14, color: t.inkMuted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (state.importProgress != null)
              _ImportProgressPanel(progress: state.importProgress!),
            if (downloadsInFlight > 0) _DownloadStrip(state: state),
            Expanded(
              child: state.entries.isEmpty
                  ? ListView(
                      children: [
                        MusifyStatePanel(
                          index: '00 // EMPTY LIBRARY',
                          title: _emptyTitle(state.filter),
                          message: state.filter == LibraryFilter.playlists
                              ? 'Tap Create Playlist above or import from YouTube and Spotify.'
                              : 'Like a song, download it for offline, or create a playlist to fill this shelf.',
                          icon: Icons.library_music_outlined,
                          actionLabel: state.filter == LibraryFilter.playlists
                              ? 'CREATE A PLAYLIST'
                              : 'IMPORT A PLAYLIST',
                          onAction: state.filter == LibraryFilter.playlists
                              ? () => _showCreatePlaylistDialog(context)
                              : () => showImportUrlSheet(context),
                        ),
                      ],
                    )
                  : state.layout == LibraryLayout.grid
                      ? _LibraryGrid(state: state)
                      : _LibraryList(state: state),
            ),
          ],
        );
      },
    );
  }

  static String _emptyTitle(LibraryFilter filter) => switch (filter) {
        LibraryFilter.all => 'Nothing saved yet',
        LibraryFilter.playlists => 'No playlists yet',
        LibraryFilter.liked => 'No liked songs yet',
        LibraryFilter.downloaded => 'No downloads yet',
        LibraryFilter.albums => 'No albums yet',
        LibraryFilter.artists => 'No artists yet',
      };

  static LibrarySort _nextSort(LibrarySort sort) => switch (sort) {
        LibrarySort.recentlyPlayed => LibrarySort.recentlyAdded,
        LibrarySort.recentlyAdded => LibrarySort.alphabetical,
        LibrarySort.alphabetical => LibrarySort.recentlyPlayed,
      };

  static String _sortTag(LibrarySort sort) => switch (sort) {
        LibrarySort.recentlyPlayed => 'SORT: PLAYED',
        LibrarySort.recentlyAdded => 'SORT: ADDED',
        LibrarySort.alphabetical => 'SORT: A–Z',
      };
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: SwissGrid.xxl),
      itemCount: state.entries.length,
      itemBuilder: (context, index) => _LibraryRow(entry: state.entries[index]),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(SwissGrid.gutter),
      itemCount: state.entries.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: SwissGrid.md,
        crossAxisSpacing: SwissGrid.md,
        childAspectRatio: 0.84,
      ),
      itemBuilder: (context, index) {
        final entry = state.entries[index];
        return CollectionGridTile(
          title: entry.title,
          subtitle: entry.subtitle,
          imageUrl: entry.imageUrl ?? '',
          mosaic: entry.mosaic,
          round: entry.systemKind == CollectionKind.artist,
          badge: entry.isSystem ? 'SYSTEM' : null,
          onTap: () => _open(context, entry),
        );
      },
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final isLiked = entry.id == '__liked__';
    final isDownloads = entry.id == '__downloads__';
    final isPinned = isLiked || isDownloads;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Haptics.tap();
          _open(context, entry);
        },
        onLongPress: entry.playlist == null
            ? null
            : () {
                Haptics.press();
                _playlistOptions(context, entry.playlist!);
              },
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SwissGrid.gutter,
            vertical: 7,
          ),
          decoration: const BoxDecoration(),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: isLiked
                        ? Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF6366F1),
                                  Color(0xFFA855F7),
                                  Color(0xFFEC4899),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.favorite,
                                  size: 26, color: Colors.white),
                            ),
                          )
                        : isDownloads
                            ? Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: t.surfaceRaised,
                                  border: Border.all(color: t.hairline, width: 1),
                                ),
                                child: Center(
                                  child: Icon(Icons.storage_rounded,
                                      size: 24, color: t.accent),
                                ),
                              )
                            : entry.mosaic.length > 1
                                ? MosaicArtwork(urls: entry.mosaic, size: 58, radius: 12)
                                : SwissArtwork(
                                    imageUrl: entry.imageUrl ?? '',
                                    size: 58,
                                    radius: 12,
                                    circular: entry.systemKind == CollectionKind.artist,
                                    placeholderIcon: Icons.queue_music,
                                  ),
                  ),
                  if (isPinned)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: t.surfaceRaised,
                          shape: BoxShape.circle,
                          border: Border.all(color: t.hairline, width: 1),
                        ),
                        child: Icon(Icons.push_pin, size: 9, color: t.accent),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: SwissGrid.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      style: SwissType.title.copyWith(
                        color: t.ink,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      style: SwissType.bodyXs.copyWith(
                        color: entry.isSystem ? t.inkMuted : t.inkFaint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SwissGrid.sm),
              if (entry.playlist != null)
                IconButton(
                  icon: Icon(Icons.more_vert, size: 18, color: t.inkMuted),
                  splashRadius: 16,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: () => _playlistOptions(context, entry.playlist!),
                )
              else
                Icon(Icons.chevron_right, size: 16, color: t.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the collection behind a library entry. One top-level rule shared by
/// both the grid and the row list, so the two layouts can never diverge.
void _open(BuildContext context, LibraryEntry entry) {
  final library = context.read<LibraryCubit>();
  switch (entry.id) {
    case '__liked__':
      openCollection(
        context,
        Collection(
          id: '__liked__',
          title: 'LIKED SONGS',
          kind: CollectionKind.system,
          subtitle: entry.subtitle,
          imageUrl: entry.imageUrl ?? '',
        ),
        tracks: library.state.liked,
      );
    case '__downloads__':
      openCollection(
        context,
        Collection(
          id: '__downloads__',
          title: 'OFFLINE VAULT',
          kind: CollectionKind.system,
          subtitle: entry.subtitle,
          imageUrl: entry.imageUrl ?? '',
        ),
        tracks: library.state.downloads,
      );
    default:
      if (entry.playlist != null) {
        openUserPlaylist(context, entry.playlist!.id);
        return;
      }
      openCollection(
        context,
        Collection(
          id: entry.id,
          title: entry.title,
          kind: entry.systemKind ?? CollectionKind.system,
          subtitle: entry.subtitle,
          imageUrl: entry.imageUrl ?? '',
          songCount: entry.trackCount,
        ),
      );
  }
}

/// Rename / delete for user playlists — the only two operations a system
/// collection must never expose.
Future<void> _playlistOptions(
    BuildContext context, UserPlaylist playlist) async {
  final id = playlist.id;
  final name = playlist.name;
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
              title: name.toUpperCase(),
              subtitle: 'PLAYLIST // ${playlist.length} TRACKS',
              trailing: TactileIconKeycap(
                icon: Icons.close,
                size: 30,
                iconSize: 15,
                hapticOnPress: false,
                onPressed: () => Navigator.of(sheetContext).maybePop(),
              ),
            ),
            _SheetRow(
              icon: Icons.edit_outlined,
              label: 'RENAME PLAYLIST',
              onTap: () async {
                Navigator.of(sheetContext).maybePop();
                final controller = TextEditingController(text: name);
                final renamed = await showDialog<String>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: t.surface,
                    title: Text('RENAME PLAYLIST',
                        style: SwissType.label.copyWith(color: t.ink)),
                    content: RecessedWell(
                      padding:
                          const EdgeInsets.symmetric(horizontal: SwissGrid.md),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        style: SwissType.body.copyWith(color: t.ink),
                        cursorColor: t.accent,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'PLAYLIST NAME',
                          hintStyle:
                              SwissType.micro.copyWith(color: t.inkFaint),
                        ),
                        onSubmitted: (value) =>
                            Navigator.of(dialogContext).pop(value),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text('CANCEL',
                            style: SwissType.micro.copyWith(color: t.inkMuted)),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(controller.text),
                        child: Text('SAVE',
                            style: SwissType.micro.copyWith(color: t.accent)),
                      ),
                    ],
                  ),
                );
                controller.dispose();
                if (renamed == null || renamed.trim().isEmpty) return;
                await library.renamePlaylist(id, name: renamed);
              },
            ),
            _SheetRow(
              icon: Icons.download,
              label: 'DOWNLOAD EVERY TRACK',
              onTap: () async {
                Navigator.of(sheetContext).maybePop();
                // The sheet is a live view of mutable state: the playlist can
                // disappear (deleted elsewhere, sync) between opening it and
                // tapping. `firstWhere` without `orElse` would throw
                // `StateError: No element` here — a runtime-only crash.
                final matches =
                    library.state.playlists.where((p) => p.id == id);
                if (matches.isEmpty) return;
                await library.downloadAll(matches.first.tracks);
              },
            ),
            _SheetRow(
              icon: Icons.delete_outline,
              label: 'DELETE PLAYLIST',
              accent: t.danger,
              onTap: () async {
                Navigator.of(sheetContext).maybePop();
                await library.deletePlaylist(id);
              },
            ),
            const SizedBox(height: SwissGrid.sm),
          ],
        ),
      );
    },
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final color = accent ?? t.ink;
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

/// Live progress for the URL importer, shown where the playlist will land.
class _ImportProgressPanel extends StatelessWidget {
  const _ImportProgressPanel({required this.progress});

  final ImportProgress progress;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final fraction = progress.fraction;
    final phase = switch (progress.phase) {
      ImportPhase.reading => 'READING THE PLAYLIST PAGE',
      ImportPhase.matching => 'MATCHING AGAINST JIOSAAVN',
      ImportPhase.done => 'COMPLETE',
      ImportPhase.failed => 'FAILED',
    };
    final matched = progress.matched;
    final total = progress.total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SwissGrid.gutter, SwissGrid.md, SwissGrid.gutter, 0),
      child: RecessedWell(
        padding: const EdgeInsets.all(SwissGrid.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LedDot(active: true, size: 6),
                const SizedBox(width: SwissGrid.sm),
                Expanded(
                  child: Text(
                    'IMPORT // $phase',
                    style: SwissType.label.copyWith(color: t.accent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: SwissGrid.sm),
                Text(
                  total > 0 ? '$matched / $total MATCHED' : 'WORKING…',
                  style: SwissType.micro.copyWith(color: t.inkMuted),
                ),
              ],
            ),
            if (progress.current.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                progress.current.toUpperCase(),
                style: SwissType.micro.copyWith(color: t.inkFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: SwissGrid.sm),
            SizedBox(
              height: 4,
              child: Stack(
                children: [
                  const Positioned.fill(
                      child: ColoredBox(color: Colors.black26)),
                  FractionallySizedBox(
                    widthFactor: (fraction ?? 0).clamp(0.0, 1.0),
                    alignment: Alignment.centerLeft,
                    child: ColoredBox(color: t.accent),
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

/// One line per in-flight download — the queue is per-device, so it belongs on
/// the Library screen rather than in a modal.
class _DownloadStrip extends StatelessWidget {
  const _DownloadStrip({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final active = state.inFlight.entries.toList();
    if (active.isEmpty) return const SizedBox.shrink();

    final first = active.first;
    final progress = first.value ?? 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SwissGrid.gutter,
        SwissGrid.sm,
        SwissGrid.gutter,
        SwissGrid.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.hairline),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.sync, size: 16, color: t.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Downloading Offline Vault (${_label(first.key)})',
                    style: SwissType.bodyXs.copyWith(
                      color: t.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: SwissType.micro.copyWith(
                    color: t.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  backgroundColor: t.surfaceSunken,
                  valueColor: AlwaysStoppedAnimation<Color>(t.accent),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${active.length} items in queue',
                  style: SwissType.micro.copyWith(color: t.inkMuted),
                ),
                Text(
                  'Lossless Cache',
                  style: SwissType.micro.copyWith(color: t.inkFaint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _label(String trackId) {
    for (final track in [...state.downloads, ...state.liked, ...state.cached]) {
      if (track.id == trackId) {
        final title = track.title;
        return title.length > 20 ? '${title.substring(0, 20)}…' : title;
      }
    }
    return 'Track';
  }
}

Future<void> _showCreatePlaylistDialog(BuildContext context) async {
  final controller = TextEditingController();
  final library = context.read<LibraryCubit>();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final t = SwissTokens.of(sheetContext);
      final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;

      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: MusifySheetShell(
          maxHeightFactor: 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MusifySheetHeader(
                title: 'CREATE PLAYLIST',
                subtitle: 'NAME YOUR PLAYLIST',
                trailing: TactileIconKeycap(
                  icon: Icons.close,
                  size: 30,
                  iconSize: 15,
                  hapticOnPress: false,
                  onPressed: () => Navigator.of(sheetContext).maybePop(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(SwissGrid.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.surfaceRaised,
                          borderRadius:
                              BorderRadius.circular(SwissTokens.radiusFull),
                          border: Border.all(color: t.accent, width: 1.5),
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: SwissGrid.md),
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          style: SwissType.body.copyWith(color: t.ink),
                          cursorColor: t.accent,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            hintText: 'PLAYLIST NAME',
                            hintStyle:
                                SwissType.micro.copyWith(color: t.inkFaint),
                          ),
                          onSubmitted: (val) async {
                            final name = val.trim();
                            if (name.isEmpty) return;
                            Navigator.of(sheetContext).maybePop();
                            final created =
                                await library.createPlaylist(name: name);
                            if (created != null && context.mounted) {
                              openUserPlaylist(context, created.id);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: SwissGrid.sm),
                    TactileKeycap(
                      accent: true,
                      onPressed: () async {
                        final name = controller.text.trim();
                        if (name.isEmpty) return;
                        Navigator.of(sheetContext).maybePop();
                        final created =
                            await library.createPlaylist(name: name);
                        if (created != null && context.mounted) {
                          openUserPlaylist(context, created.id);
                        }
                      },
                      child: const Text('CREATE'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  controller.dispose();
}

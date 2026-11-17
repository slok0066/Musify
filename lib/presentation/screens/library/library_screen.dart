import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../data/datasources/playlist_importer.dart';
import '../../../data/models/collection.dart';
import '../../../data/models/user_playlist.dart';
import '../../../data/repositories/library_repository.dart';
import '../../cubits/library_cubit.dart';
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
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SwissGrid.gutter,
                  SwissGrid.sm,
                  SwissGrid.gutter,
                  SwissGrid.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---- Clean Header Row -----------------------------------
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Library',
                          style: SwissType.display.copyWith(
                            color: t.ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TactileIconKeycap(
                              icon: Icons.add,
                              size: 38,
                              iconSize: 20,
                              tooltip: 'Create new playlist',
                              onPressed: () => _showCreatePlaylistDialog(context),
                            ),
                            const SizedBox(width: SwissGrid.xs + 2),
                            TactileIconKeycap(
                              icon: Icons.link,
                              size: 38,
                              iconSize: 19,
                              tooltip: 'Import playlist',
                              onPressed: () => showImportUrlSheet(context),
                            ),
                            const SizedBox(width: SwissGrid.xs + 2),
                            TactileIconKeycap(
                              icon: state.layout == LibraryLayout.list
                                  ? Icons.view_module_outlined
                                  : Icons.view_agenda_outlined,
                              size: 38,
                              iconSize: 18,
                              tooltip: state.layout == LibraryLayout.list
                                  ? 'Grid view'
                                  : 'List view',
                              onPressed: cubit.toggleLayout,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // ---- Search & Sort Row ----------------------------------
                    Row(
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
                    const SizedBox(height: 10),
                    // ---- Filter Chips Rail ----------------------------------
                    PillStrip(
                      padding: EdgeInsets.zero,
                      children: [
                        SwissPill(
                          label: 'ALL',
                          selected: state.filter == LibraryFilter.all,
                          dense: true,
                          onTap: () => cubit.setFilter(LibraryFilter.all),
                        ),
                        SwissPill(
                          label: 'PLAYLISTS',
                          selected: state.filter == LibraryFilter.playlists,
                          dense: true,
                          onTap: () => cubit.setFilter(LibraryFilter.playlists),
                        ),
                        SwissPill(
                          label: 'ALBUMS',
                          selected: state.filter == LibraryFilter.albums,
                          dense: true,
                          onTap: () => cubit.setFilter(LibraryFilter.albums),
                        ),
                        SwissPill(
                          label: 'ARTISTS',
                          selected: state.filter == LibraryFilter.artists,
                          dense: true,
                          onTap: () => cubit.setFilter(LibraryFilter.artists),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (state.importProgress != null)
              _ImportProgressPanel(progress: state.importProgress!),
            if (downloadsInFlight > 0) _DownloadStrip(state: state),
            Expanded(
              child: _LibraryBody(state: state),
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

class _LibraryBody extends StatelessWidget {
  const _LibraryBody({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final showPinnedVaults =
        state.filter == LibraryFilter.all && state.query.isEmpty;
    final otherEntries = showPinnedVaults
        ? state.entries
            .where((e) => e.id != '__liked__' && e.id != '__downloads__')
            .toList()
        : state.entries;

    if (state.entries.isEmpty) {
      return ListView(
        children: [
          MusifyStatePanel(
            index: '00 // EMPTY LIBRARY',
            title: _LibraryScreenState._emptyTitle(state.filter),
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
      );
    }

    return CustomScrollView(
      slivers: [
        if (showPinnedVaults)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SwissGrid.gutter,
                SwissGrid.sm,
                SwissGrid.gutter,
                SwissGrid.xs,
              ),
              child: _PinnedVaults(state: state),
            ),
          ),
        if (showPinnedVaults && otherEntries.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SwissGrid.gutter,
                SwissGrid.md,
                SwissGrid.gutter,
                SwissGrid.xs,
              ),
              child: Text(
                'YOUR PLAYLISTS & COLLECTIONS',
                style: SwissType.micro.copyWith(
                  color: t.inkMuted,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (state.layout == LibraryLayout.grid)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              SwissGrid.gutter,
              SwissGrid.xs,
              SwissGrid.gutter,
              SwissGrid.xxl,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: SwissGrid.md,
                crossAxisSpacing: SwissGrid.md,
                childAspectRatio: 0.84,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = otherEntries[index];
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
                childCount: otherEntries.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: SwissGrid.xxl),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _LibraryRow(entry: otherEntries[index]),
                childCount: otherEntries.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _PinnedVaults extends StatelessWidget {
  const _PinnedVaults({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return Row(
      children: [
        // Liked Songs Vault Card
        Expanded(
          child: _VaultCard(
            title: 'Liked Songs',
            subtitle: '${state.liked.length} songs',
            badge: 'PINNED',
            badgeColor: t.inkMuted,
            icon: Icons.favorite,
            accentColor: const Color(0xFFFF4D4D),
            onTap: () {
              Haptics.tap();
              openCollection(
                context,
                Collection(
                  id: '__liked__',
                  title: 'LIKED SONGS',
                  kind: CollectionKind.system,
                  subtitle: '${state.liked.length} TRACKS',
                  imageUrl:
                      state.liked.isNotEmpty ? state.liked.first.imageUrl : '',
                ),
                tracks: state.liked,
              );
            },
          ),
        ),
        const SizedBox(width: SwissGrid.sm),
        // Offline Vault Card
        Expanded(
          child: _VaultCard(
            title: 'Offline Vault',
            subtitle: '${state.downloads.length} songs',
            badge: 'OFFLINE',
            badgeColor: const Color(0xFF38BDF8),
            icon: Icons.storage_rounded,
            accentColor: const Color(0xFF38BDF8),
            onTap: () {
              Haptics.tap();
              openCollection(
                context,
                Collection(
                  id: '__downloads__',
                  title: 'OFFLINE VAULT',
                  kind: CollectionKind.system,
                  subtitle: '${state.downloads.length} TRACKS',
                  imageUrl: state.downloads.isNotEmpty
                      ? state.downloads.first.imageUrl
                      : '',
                ),
                tracks: state.downloads,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VaultCard extends StatelessWidget {
  const _VaultCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.hairline, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Icon(icon, size: 18, color: accentColor),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: t.hairline, width: 1),
                    ),
                    child: Text(
                      badge,
                      style: SwissType.micro.copyWith(
                        color: badgeColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: SwissType.title.copyWith(
                  color: t.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: SwissType.bodyXs.copyWith(color: t.inkFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
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
                              color: const Color(0xFFFF4D4D)
                                  .withValues(alpha: 0.12),
                              border: Border.all(
                                color: const Color(0xFFFF4D4D)
                                    .withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.favorite,
                                  size: 24, color: Color(0xFFFF4D4D)),
                            ),
                          )
                        : isDownloads
                            ? Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: const Color(0xFF38BDF8)
                                      .withValues(alpha: 0.12),
                                  border: Border.all(
                                    color: const Color(0xFF38BDF8)
                                        .withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(Icons.storage_rounded,
                                      size: 24, color: Color(0xFF38BDF8)),
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

typedef _SheetRow = SwissSheetActionTile;

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

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';
import '../../data/datasources/playlist_importer.dart';
import '../../data/models/user_playlist.dart';
import '../cubits/library_cubit.dart';
import 'track_options_sheet.dart';

/// "Import a playlist from a link" — the Library screen's one remote write.
///
/// The sheet reads the public playlist page for **metadata only** (titles and
/// artists, no credentials and no audio), re-matches every entry against
/// JioSaavn, and then hands the result to the user: save it as a new playlist,
/// or file it into one they already own. Progress is reported live, because a
/// 200-track import takes a while and a dead sheet would look like a hang.
Future<void> showImportUrlSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ImportUrlSheet(),
  );
}

class _ImportUrlSheet extends StatefulWidget {
  const _ImportUrlSheet();

  @override
  State<_ImportUrlSheet> createState() => _ImportUrlSheetState();
}

class _ImportUrlSheetState extends State<_ImportUrlSheet> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _name = TextEditingController();

  /// True once the scan has produced a [PendingImport]; the next time the
  /// pending value goes away the user committed (or discarded) and the sheet
  /// can close itself.
  bool _pendingSeen = false;

  /// The suggestion the name field was last seeded from, so the user's own
  /// edits are never overwritten by a rebuild.
  String? _seededFor;

  @override
  void dispose() {
    _controller.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return BlocConsumer<LibraryCubit, LibraryState>(
      listenWhen: (previous, next) =>
          next.importProgress != previous.importProgress ||
          next.pendingImport != previous.pendingImport,
      listener: (context, state) {
        final pending = state.pendingImport;
        if (pending != null) {
          _pendingSeen = true;
          if (_seededFor != pending.name) {
            _seededFor = pending.name;
            _name.text = pending.name;
          }
          return;
        }
        if (_pendingSeen) {
          _pendingSeen = false;
          Navigator.of(context).maybePop();
        }
      },
      builder: (context, state) {
        final progress = state.importProgress;
        final pending = state.pendingImport;

        return Padding(
          padding: EdgeInsets.only(bottom: insets),
          child: MusifySheetShell(
            maxHeightFactor: 0.92,
            child: pending != null
                ? _Destination(
                    pending: pending,
                    playlists: state.playlists,
                    nameController: _name,
                  )
                : _UrlForm(
                    controller: _controller,
                    progress: progress,
                    busy: progress != null,
                    onImport: _scan,
                  ),
          ),
        );
      },
    );
  }

  void _scan() {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    if (context.read<LibraryCubit>().state.importing) return;
    FocusScope.of(context).unfocus();
    context.read<LibraryCubit>().scanPlaylist(url);
  }
}

// ---------------------------------------------------------------- phase 1 & 2

class _UrlForm extends StatelessWidget {
  const _UrlForm({
    required this.controller,
    required this.progress,
    required this.busy,
    required this.onImport,
  });

  final TextEditingController controller;
  final ImportProgress? progress;
  final bool busy;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MusifySheetHeader(
          title: 'IMPORT PLAYLIST',
          subtitle: 'YOUTUBE · SPOTIFY · PUBLIC LINKS',
          trailing: TactileIconKeycap(
            icon: Icons.close,
            size: 30,
            iconSize: 15,
            hapticOnPress: false,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(SwissGrid.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PASTE A PLAYLIST URL',
                style: SwissType.label.copyWith(color: t.inkFaint),
              ),
              const SizedBox(height: SwissGrid.sm),
              Container(
                decoration: BoxDecoration(
                  color: t.surfaceRaised,
                  borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
                  border: Border.all(color: t.hairline, width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: SwissGrid.md),
                child: TextField(
                  controller: controller,
                  enabled: !busy,
                  autofocus: true,
                  style: SwissType.body.copyWith(color: t.ink),
                  cursorColor: t.accent,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => onImport(),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: SwissGrid.md),
                    hintText: 'https://www.youtube.com/playlist?list=…',
                    hintStyle: SwissType.micro.copyWith(color: t.inkFaint),
                  ),
                ),
              ),
              const SizedBox(height: SwissGrid.md),
              TactileKeycap(
                accent: true,
                glow: !busy,
                height: 46,
                width: double.infinity,
                enabled: !busy,
                onPressed: busy ? null : onImport,
                child: Text(busy ? 'SCANNING…' : 'SCAN THE PLAYLIST'),
              ),
              if (progress != null) ...[
                const SizedBox(height: SwissGrid.md),
                _Progress(progress: progress!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- phase 3

/// The scan result, parked until the user says where it goes.
class _Destination extends StatelessWidget {
  const _Destination({
    required this.pending,
    required this.playlists,
    required this.nameController,
  });

  final PendingImport pending;
  final List<UserPlaylist> playlists;
  final TextEditingController nameController;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final cubit = context.read<LibraryCubit>();
    final preview = pending.tracks.take(4).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MusifySheetHeader(
          title: 'WHERE SHOULD IT GO?',
          subtitle: pending.summary,
          trailing: TactileIconKeycap(
            icon: Icons.close,
            size: 30,
            iconSize: 15,
            hapticOnPress: false,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              SwissGrid.lg,
              0,
              SwissGrid.lg,
              SwissGrid.lg,
            ),
            shrinkWrap: true,
            children: [
              // What the scan actually found — the reassurance that "23
              // matched" is 23 real songs and not an empty list with a number.
              SwissPanel(
                raised: true,
                padding: const EdgeInsets.all(SwissGrid.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MATCHED ON JIOSAAVN // 320 KBPS AAC',
                      style: SwissType.micro.copyWith(color: t.accent),
                    ),
                    const SizedBox(height: SwissGrid.sm),
                    for (final track in preview)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '${track.title} — ${track.displayArtist}'.toUpperCase(),
                          style:
                              SwissType.micro.copyWith(color: t.inkMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (pending.tracks.length > preview.length)
                      Text(
                        '+ ${pending.tracks.length - preview.length} MORE',
                        style: SwissType.micro.copyWith(color: t.inkFaint),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: SwissGrid.lg),

              Text(
                'SAVE AS A NEW PLAYLIST',
                style: SwissType.label.copyWith(color: t.inkFaint),
              ),
              const SizedBox(height: SwissGrid.sm),
              Container(
                decoration: BoxDecoration(
                  color: t.surfaceRaised,
                  borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
                  border: Border.all(color: t.hairline, width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: SwissGrid.md),
                child: TextField(
                  controller: nameController,
                  style: SwissType.body.copyWith(color: t.ink),
                  cursorColor: t.accent,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) => cubit.commitPendingAsPlaylist(value),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: SwissGrid.md),
                    hintText: 'PLAYLIST NAME',
                    hintStyle: SwissType.micro.copyWith(color: t.inkFaint),
                  ),
                ),
              ),
              const SizedBox(height: SwissGrid.sm),
              TactileKeycap(
                accent: true,
                glow: true,
                height: 44,
                width: double.infinity,
                onPressed: () => cubit.commitPendingAsPlaylist(nameController.text),
                child: Text('SAVE // ${pending.tracks.length} TRACKS'),
              ),
              const SizedBox(height: SwissGrid.lg),

              if (playlists.isEmpty)
                Text(
                  'YOU HAVE NO OTHER PLAYLISTS YET — SAVE THIS ONE, OR CREATE ONE '
                  'FROM ANY TRACK MENU FIRST.',
                  style: SwissType.micro.copyWith(color: t.inkFaint, height: 1.5),
                )
              else ...[
                Text(
                  'OR ADD ALL ${pending.tracks.length} TRACKS TO',
                  style: SwissType.label.copyWith(color: t.inkFaint),
                ),
                const SizedBox(height: SwissGrid.sm),
                for (final playlist in playlists)
                  _PlaylistRow(
                    playlist: playlist,
                    onTap: () => cubit.commitPendingIntoPlaylist(playlist.id),
                  ),
              ],
              const SizedBox(height: SwissGrid.md),
              Center(
                child: TextButton(
                  onPressed: cubit.discardPendingImport,
                  child: Text(
                    'DISCARD THIS IMPORT',
                    style: SwissType.micro.copyWith(color: t.inkMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist, required this.onTap});

  final UserPlaylist playlist;
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
          padding: const EdgeInsets.symmetric(vertical: SwissGrid.md),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.hairline, width: 1)),
          ),
          child: Row(
            children: [
              Icon(Icons.queue_music, size: 16, color: t.inkMuted),
              const SizedBox(width: SwissGrid.md),
              Expanded(
                child: Text(
                  playlist.name.toUpperCase(),
                  style: SwissType.label.copyWith(color: t.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: SwissGrid.sm),
              Text(
                '${playlist.length} TRACKS',
                style: SwissType.micro.copyWith(color: t.inkFaint),
              ),
              const SizedBox(width: SwissGrid.sm),
              Icon(Icons.add, size: 16, color: t.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.progress});

  final ImportProgress progress;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final fraction = progress.fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 4,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.black26)),
              FractionallySizedBox(
                widthFactor: (fraction ?? 0).clamp(0.0, 1.0),
                alignment: Alignment.centerLeft,
                child: ColoredBox(color: t.accent),
              ),
            ],
          ),
        ),
        const SizedBox(height: SwissGrid.sm),
        Text(
          progress.current.isEmpty
              ? 'READING THE PLAYLIST PAGE…'
              : '${progress.matched} OF ${progress.total} MATCHED // ${progress.current.toUpperCase()}',
          style: SwissType.micro.copyWith(color: t.inkMuted),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

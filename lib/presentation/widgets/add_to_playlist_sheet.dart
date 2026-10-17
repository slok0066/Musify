import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';
import '../../data/models/track.dart';
import '../../data/models/user_playlist.dart';
import '../cubits/library_cubit.dart';
import 'swiss_artwork.dart';
import 'track_options_sheet.dart';

/// The "Add to Custom Playlist…" picker from the track context menu.
Future<void> showAddToPlaylist(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddToPlaylist(track: track),
  );
}

class _AddToPlaylist extends StatefulWidget {
  const _AddToPlaylist({required this.track});

  final Track track;

  @override
  State<_AddToPlaylist> createState() => _AddToPlaylistState();
}

class _AddToPlaylistState extends State<_AddToPlaylist> {
  bool _creating = false;
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final library = context.watch<LibraryCubit>();
    final playlists = library.state.playlists;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: MusifySheetShell(
        maxHeightFactor: 0.85,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MusifySheetHeader(
              title: _creating ? 'CREATE PLAYLIST' : 'ADD TO PLAYLIST',
              subtitle: widget.track.title.toUpperCase(),
              trailing: TactileIconKeycap(
                icon: _creating ? Icons.arrow_back : Icons.close,
                size: 30,
                iconSize: 15,
                hapticOnPress: false,
                onPressed: () {
                  if (_creating) {
                    setState(() => _creating = false);
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
            ),
          if (_creating)
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
                        border: Border.all(color: t.hairline, width: 1),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: SwissGrid.md),
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        style: SwissType.body.copyWith(color: t.ink),
                        cursorColor: t.accent,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'PLAYLIST NAME',
                          hintStyle: SwissType.micro.copyWith(color: t.inkFaint),
                        ),
                        onSubmitted: (_) => _create(),
                      ),
                    ),
                  ),
                  const SizedBox(width: SwissGrid.sm),
                  TactileKeycap(
                    accent: true,
                    onPressed: _create,
                    child: const Text('CREATE'),
                  ),
                ],
              ),
            )
          else ...[
            _Entry(
              icon: Icons.add,
              label: 'NEW PLAYLIST',
              onTap: () => setState(() => _creating = true),
            ),
            _Entry(
              icon: Icons.favorite,
              label: 'LIKED SONGS',
              onTap: () async {
                final library = context.read<LibraryCubit>();
                final nav = Navigator.of(context);
                await library.like(widget.track);
                if (mounted) nav.maybePop();
              },
            ),
          ],
          if (playlists.isEmpty && !_creating)
            Padding(
              padding: const EdgeInsets.all(SwissGrid.xl),
              child: Text(
                'NO PLAYLISTS YET — CREATE ONE ABOVE',
                style: SwissType.micro.copyWith(color: t.inkFaint),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return _PlaylistRow(
                    playlist: playlist,
                    onTap: () => _add(playlist),
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}

  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final library = context.read<LibraryCubit>();
    final playlist = await library.createPlaylist(name: name);
    if (playlist == null || !mounted) return;
    await _add(playlist);
  }

  Future<void> _add(UserPlaylist playlist) async {
    final library = context.read<LibraryCubit>();
    await library.addToPlaylist(playlist.id, widget.track);
    if (mounted) Navigator.of(context).maybePop();
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.icon, required this.label, required this.onTap});

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
              Icon(icon, size: 17, color: t.accent),
              const SizedBox(width: SwissGrid.md),
              Text(label, style: SwissType.label.copyWith(color: t.ink)),
            ],
          ),
        ),
      ),
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
          padding: const EdgeInsets.symmetric(
            horizontal: SwissGrid.lg,
            vertical: SwissGrid.md,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.hairline, width: 1)),
          ),
          child: Row(
            children: [
              MosaicArtwork(urls: playlist.mosaicArtwork, size: 40),
              const SizedBox(width: SwissGrid.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      playlist.name.toUpperCase(),
                      style: SwissType.title.copyWith(color: t.ink, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${playlist.length} TRACKS',
                      style: SwissType.micro.copyWith(color: t.inkFaint),
                    ),
                  ],
                ),
              ),
              Icon(Icons.add, size: 17, color: t.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

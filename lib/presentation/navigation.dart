import 'package:flutter/material.dart';

import '../data/models/collection.dart';
import '../data/models/track.dart';
import 'screens/collection/collection_detail_screen.dart';
import 'screens/library/playlist_detail_screen.dart';
import 'screens/now_playing/now_playing_screen.dart';

/// One place where routes are pushed, so every entry point into a detail screen
/// looks and behaves identically (and no screen has to know about the others).
///
/// Detail screens are pushed on the *nearest* navigator — inside the shell's
/// chassis — so the mini-player and the tab bar stay on screen while the user
/// browses. The full-screen Now Playing route is the one exception: it is
/// pushed on the root navigator so it covers the chassis, exactly like a
/// player should.

void openNowPlaying(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const NowPlayingScreen(),
      transitionsBuilder: (_, animation, __, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
  );
}

/// Albums, playlists, charts, mixes and genres.
///
/// [tracks] turns the screen into a local-only list (Liked Songs, the Offline
/// Vault): nothing is fetched, the tracks come straight from the library.
void openCollection(
  BuildContext context,
  Collection collection, {
  List<Track>? tracks,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          CollectionDetailScreen(collection: collection, tracks: tracks),
    ),
  );
}

/// A user playlist, by id — the editor reads the live library each frame.
void openUserPlaylist(BuildContext context, String playlistId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlaylistDetailScreen(playlistId: playlistId),
    ),
  );
}

/// An artist profile. The catalogue id may be unknown (library-derived
/// artists), in which case the name is used as a search seed.
void openArtist(
  BuildContext context, {
  String? id,
  required String name,
  String? imageUrl,
}) {
  openCollection(
    context,
    Collection(
      id: id ?? name,
      title: name,
      kind: CollectionKind.artist,
      imageUrl: imageUrl ?? '',
      artistId: id,
    ),
  );
}

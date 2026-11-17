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
  // "Remove animations" gets an instant route: the cover still lands in place,
  // there is just no flight to sit through.
  final instant = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      transitionDuration:
          instant ? Duration.zero : const Duration(milliseconds: 420),
      reverseTransitionDuration:
          instant ? Duration.zero : const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => const NowPlayingScreen(),
      transitionsBuilder: (_, animation, __, child) {
        // The cover hero carries the motion; the page only settles in behind
        // it, so the eye follows one object instead of two competing slides.
        final rise = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.05, 0.7, curve: Curves.easeOut),
            reverseCurve: const Interval(0.35, 1, curve: Curves.easeIn),
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(rise),
            child: child,
          ),
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

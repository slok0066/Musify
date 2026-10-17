import 'package:flutter/material.dart';

import '../../data/models/track.dart';
import '../../data/repositories/music_repository.dart';
import '../../services/service_locator.dart';

/// Warms the cache for the head of a list the user has just opened, so the tap
/// that follows starts in milliseconds instead of a full download.
///
/// Why this exists: `flutter_soloud` stages a remote URL by fetching the whole
/// file, and JioSaavn's 320 kbps renditions are ~10 MB, so the very first tap of
/// a session used to sit on `BUFFERING` for 10–15 seconds. Downloading the first
/// one or two entries of a list *while the user reads it* moves that wait
/// off-screen, where nobody is watching it.
///
/// The warm-up runs after the first frame, never blocks a build, and asks for
/// nothing when the device is offline or the track is already on disk.
class TrackPrefetch extends StatefulWidget {
  const TrackPrefetch({
    required this.tracks,
    required this.child,
    this.count = 2,
    super.key,
  });

  final List<Track> tracks;
  final Widget child;

  /// How many entries to warm. Deliberately small: this spends the user's data.
  final int count;

  @override
  State<TrackPrefetch> createState() => _TrackPrefetchState();
}

class _TrackPrefetchState extends State<TrackPrefetch> {
  String _warmed = '';

  @override
  void initState() {
    super.initState();
    _warm();
  }

  @override
  void didUpdateWidget(covariant TrackPrefetch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tracks, widget.tracks)) _warm();
  }

  void _warm() {
    final tracks = widget.tracks;
    if (tracks.isEmpty) return;
    final signature =
        tracks.take(widget.count).map((track) => track.id).join('|');
    if (signature.isEmpty || signature == _warmed) return;
    _warmed = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      locator<MusicRepository>().prefetchTracks(tracks, count: widget.count);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

import '../../../core/artwork_url.dart';
import '../../../core/theme/swiss_tokens.dart';
import '../../../core/theme/tactile_decorations.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../services/service_locator.dart';
import '../../cubits/library_cubit.dart';
import '../../cubits/player_cubit.dart';
import '../../cubits/settings_cubit.dart';
import '../../widgets/artwork_color.dart';
import '../../widgets/eight_d_calibration_sheet.dart';
import '../../widgets/swiss_artwork.dart';
import '../../widgets/tactile_slider.dart';
import '../../widgets/track_options_sheet.dart';
import 'lyrics_bottom_sheet.dart';
import 'queue_bottom_sheet.dart';
import 'sleep_timer_sheet.dart';

/// The instrument face, in the house order: artwork, identity, the spatial
/// engine telemetry, the seek readout and the transport.
///
/// The screen deliberately rebuilds on *identity* changes only — position ticks
/// reach the seekbar through a nested builder, so a 250 ms timer repaints a
/// 28 px band instead of the whole route.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SwissTokens.of(context).bg,
      body: BlocBuilder<PlayerCubit, PlayerState>(
        buildWhen: (previous, next) =>
            previous.track?.id != next.track?.id ||
            previous.track?.imageUrl != next.track?.imageUrl ||
            previous.isPlaying != next.isPlaying ||
            previous.is8D != next.is8D ||
            previous.shuffle != next.shuffle ||
            previous.repeat != next.repeat ||
            previous.liked != next.liked ||
            previous.downloaded != next.downloaded ||
            previous.downloadProgress != next.downloadProgress ||
            previous.headphones != next.headphones ||
            previous.sleepRemaining != next.sleepRemaining ||
            previous.errorText != next.errorText,
        builder: (context, state) {
          final track = state.track;
          if (track == null) {
            return SafeArea(
              child: Column(
                children: [
                  const _TopBar(),
                  Expanded(
                    child: Center(
                      child: Text(
                        'NOTHING LOADED // PICK A TRACK',
                        style: SwissType.label
                            .copyWith(color: SwissTokens.of(context).inkFaint),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return _Face(state: state);
        },
      ),
    );
  }
}

class _Face extends StatefulWidget {
  const _Face({required this.state});

  final PlayerState state;

  @override
  State<_Face> createState() => _FaceState();
}

class _FaceState extends State<_Face> with WidgetsBindingObserver {
  VideoPlayerController? _videoController;
  String? _loadedTrackId;
  bool _canvasVisible = true;
  bool _loadingVideo = false;
  bool _hasCanvas = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final track = widget.state.track;
    if (track != null) {
      _loadCanvas(track);
    }
  }

  @override
  void didUpdateWidget(_Face oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentTrack = widget.state.track;
    final oldTrack = oldWidget.state.track;

    if (currentTrack?.id != oldTrack?.id) {
      _disposeVideo();
      if (currentTrack != null) {
        _loadCanvas(currentTrack);
      }
    } else if (widget.state.isPlaying != oldWidget.state.isPlaying) {
      if (widget.state.isPlaying && _canvasVisible) {
        _videoController?.play();
      } else {
        _videoController?.pause();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      if (widget.state.isPlaying &&
          _canvasVisible &&
          _videoController?.value.isInitialized == true) {
        _videoController?.play();
      }
    } else {
      _videoController?.pause();
    }
  }

  void _onVideoTick() {
    if (!mounted) return;
    final controller = _videoController;
    if (controller == null) return;

    // Gracefully fallback to album artwork on decoder errors
    if (controller.value.hasError) {
      debugPrint('[CANVAS-UI] Video player error: ${controller.value.errorDescription}');
      if (_hasCanvas) {
        setState(() {
          _hasCanvas = false;
        });
      }
      return;
    }

    // Auto-resume video if audio is running, canvas is turned on, but video stalled/paused
    if (widget.state.isPlaying &&
        _canvasVisible &&
        controller.value.isInitialized &&
        !controller.value.isPlaying &&
        !controller.value.isBuffering) {
      controller.play();
    }
  }

  void _toggleCanvas() {
    Haptics.tap();
    setState(() {
      _canvasVisible = !_canvasVisible;
    });
    if (_canvasVisible) {
      if (widget.state.isPlaying &&
          _videoController?.value.isInitialized == true) {
        _videoController?.play();
      }
    } else {
      _videoController?.pause();
    }
  }

  Future<void> _loadCanvas(Track track) async {
    final settings = context.read<SettingsCubit>().state.settings;
    if (!settings.canvasEnabled) {
      return;
    }

    final trackId = track.id;
    _loadedTrackId = trackId;
    setState(() {
      _loadingVideo = true;
      _hasCanvas = false;
    });

    VideoPlayerController? controller;
    try {
      final videoUrl = await locator<MusicRepository>().canvasFor(track);
      if (!mounted || _loadedTrackId != trackId || videoUrl == null) {
        if (mounted && _loadedTrackId == trackId) {
          setState(() {
            _loadingVideo = false;
          });
        }
        return;
      }

      final isLocal =
          !videoUrl.startsWith('http://') && !videoUrl.startsWith('https://');
      controller = isLocal
          ? VideoPlayerController.file(
              File(videoUrl.startsWith('file://')
                  ? Uri.parse(videoUrl).toFilePath()
                  : videoUrl),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
              viewType: VideoViewType.platformView,
            )
          : VideoPlayerController.networkUrl(
              Uri.parse(videoUrl),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
              viewType: VideoViewType.platformView,
            );

      await controller.initialize();
      await controller.setVolume(0.0); // Strictly muted to preserve SoLoud audio
      await controller.setLooping(true); // ExoPlayer native seamless hardware looping

      final totalDur = controller.value.duration;
      // Skip studio intro / credit scenes if video is long enough (official music videos)
      if (totalDur.inSeconds > 35) {
        try {
          await controller.seekTo(const Duration(seconds: 18));
        } catch (_) {
          // Seamlessly proceed from start if seek fails
        }
      }

      if (!mounted || _loadedTrackId != trackId) {
        controller.dispose();
        return;
      }

      _videoController?.removeListener(_onVideoTick);
      _videoController?.dispose();
      _videoController = controller;
      controller = null;
      _hasCanvas = true;
      _loadingVideo = false;

      _videoController!.addListener(_onVideoTick);

      if (widget.state.isPlaying && _canvasVisible) {
        _videoController!.play();
      }
      setState(() {});
    } catch (e) {
      controller?.dispose();
      debugPrint('[CANVAS-UI] Error initializing canvas video: $e');
      if (mounted && _loadedTrackId == trackId) {
        setState(() {
          _loadingVideo = false;
          _hasCanvas = false;
        });
      }
    }
  }

  void _disposeVideo() {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
    _loadedTrackId = null;
    _hasCanvas = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final player = context.read<PlayerCubit>();
    final track = widget.state.track!;
    final state = widget.state;

    final hasCanvas = _hasCanvas &&
        _videoController != null &&
        _videoController!.value.isInitialized &&
        !_videoController!.value.hasError &&
        _videoController!.value.size.width > 0 &&
        _videoController!.value.size.height > 0;
    final showCanvas = hasCanvas && _canvasVisible;

    return ArtworkColorBuilder(
      imageUrl: track.imageUrl,
      builder: (context, dominantColor) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: Hardware Canvas Video Layer
            if (showCanvas)
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: _videoController!.value.size.width,
                    height: _videoController!.value.size.height,
                    child: VideoPlayer(_videoController!),
                  ),
                ),
              ),

            // Layer 2: Obsidian Scrim Gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: showCanvas
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.65),
                            Colors.black.withValues(alpha: 0.15),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.45),
                            t.bg.withValues(alpha: 0.90),
                            t.bg,
                          ],
                          stops: const [0.0, 0.16, 0.40, 0.65, 0.88, 1.0],
                        )
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            dominantColor.withValues(alpha: t.isDark ? 0.38 : 0.22),
                            dominantColor.withValues(alpha: t.isDark ? 0.12 : 0.06),
                            t.bg,
                          ],
                          stops: const [0.0, 0.44, 0.86],
                        ),
                ),
              ),
            ),

            // Layer 3: Foreground Controls
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final artSize = math
                      .min(
                        constraints.maxWidth - SwissGrid.gutter * 2,
                        constraints.maxHeight * 0.38,
                      )
                      .clamp(120.0, 380.0);

                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            _TopBar(
                              hasCanvas: hasCanvas,
                              canvasActive: showCanvas,
                              isLoadingCanvas: _loadingVideo,
                              onToggleCanvas: hasCanvas ? _toggleCanvas : null,
                            ),
                            const SizedBox(height: SwissGrid.md),

                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: SwissGrid.gutter),
                              child: GestureDetector(
                                onTap: hasCanvas ? _toggleCanvas : null,
                                behavior: HitTestBehavior.opaque,
                                child: SizedBox(
                                  height: artSize,
                                  width: constraints.maxWidth,
                                  child: Center(
                                    child: AnimatedCrossFade(
                                      duration: const Duration(milliseconds: 350),
                                      crossFadeState: showCanvas
                                          ? CrossFadeState.showSecond
                                          : CrossFadeState.showFirst,
                                      firstChild: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Hero(
                                            tag: 'musify-artwork',
                                            curve: Curves.easeOutCubic,
                                            reverseCurve: Curves.easeInCubic,
                                            flightShuttleBuilder: (
                                              _,
                                              animation,
                                              __,
                                              ___,
                                              ____,
                                            ) =>
                                                _ArtworkShuttle(
                                              animation: animation,
                                              imageUrl: track.imageUrl,
                                              cacheDim: SwissArtwork.cacheDimFor(
                                                  artSize),
                                            ),
                                            child: SwissArtwork(
                                              imageUrl: track.imageUrl,
                                              size: artSize,
                                              radius: SwissTokens.radiusLg,
                                              placeholderIcon: Icons.music_note,
                                              filterQuality: FilterQuality.high,
                                            ),
                                          ),
                                          if (state.is8D)
                                            Positioned(
                                              right: 10,
                                              top: 10,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: t.accent,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          SwissTokens.radiusFull),
                                                ),
                                                child: Text(
                                                  'SPATIAL 8D',
                                                  style:
                                                      SwissType.micro.copyWith(
                                                    color: t.accentInk,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      secondChild: SizedBox(
                                        height: artSize,
                                        width: constraints.maxWidth,
                                        child: Center(
                                          child: state.is8D
                                              ? Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 12,
                                                    vertical: 5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: t.surfaceSunken
                                                        .withValues(alpha: 0.6),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            SwissTokens
                                                                .radiusFull),
                                                    border: Border.all(
                                                      color: t.hairline,
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.surround_sound,
                                                        size: 14,
                                                        color: t.accent,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'SPATIAL 8D ACTIVE',
                                                        style: SwissType.micro
                                                            .copyWith(
                                                          color: t.accent,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                        const Spacer(flex: 3),

                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            SwissGrid.gutter,
                            0,
                            SwissGrid.gutter,
                            SwissGrid.sm,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      track.title,
                                      style: SwissType.display.copyWith(color: t.ink),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      track.displayArtist,
                                      style: SwissType.body.copyWith(color: t.inkMuted),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (track.album.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '${track.album.toUpperCase()}${track.year == null ? '' : ' · ${track.year}'}',
                                        style: SwissType.micro.copyWith(color: t.inkFaint),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: SwissGrid.md),
                              // Like button with ambient artwork gradient glow
                              BlocSelector<LibraryCubit, LibraryState, bool>(
                                selector: (library) => library.liked.any(
                                  (t) =>
                                      t.id == track.id ||
                                      (t.dedupeKey == track.dedupeKey &&
                                          track.dedupeKey.isNotEmpty),
                                ),
                                builder: (context, liked) => Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        dominantColor.withValues(alpha: liked ? 0.35 : 0.16),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                  child: TactileIconKeycap(
                                    icon: liked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 48,
                                    iconSize: 26,
                                    ghost: true,
                                    tint: liked ? const Color(0xFFEF4444) : t.inkMuted,
                                    tooltip: liked
                                        ? 'Remove from Liked Songs'
                                        : 'Add to Liked Songs',
                                    onPressed: () async {
                                      Haptics.commit();
                                      await context
                                          .read<LibraryCubit>()
                                          .toggleLike(track);
                                      if (context.mounted) {
                                        context.read<PlayerCubit>().sync();
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        SwissGrid.gutter, 0, SwissGrid.gutter, SwissGrid.sm),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: t.surfaceSunken,
                            borderRadius: BorderRadius.circular(
                                SwissTokens.radiusFull),
                            border: Border.all(color: t.hairline, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LedDot(active: state.isPlaying, size: 6),
                              const SizedBox(width: 6),
                              Text(
                                state.isPlaying ? 'PLAYING' : 'PAUSED',
                                style: SwissType.micro.copyWith(
                                  color: state.isPlaying
                                      ? t.accent
                                      : t.inkMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (state.errorText != null)
                    _Banner(
                      icon: Icons.error_outline,
                      color: t.danger,
                      text: state.errorText!,
                    )
                  else if (state.downloadProgress != null)
                    _DownloadBanner(fraction: state.downloadProgress!)
                  else if (state.is8D && !state.headphones)
                    _Banner(
                      icon: Icons.headphones,
                      color: t.warning,
                      text: 'TAP IN HEADPHONES FOR THE FULL 3D ORBIT',
                    ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        SwissGrid.gutter, SwissGrid.sm, SwissGrid.gutter, 0),
                    child: _SeekSection(
                      enabled: state.canSeek,
                      buffered: state.bufferedFraction,
                      onSeek: player.seek,
                      onSeekHint: player.seekHint,
                    ),
                  ),
                  const SizedBox(height: SwissGrid.md),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SwissGrid.gutter),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TactileIconKeycap(
                          icon: Icons.shuffle,
                          size: 48,
                          iconSize: 22,
                          ghost: true,
                          tint: state.shuffle ? t.accent : t.inkMuted,
                          tooltip: 'Shuffle',
                          onPressed: player.toggleShuffle,
                        ),
                        TactileIconKeycap(
                          icon: Icons.skip_previous,
                          size: 54,
                          iconSize: 30,
                          ghost: true,
                          tint: t.ink,
                          tooltip: 'Previous',
                          onPressed: player.previous,
                        ),
                        TactileKeycap(
                          width: 74,
                          height: 74,
                          accent: true,
                          glow: false,
                          onPressed: player.togglePlayPause,
                          tooltip: state.isPlaying ? 'Pause' : 'Play',
                          child: Icon(
                            state.isPlaying
                                ? Icons.pause
                                : (state.isBuffering
                                    ? Icons.hourglass_top
                                    : Icons.play_arrow),
                            size: 36,
                            color: t.accentInk,
                          ),
                        ),
                        TactileIconKeycap(
                          icon: Icons.skip_next,
                          size: 54,
                          iconSize: 30,
                          ghost: true,
                          tint: t.ink,
                          tooltip: 'Next',
                          onPressed: player.next,
                        ),
                        TactileIconKeycap(
                          icon: switch (state.repeat) {
                            RepeatMode.one => Icons.repeat_one,
                            _ => Icons.repeat,
                          },
                          size: 48,
                          iconSize: 22,
                          ghost: true,
                          tint: state.repeat != RepeatMode.off
                              ? t.accent
                              : t.inkMuted,
                          tooltip: 'Repeat',
                          onPressed: player.cycleRepeat,
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 1),
                  const SizedBox(height: SwissGrid.sm),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SwissGrid.gutter),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: t.surfaceSunken,
                        borderRadius:
                            BorderRadius.circular(SwissTokens.radiusFull),
                        border: Border.all(color: t.hairline, width: 1),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _StripSegment(
                              icon: Icons.lyrics_outlined,
                              label: 'LYRICS',
                              selected: false,
                              onTap: () => showLyricsSheet(context, track),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _StripSegment(
                              icon: Icons.surround_sound,
                              label: 'SPATIAL 8D',
                              selected: state.is8D,
                              onTap: () {
                                Haptics.commit();
                                player.toggle8D();
                              },
                              onLongPress: () =>
                                  showEightDCalibration(context),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _StripSegment(
                              icon: Icons.queue_music,
                              label: 'QUEUE',
                              selected: false,
                              onTap: () => showQueueSheet(context),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _StripSegment(
                              icon: Icons.bedtime_outlined,
                              label: state.sleepRemaining == null
                                  ? 'SLEEP'
                                  : Fmt.countdown(state.sleepRemaining),
                              selected: state.sleepRemaining != null,
                              onTap: () => showSleepTimerSheet(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: SwissGrid.xl),
                ],
              ),
            ),
          ),
        );
      },
    ),
  ),
],
);
},
);
}
}

/// The cover in flight. It renders the plate's own cached decode and opens the
/// mini bar's 12 px corners into the plate's, so the flight never swaps image
/// resolutions or snaps a radius at either end.
class _ArtworkShuttle extends StatelessWidget {
  const _ArtworkShuttle({
    required this.animation,
    required this.imageUrl,
    required this.cacheDim,
  });

  final Animation<double> animation;
  final String imageUrl;
  final int cacheDim;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final url = hiresArtwork(imageUrl);
    final cover = url.isEmpty
        ? ColoredBox(
            color: t.surfaceSunken,
            child: Icon(Icons.music_note, color: t.inkFaint),
          )
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            memCacheWidth: cacheDim,
            memCacheHeight: cacheDim,
            placeholder: (_, __) => ColoredBox(color: t.surfaceSunken),
            errorWidget: (_, __, ___) => ColoredBox(
              color: t.surfaceSunken,
              child: Icon(Icons.music_note, color: t.inkFaint),
            ),
          );
    // Only the clip radius changes per frame; the image is built once.
    return AnimatedBuilder(
      animation: animation,
      child: cover,
      builder: (context, child) => ClipRRect(
        borderRadius: BorderRadius.circular(
          ui.lerpDouble(12, SwissTokens.radiusLg, animation.value)!,
        ),
        child: child,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    this.hasCanvas = false,
    this.canvasActive = false,
    this.isLoadingCanvas = false,
    this.onToggleCanvas,
  });

  final bool hasCanvas;
  final bool canvasActive;
  final bool isLoadingCanvas;
  final VoidCallback? onToggleCanvas;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final track = context.select<PlayerCubit, Track?>((c) => c.state.track);
    final sourceLabel =
        context.select<PlayerCubit, String>((c) => c.state.sourceLabel);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SwissGrid.sm, SwissGrid.sm, SwissGrid.sm, 0),
      child: Row(
        children: [
          TactileIconKeycap(
            icon: Icons.keyboard_arrow_down,
            size: 44,
            iconSize: 26,
            ghost: true,
            tint: t.ink,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: SwissGrid.sm),
          Expanded(
            child: hasCanvas
                ? Center(
                    child: GestureDetector(
                      onTap: onToggleCanvas,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: canvasActive
                              ? t.accent
                              : t.surfaceSunken.withValues(alpha: 0.7),
                          borderRadius:
                              BorderRadius.circular(SwissTokens.radiusFull),
                          border: Border.all(
                            color: canvasActive ? t.accent : t.hairline,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LedDot(active: canvasActive, size: 6),
                            const SizedBox(width: 6),
                            Text(
                              canvasActive ? 'CANVAS ON' : 'CANVAS OFF',
                              style: SwissType.micro.copyWith(
                                color: canvasActive
                                    ? t.accentInk
                                    : t.inkMuted,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : (isLoadingCanvas
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: t.surfaceSunken.withValues(alpha: 0.7),
                            borderRadius:
                                BorderRadius.circular(SwissTokens.radiusFull),
                            border: Border.all(
                              color: t.hairline,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 8,
                                height: 8,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: t.accent,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'LOADING CANVAS',
                                style: SwissType.micro.copyWith(
                                  color: t.inkMuted,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sourceLabel.isEmpty
                                ? 'NOW PLAYING'
                                : 'NOW PLAYING // $sourceLabel',
                            style: SwissType.micro.copyWith(color: t.inkFaint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'MUSIFY PLAYER',
                            style: SwissType.label.copyWith(
                              color: t.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )),
          ),
          const SizedBox(width: SwissGrid.sm),
          TactileIconKeycap(
            icon: Icons.format_list_bulleted,
            size: 44,
            iconSize: 19,
            ghost: true,
            tint: t.ink,
            tooltip: 'Queue',
            onPressed: () => showQueueSheet(context),
          ),
          const SizedBox(width: SwissGrid.xs),
          TactileIconKeycap(
            icon: Icons.more_vert,
            size: 44,
            iconSize: 19,
            ghost: true,
            tint: t.ink,
            tooltip: 'Track options',
            onPressed: track == null
                ? null
                : () => showTrackOptions(
                      context,
                      track,
                      source: sourceLabel,
                      queueContext: context.read<PlayerCubit>().state.queue,
                    ),
          ),
        ],
      ),
    );
  }
}

/// One segment of the transport strip: soft pill, accent when latched.
class _StripSegment extends StatelessWidget {
  const _StripSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? t.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: selected ? t.accentInk : t.inkMuted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: SwissType.micro.copyWith(
                  color: selected ? t.accentInk : t.inkMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The seek readout, isolated so only it repaints with the position timer.
class _SeekSection extends StatelessWidget {
  const _SeekSection({
    required this.onSeek,
    required this.onSeekHint,
    this.enabled,
    this.buffered,
  });

  final bool? enabled;
  final double? buffered;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSeekHint;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (previous, next) =>
          previous.position != next.position ||
          previous.duration != next.duration ||
          previous.buffered != next.buffered ||
          previous.canSeek != next.canSeek ||
          previous.bufferedFraction != next.bufferedFraction,
      builder: (context, state) => TactileSeekBar(
        position: state.position,
        duration: state.duration,
        buffered: state.bufferedFraction,
        enabled: state.canSeek,
        onSeek: onSeek,
        onSeekHint: onSeekHint,
      ),
    );
  }
}



class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
          SwissGrid.gutter, 0, SwissGrid.gutter, SwissGrid.md),
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: SwissGrid.sm),
          Expanded(
            child: Text(
              text,
              style: SwissType.micro.copyWith(color: t.ink, letterSpacing: 1.0),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadBanner extends StatelessWidget {
  const _DownloadBanner({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
          SwissGrid.gutter, 0, SwissGrid.gutter, SwissGrid.md),
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
      ),
      child: Row(
        children: [
          Icon(Icons.downloading, size: 14, color: t.accent),
          const SizedBox(width: SwissGrid.sm),
          Expanded(
            child: Text(
              'SAVING OFFLINE // ${(fraction * 100).round()}%',
              style: SwissType.micro.copyWith(color: t.ink),
            ),
          ),
          SizedBox(
            width: 60,
            child: TactileSlider(
              value: fraction,
              min: 0,
              max: 1,
              height: 18,
              thumbWidth: 8,
              thumbHeight: 12,
              enabled: false,
              onChanged: (_) {},
            ),
          ),
        ],
      ),
    );
  }
}

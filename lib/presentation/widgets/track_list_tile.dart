import 'package:flutter/material.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import 'swiss_artwork.dart';

/// The row that every tracklist in Musify is built from.
///
/// One tap plays (or resumes) the track; the `⋮` opens the universal context
/// menu; the leading cell doubles as an equaliser readout for whatever is
/// currently playing, which is how the user always knows where they are inside
/// a 60-track playlist.
class TrackListTile extends StatelessWidget {
  const TrackListTile({
    required this.track,
    required this.onTap,
    this.onOptions,
    this.onLongPress,
    this.isCurrent = false,
    this.isPlaying = false,
    this.index,
    this.trailing,
    this.showArtwork = true,
    this.showBitrate = false,
    this.showDivider = false,
    this.artworkSize = 48.0,
    this.padding,
    this.borderRadius,
    this.dense = false,
    this.subtitle,
    super.key,
  });

  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onOptions;
  final VoidCallback? onLongPress;
  final bool isCurrent;
  final bool isPlaying;
  final int? index;
  final Widget? trailing;
  final bool showArtwork;
  final bool showBitrate;
  final bool showDivider;
  final double artworkSize;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final bool dense;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final accent = t.accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Haptics.tap();
          onTap();
        },
        onLongPress: onLongPress,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Container(
          padding: padding ??
              EdgeInsets.symmetric(
                horizontal: SwissGrid.gutter,
                vertical: dense ? SwissGrid.sm : SwissGrid.sm + 4,
              ),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(
                    bottom: BorderSide(
                        color: t.hairline.withValues(alpha: 0.6), width: 1),
                  )
                : null,
            borderRadius: borderRadius ?? BorderRadius.circular(12),
            color: isCurrent ? t.accentSoft.withValues(alpha: 0.2) : null,
          ),
          child: Row(
            children: [
              if (index != null && !showArtwork)
                SizedBox(
                  width: 24,
                  child: Text(
                    '${index! + 1}'.padLeft(2, '0'),
                    style: SwissType.mono.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? accent : t.inkFaint,
                    ),
                  ),
                ),
              if (showArtwork) ...[
                _Leading(
                  track: track,
                  isCurrent: isCurrent,
                  isPlaying: isPlaying,
                  accent: accent,
                  size: artworkSize,
                ),
                const SizedBox(width: SwissGrid.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      style: SwissType.title.copyWith(
                        color: isCurrent ? accent : t.ink,
                        fontSize: dense ? 14.0 : 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (track.isDownloaded) ...[
                          Icon(Icons.offline_pin_outlined, size: 12, color: t.positive),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            subtitle ?? track.artist,
                            style: SwissType.body.copyWith(
                              color: t.inkMuted,
                              fontSize: dense ? 12.0 : 13.0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SwissGrid.sm),
              if (showBitrate) ...[
                SwissBadge(
                  text: track.isDownloaded ? 'OFFLINE' : track.bitrateLabel,
                  color: track.isDownloaded ? t.positive : null,
                ),
                const SizedBox(width: SwissGrid.sm),
              ],
              Text(
                Fmt.durationShort(track.duration),
                style: SwissType.mono.copyWith(color: t.inkFaint, fontSize: 11.5),
              ),
              if (trailing != null) ...[
                const SizedBox(width: SwissGrid.sm),
                trailing!,
              ] else if (onOptions != null) ...[
                const SizedBox(width: SwissGrid.xs),
                TactileIconKeycap(
                  icon: Icons.more_vert,
                  size: 32,
                  iconSize: 16,
                  ghost: true,
                  tooltip: 'Options',
                  hapticOnPress: false,
                  onPressed: () {
                    Haptics.tap();
                    onOptions!();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Leading extends StatelessWidget {
  const _Leading({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.accent,
    this.size = 40.0,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final art = SwissArtwork(
      imageUrl: track.imageUrl,
      size: size,
      radius: size > 44 ? 12 : 10,
      showBorder: false,
      placeholderIcon: Icons.music_note,
    );

    if (!isCurrent) return art;

    return Stack(
      children: [
        art,
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.bg.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(size > 44 ? 12 : 10),
            ),
            child: Center(
              child: Icon(
                isPlaying ? Icons.graphic_eq : Icons.pause,
                size: size > 44 ? 22 : 18,
                color: accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A compact card for rails ("Continue Listening", "Recently Played"):
/// floating paper, artwork, a corner play bead and clean typography.
class TrackCard extends StatelessWidget {
  const TrackCard({
    required this.track,
    required this.onTap,
    this.onOptions,
    this.width = 160,
    this.isCurrent = false,
    this.caption,
    super.key,
  });

  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onOptions;
  final double width;
  final bool isCurrent;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final accent = t.accent;

    return SizedBox(
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          onTap();
        },
        onLongPress: onOptions,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrent ? t.accent.withValues(alpha: 0.45) : t.hairline,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  SwissArtwork(
                    imageUrl: track.imageUrl,
                    radius: 12,
                    showBorder: false,
                    placeholderIcon: Icons.music_note,
                  ),
                  if (isCurrent)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.bg.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? accent
                            : Colors.black.withValues(alpha: 0.70),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        isCurrent ? Icons.graphic_eq : Icons.play_arrow,
                        size: 17,
                        color: isCurrent ? t.accentInk : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (isCurrent) ...[
                Container(
                  height: 2.5,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: t.surfaceSunken,
                    borderRadius: BorderRadius.circular(SwissTokens.radiusFull),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 0.65,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.accent,
                        borderRadius:
                            BorderRadius.circular(SwissTokens.radiusFull),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                track.title,
                style: SwissType.bodySm.copyWith(
                  color: isCurrent ? accent : t.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                caption ?? track.displayArtist,
                style: SwissType.bodyXs.copyWith(
                  color: t.inkMuted,
                  fontSize: 11.5,
                ),
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

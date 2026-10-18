import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/artwork_url.dart';
import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';

/// A square artwork frame with the exposed Swiss hairline.
///
/// Every network image in Musify goes through here, which is what satisfies
/// PRD Law 5: explicit size, a skeleton placeholder while it loads, and a
/// drawn fallback when the link is dead — so a broken cover can never change a
/// layout or leave a hole in the grid.
class SwissArtwork extends StatelessWidget {
  const SwissArtwork({
    required this.imageUrl,
    this.size,
    this.radius = SwissTokens.radius,
    this.circular = false,
    this.showBorder = true,
    this.placeholderIcon = Icons.album_outlined,
    this.heroTag,
    this.filterQuality = FilterQuality.medium,
    super.key,
  });

  final String imageUrl;
  final double? size;
  final double radius;
  final bool circular;
  final bool showBorder;
  final IconData placeholderIcon;
  final Object? heroTag;

  /// `medium` is the floor everywhere; a cover shown as a large plate (Now
  /// Playing) asks for `high`, because low-quality resampling is exactly what
  /// makes an upscaled 500px cover look blocky on a 3× screen.
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final border = showBorder && !circular
        ? Border.all(color: t.hairline, width: 1)
        : null;

    // Always ask for the biggest rendition the CDN has. A track cached by an
    // older build (or restored from a backup) can carry a 150×150 URL, and the
    // plate must not inherit that blur.
    final resolvedUrl = hiresArtwork(imageUrl);

    Widget content = ClipRRect(
      borderRadius: circular
          ? BorderRadius.circular((size ?? 48) / 2)
          : BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surfaceSunken,
          border: border,
          borderRadius: circular ? null : BorderRadius.circular(radius),
          shape: circular ? BoxShape.circle : BoxShape.rectangle,
        ),
        child: resolvedUrl.isEmpty
            ? _Fallback(icon: placeholderIcon, circular: circular)
            : CachedNetworkImage(
                imageUrl: resolvedUrl,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 180),
                filterQuality: filterQuality,
                placeholder: (context, _) => const SwissSkeleton(
                  height: double.infinity,
                  radius: SwissTokens.radius,
                ),
                errorWidget: (context, _, __) => _Fallback(
                  icon: placeholderIcon,
                  circular: circular,
                ),
              ),
      ),
    );

    if (heroTag != null) {
      content = Hero(tag: heroTag!, child: content);
    }

    if (size == null) return AspectRatio(aspectRatio: 1, child: content);
    return SizedBox(width: size, height: size, child: content);
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.icon, this.circular = false});

  final IconData icon;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    return Center(
      child: Icon(
        icon,
        size: circular ? 22 : 24,
        color: t.inkFaint.withValues(alpha: 0.7),
      ),
    );
  }
}

/// The 2×2 mosaic cover used for playlists and albums built from songs.
///
/// Falls back gracefully at every count: four covers make the mosaic, fewer
/// covers repeat the first, none shows the plate icon. A playlist never gets
/// fake artwork it has not earned.
class MosaicArtwork extends StatelessWidget {
  const MosaicArtwork({
    required this.urls,
    this.size,
    this.radius = SwissTokens.radius,
    this.placeholderIcon = Icons.queue_music,
    super.key,
  });

  final List<String> urls;
  final double? size;
  final double radius;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final covers = urls.where((u) => u.isNotEmpty).toList();

    Widget body;
    if (covers.isEmpty) {
      body = Center(child: Icon(placeholderIcon, size: 22, color: t.inkFaint));
    } else if (covers.length == 1) {
      body = CachedNetworkImage(
        imageUrl: hiresArtwork(covers.first),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    } else {
      body = Column(
        children: [
          Expanded(child: _row(covers[0], covers.length > 1 ? covers[1] : null)),
          Expanded(child: _row(covers.length > 2 ? covers[2] : null, covers.length > 3 ? covers[3] : null)),
        ],
      );
    }

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surfaceSunken,
          border: Border.all(color: t.hairline),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: body,
      ),
    );

    if (size == null) return AspectRatio(aspectRatio: 1, child: content);
    return SizedBox(width: size, height: size, child: content);
  }

  Widget _row(String? left, String? right) {
    Widget cell(String? url) => Expanded(
      child: url == null || url.isEmpty
          ? const ColoredBox(color: Colors.transparent)
          : CachedNetworkImage(
              imageUrl: hiresArtwork(url),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
    );
    return Row(
      children: [cell(left), cell(right)],
    );
  }
}

/// A `320 KBPS` / `OFFLINE` / `8D` tag row helper used under artwork.
class ArtworkBadgeRow extends StatelessWidget {
  const ArtworkBadgeRow({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: SwissGrid.xs,
    runSpacing: SwissGrid.xs,
    children: children,
  );
}

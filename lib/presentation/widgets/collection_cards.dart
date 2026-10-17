import 'package:flutter/material.dart';

import '../../core/theme/swiss_tokens.dart';
import '../../core/theme/tactile_decorations.dart';
import '../../data/datasources/jiosaavn_client.dart';
import '../../data/models/collection.dart';
import 'swiss_artwork.dart';

/// A card in a horizontal rail: square (or round, for artists) artwork with two
/// lines of type under it.
class CollectionRailCard extends StatelessWidget {
  const CollectionRailCard({
    required this.collection,
    required this.onTap,
    this.width = 156,
    super.key,
  });

  final Collection collection;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final round = collection.isRound;

    return SizedBox(
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: Column(
          crossAxisAlignment:
              round ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SwissArtwork(
              imageUrl: collection.imageUrl,
              radius: 14,
              circular: round,
              placeholderIcon:
                  round ? Icons.person_outline : Icons.album_outlined,
            ),
            const SizedBox(height: SwissGrid.sm),
            Text(
              collection.title,
              textAlign: round ? TextAlign.center : TextAlign.start,
              style: SwissType.bodySm.copyWith(
                color: t.ink,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              collection.subtitle.isEmpty
                  ? collection.kindLabel
                  : collection.subtitle,
              textAlign: round ? TextAlign.center : TextAlign.start,
              style: SwissType.micro.copyWith(color: t.inkFaint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// A rail item that may be *either* a collection or a playable song — the
/// JioSaavn launch payload mixes both inside one rail.
class RailItemCard extends StatelessWidget {
  const RailItemCard({
    required this.item,
    required this.onOpenCollection,
    required this.onPlayTrack,
    this.width = 156,
    super.key,
  });

  final RailItem item;
  final ValueChanged<Collection> onOpenCollection;
  final ValueChanged<dynamic> onPlayTrack;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return SizedBox(
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          final collection = item.collection;
          if (collection != null) {
            onOpenCollection(collection);
          } else {
            onPlayTrack(item.track);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                SwissArtwork(
                  imageUrl: item.imageUrl,
                  radius: 14,
                  placeholderIcon:
                      item.isTrack ? Icons.music_note : Icons.album_outlined,
                ),
                if (item.isTrack)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.surfaceRaised,
                        shape: BoxShape.circle,
                        boxShadow: t.raisedShadow,
                      ),
                      child: Icon(Icons.play_arrow, size: 16, color: t.accent),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: SwissGrid.sm),
            Text(
              item.title,
              style: SwissType.bodySm
                  .copyWith(color: t.ink, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              item.isTrack ? 'TRACK' : (item.collection?.kindLabel ?? ''),
              style: SwissType.micro.copyWith(
                color: t.accent,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// The 2-column grid tile used by the Library grid and the genre browser.
class CollectionGridTile extends StatelessWidget {
  const CollectionGridTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onTap,
    this.ordinal,
    this.mosaic = const [],
    this.round = false,
    this.badge,
    super.key,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final List<String> mosaic;
  final VoidCallback onTap;

  /// `01`, `02`… rendered in the corner of genre tiles.
  final String? ordinal;
  final bool round;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);
    final resolvedUrl = imageUrl.isNotEmpty
        ? imageUrl
        : (mosaic.isEmpty ? _fallbackGenreImage(title) : '');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: t.hairline, width: 1),
          borderRadius: BorderRadius.circular(16),
          color: t.surfaceRaised,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(SwissGrid.sm),
              child: mosaic.isNotEmpty
                  ? MosaicArtwork(urls: mosaic, radius: 12)
                  : SwissArtwork(imageUrl: resolvedUrl, circular: round, radius: 12),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SwissGrid.sm + 2,
                0,
                SwissGrid.sm + 2,
                SwissGrid.sm + 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ordinal != null) ...[
                    Text(
                      ordinal!,
                      style: SwissType.micro.copyWith(
                        color: t.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: SwissGrid.xs),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: SwissType.bodySm.copyWith(
                            color: t.ink,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: SwissType.micro.copyWith(color: t.inkFaint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: SwissGrid.xs),
                    SwissBadge(text: badge!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontal rail with its `NN // TITLE` header.
class SwissRail extends StatelessWidget {
  const SwissRail({
    required this.index,
    required this.title,
    required this.children,
    this.subtitle,
    this.height,
    this.trailing,
    super.key,
  });

  final String index;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Fixed rail height — without it, a horizontal `ListView` inside a vertical
  /// scroll view would have unbounded height (PRD Law 5).
  final double? height;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          index: index,
          title: title,
          subtitle: subtitle,
          trailing: trailing,
        ),
        SizedBox(
          height: height ?? 228,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: SwissGrid.gutter),
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(width: SwissGrid.md),
            itemBuilder: (context, i) => children[i],
          ),
        ),
      ],
    );
  }
}

/// [SwissRail] with a sliver-shaped API, for use inside
/// `CustomScrollView.slivers`.
///
/// `SwissRail` builds a box (`Column`). Handing a box widget straight to a
/// viewport throws, at first paint:
///
/// ```
/// type 'RenderConstrainedBox' is not a subtype of type 'RenderSliver' of 'child'
/// ```
///
/// `flutter analyze` cannot see this — every `slivers:` list is just
/// `List<Widget>`. So the rule is mechanical: **slivers list → `SliverRail`,
/// box list → `SwissRail`.** The empty case still returns a sliver, because an
/// empty rail can become non-empty on the next rebuild without the element
/// being re-created.
class SliverRail extends StatelessWidget {
  const SliverRail({
    required this.index,
    required this.title,
    required this.children,
    this.subtitle,
    this.height,
    this.trailing,
    super.key,
  });

  final String index;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final double? height;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: SwissRail(
        index: index,
        title: title,
        subtitle: subtitle,
        height: height,
        trailing: trailing,
        children: children,
      ),
    );
  }
}

/// The loading skeleton for a rail: same geometry, no layout shift.
class RailSkeleton extends StatelessWidget {
  const RailSkeleton(
      {this.count = 3, this.index = '00', this.title = 'LOADING', super.key});

  final int count;
  final String index;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SwissRail(
      index: index,
      title: title,
      children: List<Widget>.generate(
        count,
        (_) => const SizedBox(
          width: 148,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwissSkeleton(height: 148),
              SizedBox(height: SwissGrid.sm),
              SwissSkeleton(height: 11, width: 110),
              SizedBox(height: SwissGrid.xs),
              SwissSkeleton(height: 9, width: 70),
            ],
          ),
        ),
      ),
    );
  }
}

String _fallbackGenreImage(String title) {
  final q = title.toLowerCase();
  if (q.contains('phonk') || q.contains('bass')) {
    return 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&auto=format&fit=crop&q=80';
  } else if (q.contains('bollywood') || q.contains('indi-pop') || q.contains('indian')) {
    return 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=600&auto=format&fit=crop&q=80';
  } else if (q.contains('global') || q.contains('pop') || q.contains('top 50')) {
    return 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=600&auto=format&fit=crop&q=80';
  } else if (q.contains('lo-fi') || q.contains('lofi') || q.contains('study') || q.contains('chill')) {
    return 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=600&auto=format&fit=crop&q=80';
  } else if (q.contains('hip-hop') || q.contains('hip hop') || q.contains('rap')) {
    return 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=600&auto=format&fit=crop&q=80';
  } else if (q.contains('electronic') || q.contains('synth') || q.contains('edm') || q.contains('dance')) {
    return 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=600&auto=format&fit=crop&q=80';
  } else if (q.contains('8d') || q.contains('spatial')) {
    return 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=600&auto=format&fit=crop&q=80';
  } else if (q.contains('workout') || q.contains('bpm') || q.contains('gym') || q.contains('fitness')) {
    return 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=600&auto=format&fit=crop&q=80';
  }
  return 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=600&auto=format&fit=crop&q=80';
}

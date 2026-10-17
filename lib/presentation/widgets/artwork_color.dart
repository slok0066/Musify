import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Samples the dominant color from track cover art to power dynamic ambient
/// gradients in the Now Playing screen, identical to Spotify's player aesthetic.
class ArtworkColorExtractor {
  static final Map<String, Color> _cache = {};

  /// Synchronously returns a cached or hash-derived vibrant fallback color.
  static Color fastColor(String imageUrl, {Color fallback = const Color(0xFF6366F1)}) {
    if (imageUrl.isEmpty) return fallback;
    if (_cache.containsKey(imageUrl)) return _cache[imageUrl]!;

    final hash = imageUrl.hashCode.abs();
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.65, 0.38).toColor();
  }

  /// Asynchronously extracts the true dominant color by rendering the image to a 1x1 canvas.
  static Future<Color> extract(
    String imageUrl, {
    Color fallback = const Color(0xFF6366F1),
  }) async {
    if (imageUrl.isEmpty) return fallback;
    if (_cache.containsKey(imageUrl)) return _cache[imageUrl]!;

    try {
      final provider = CachedNetworkImageProvider(imageUrl);
      final completer = Completer<ui.Image>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info.image);
          stream.removeListener(listener);
        },
        onError: (dynamic error, StackTrace? stack) {
          if (!completer.isCompleted) completer.completeError(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);

      final uiImage = await completer.future.timeout(const Duration(seconds: 2));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        uiImage,
        Rect.fromLTWH(0, 0, uiImage.width.toDouble(), uiImage.height.toDouble()),
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final tinyImg = await picture.toImage(1, 1);
      final byteData = await tinyImg.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData != null) {
        final r = byteData.getUint8(0);
        final g = byteData.getUint8(1);
        final b = byteData.getUint8(2);

        final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
        final adjusted = hsl
            .withSaturation(math.max(hsl.saturation, 0.50))
            .withLightness(hsl.lightness.clamp(0.28, 0.50))
            .toColor();

        _cache[imageUrl] = adjusted;
        return adjusted;
      }
    } catch (_) {}

    final color = fastColor(imageUrl, fallback: fallback);
    _cache[imageUrl] = color;
    return color;
  }
}

/// A reactive widget that morphs smoothly between dynamic artwork colors.
class ArtworkColorBuilder extends StatefulWidget {
  const ArtworkColorBuilder({
    required this.imageUrl,
    required this.builder,
    this.fallbackColor,
    super.key,
  });

  final String imageUrl;
  final Widget Function(BuildContext context, Color color) builder;
  final Color? fallbackColor;

  @override
  State<ArtworkColorBuilder> createState() => _ArtworkColorBuilderState();
}

class _ArtworkColorBuilderState extends State<ArtworkColorBuilder> {
  late Color _color;

  @override
  void initState() {
    super.initState();
    _color = ArtworkColorExtractor.fastColor(
      widget.imageUrl,
      fallback: widget.fallbackColor ?? const Color(0xFF6366F1),
    );
    _fetch();
  }

  @override
  void didUpdateWidget(covariant ArtworkColorBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _color = ArtworkColorExtractor.fastColor(
        widget.imageUrl,
        fallback: widget.fallbackColor ?? const Color(0xFF6366F1),
      );
      _fetch();
    }
  }

  void _fetch() {
    if (widget.imageUrl.isEmpty) return;
    ArtworkColorExtractor.extract(
      widget.imageUrl,
      fallback: widget.fallbackColor ?? const Color(0xFF6366F1),
    ).then((extracted) {
      if (mounted && extracted != _color) {
        setState(() => _color = extracted);
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _color);
  }
}

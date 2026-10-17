import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// A resolved piece of artwork.
class Artwork {
  const Artwork({required this.url, this.width = 1000, this.source = ''});

  final String url;
  final int width;
  final String source;

  bool get isValid => url.isNotEmpty;
}

/// Uncompressed 1:1 artwork and artist portraits from Deezer and iTunes.
///
/// The PRD asks for 1000×1000 px covers. JioSaavn's CDN tops out well below
/// that for many releases, so this is a *silent enhancement layer*: when it
/// finds a better image the UI swaps it in, and when both providers miss, the
/// catalogue thumbnail stays exactly as it was. It never blocks a render and
/// never surfaces an error.
class ArtworkClient {
  ArtworkClient(this._dio);

  final Dio _dio;

  final Map<String, Artwork?> _albumCache = {};
  final Map<String, Artwork?> _artistCache = {};

  /// Best square cover for an album / track.
  Future<Artwork?> albumArt({
    required String album,
    required String artist,
    String? title,
  }) async {
    final key = '${album.toLowerCase()}|${artist.toLowerCase()}';
    if (_albumCache.containsKey(key)) return _albumCache[key];

    Artwork? result;

    if (album.trim().isNotEmpty) {
      result = await _deezerAlbum(album, artist);
    }
    result ??= await _itunesTrack(title ?? album, artist);

    _albumCache[key] = result;
    return result;
  }

  /// 1000 px artist portrait.
  Future<Artwork?> artistPortrait(String artist) async {
    final key = artist.toLowerCase().trim();
    if (key.isEmpty) return null;
    if (_artistCache.containsKey(key)) return _artistCache[key];

    Artwork? result = await _deezerArtist(artist);
    result ??= await _itunesArtist(artist);

    _artistCache[key] = result;
    return result;
  }

  // ------------------------------------------------------------------ Deezer

  Future<Artwork?> _deezerAlbum(String album, String artist) async {
    final data = await _deezer('search/album', {
      'q': 'album:"$album" artist:"$artist"',
      'limit': '1',
    });
    final first = _firstDeezerResult(data);
    if (first == null) return null;
    final url = _str(first['cover_xl'] ?? first['cover_big'] ?? first['cover_medium']);
    return url.isEmpty ? null : Artwork(url: url, source: 'deezer');
  }

  Future<Artwork?> _deezerArtist(String artist) async {
    final data = await _deezer('search/artist', {'q': artist, 'limit': '1'});
    final first = _firstDeezerResult(data);
    if (first == null) return null;
    final url = _str(first['picture_xl'] ?? first['picture_big'] ?? first['picture_medium']);
    return url.isEmpty ? null : Artwork(url: url, source: 'deezer');
  }

  Future<Map<String, dynamic>?> _deezer(
    String path,
    Map<String, String> params,
  ) async {
    try {
      final response = await _dio.get<dynamic>(
        'https://api.deezer.com/$path',
        queryParameters: params,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = response.data;
      if (raw is! String || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (e) {
      debugPrint('Deezer $path failed: $e');
      return null;
    }
  }

  Map<String, dynamic>? _firstDeezerResult(Map<String, dynamic>? payload) {
    final data = payload?['data'];
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    return first is Map ? first.cast<String, dynamic>() : null;
  }

  // ------------------------------------------------------------------ iTunes

  Future<Artwork?> _itunesTrack(String term, String artist) async {
    final results = await _itunes({'term': '$term $artist', 'entity': 'song', 'limit': '1'});
    if (results.isEmpty) return null;
    final url = _upscaleItunes(_str(results.first['artworkUrl100']));
    return url.isEmpty ? null : Artwork(url: url, source: 'itunes');
  }

  Future<Artwork?> _itunesArtist(String term) async {
    final results = await _itunes({'term': term, 'entity': 'musicArtist', 'limit': '1'});
    if (results.isEmpty) return null;
    // iTunes artist entries carry no artwork; the track search does.
    final tracks = await _itunes({'term': term, 'entity': 'song', 'limit': '1'});
    if (tracks.isEmpty) return null;
    final url = _upscaleItunes(_str(tracks.first['artworkUrl100']));
    return url.isEmpty ? null : Artwork(url: url, source: 'itunes');
  }

  Future<List<Map<String, dynamic>>> _itunes(Map<String, String> params) async {
    try {
      final response = await _dio.get<dynamic>(
        'https://itunes.apple.com/search',
        queryParameters: params,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = response.data;
      if (raw is! String || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final results = decoded['results'];
      if (results is! List) return const [];
      return results.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (e) {
      debugPrint('iTunes search failed: $e');
      return const [];
    }
  }

  /// `100x100bb.jpg` → `1000x1000bb.jpg`.
  static String _upscaleItunes(String url) {
    if (url.isEmpty) return '';
    return url.replaceAllMapped(
      RegExp(r'(\d+)x(\d+)(bb)?\.(jpg|png)$', caseSensitive: false),
      (m) => '1000x1000${m.group(3) ?? ''}.${m.group(4)}',
    );
  }

  static String _str(Object? raw) => raw?.toString().trim() ?? '';
}

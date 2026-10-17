import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/formatters.dart';
import '../models/lyrics.dart';
import '../models/track.dart';

/// Time-synced lyrics from LRCLIB — free, no key, no attribution requirement.
///
/// Multiple strategies are tried in order because the catalogue's idea of an
/// artist credit ("Arijit Singh, Pritam") never matches LRCLIB's ("Arijit
/// Singh"), and getting a synced sheet is the difference between a karaoke
/// view and a wall of text.
class LyricsClient {
  LyricsClient(this._dio);

  final Dio _dio;

  static const String _base = 'https://lrclib.net/api';
  static const Map<String, String> _headers = {
    'User-Agent': 'Musify/1.0.0 (open-source music player; contact: musify@example.com)',
    'Accept': 'application/json',
  };

  final Map<String, Lyrics?> _cache = {};

  Future<Lyrics?> fetch(Track track) async {
    final key = track.dedupeKey;
    if (_cache.containsKey(key)) return _cache[key];

    final lyrics = await _fetchUncached(track);
    _cache[key] = lyrics;
    return lyrics;
  }

  Future<Lyrics?> _fetchUncached(Track track) async {
    final title = _clean(track.title);
    final artists = _artistCandidates(track);
    final duration = track.duration.inSeconds;

    // 1. Exact match with the primary artist.
    for (final artist in artists) {
      final exact = await _get(
        artist: artist,
        title: title,
        duration: duration > 0 ? duration : null,
      );
      if (exact != null && !exact.isEmpty) {
        if (exact.synced) return exact;
        // Keep the first plain-text hit as a fallback but keep looking for a
        // synced sheet.
        _cache['${track.dedupeKey}:plain'] = exact;
      }
    }

    // 2. Exact match without duration (remasters differ by seconds).
    for (final artist in artists) {
      final exact = await _get(artist: artist, title: title);
      if (exact != null && exact.synced) return exact;
    }

    // 3. Free search, scored by title similarity.
    final searched = await _search('${artists.first} $title');
    if (searched != null && !searched.isEmpty) return searched;

    return _cache['${track.dedupeKey}:plain'];
  }

  Future<Lyrics?> _get({
    required String artist,
    required String title,
    int? duration,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '$_base/get',
        queryParameters: {
          'artist_name': artist,
          'track_name': title,
          if (duration != null) 'duration': '$duration',
        },
        options: Options(
          headers: _headers,
          responseType: ResponseType.plain,
          validateStatus: (code) => code != null && code < 500,
        ),
      );
      if (response.statusCode == 404) return null;
      return _parse(response.data);
    } catch (e) {
      debugPrint('LRCLIB /get failed: $e');
      return null;
    }
  }

  Future<Lyrics?> _search(String query) async {
    try {
      final response = await _dio.get<dynamic>(
        '$_base/search',
        queryParameters: {'q': query},
        options: Options(
          headers: _headers,
          responseType: ResponseType.plain,
          validateStatus: (code) => code != null && code < 500,
        ),
      );
      final data = response.data;
      if (data is! String || data.isEmpty) return null;
      final decoded = _decode(data);
      if (decoded is! List) return null;

      Lyrics? best;
      for (final entry in decoded.whereType<Map>()) {
        final candidate = _parseFromMap(entry.cast<String, dynamic>());
        if (candidate == null || candidate.isEmpty) continue;
        if (candidate.synced) return candidate;
        best ??= candidate;
      }
      return best;
    } catch (e) {
      debugPrint('LRCLIB /search failed: $e');
      return null;
    }
  }

  Lyrics? _parse(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final decoded = _decode(raw);
    if (decoded is! Map) return null;
    return _parseFromMap(decoded.cast<String, dynamic>());
  }

  Lyrics? _parseFromMap(Map<String, dynamic> map) {
    final synced = map['syncedLyrics'];
    final plain = map['plainLyrics'];
    final instrumental = map['instrumental'] == true;

    if (instrumental) {
      return const Lyrics(
        lines: [LyricLine(text: '♪  INSTRUMENTAL')],
        synced: false,
      );
    }

    final lyrics = Lyrics.parse(
      syncedLyrics: synced is String ? synced : null,
      plainLyrics: plain is String ? plain : null,
    );
    return lyrics.isEmpty ? null : lyrics;
  }

  /// Title cleanup: strip the `(From "Film")` / `- Remastered 2011` noise that
  /// the catalogue keeps but lyric databases usually do not.
  static String _clean(String raw) {
    var s = Fmt.cleanTitle(raw);
    s = s.replaceAll(RegExp(r'\s*[\(\[](?:from|feat|ft|with|official|lyric|audio|video|remaster)[^\)\]]*[\)\]]', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*-\s*(?:remaster(?:ed)?|from|feat\.?|ft\.?).*$', caseSensitive: false), '');
    return s.trim();
  }

  /// Every plausible artist credit, most specific first.
  static List<String> _artistCandidates(Track track) {
    final raw = track.displayArtist;
    final parts = raw
        .split(RegExp(r'[,&]|\bfeat\.?\b|\bft\.?\b|\bwith\b', caseSensitive: false))
        .map((p) => Fmt.cleanTitle(p))
        .where((p) => p.isNotEmpty && p.toLowerCase() != 'unknown')
        .toList();

    final candidates = <String>{
      if (parts.isNotEmpty) parts.first,
      raw,
      ...parts,
    }.where((c) => c.isNotEmpty).toList();

    return candidates.isEmpty ? const ['Unknown'] : candidates;
  }

  static Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}

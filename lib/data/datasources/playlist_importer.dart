import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/formatters.dart';
import '../models/track.dart';
import '../repositories/music_repository.dart';

/// One song read out of a pasted public playlist page.
class ImportedEntry {
  const ImportedEntry({required this.title, this.artist = ''});

  final String title;
  final String artist;

  String get query => artist.trim().isEmpty ? title : '$title $artist';
}

/// A playlist page that was successfully read.
class ImportedSource {
  const ImportedSource({
    required this.name,
    required this.entries,
    required this.provider,
  });

  final String name;
  final List<ImportedEntry> entries;

  /// `YOUTUBE` or `SPOTIFY`, shown in the import readout.
  final String provider;
}

/// Live import progress for the `[IMPORT URL]` sheet.
class ImportProgress {
  const ImportProgress({
    required this.matched,
    required this.total,
    this.current = '',
    this.phase = ImportPhase.matching,
  });

  const ImportProgress.reading()
      : matched = 0,
        total = 0,
        current = '',
        phase = ImportPhase.reading;

  final int matched;
  final int total;
  final String current;
  final ImportPhase phase;

  double? get fraction => total == 0 ? null : (matched / total).clamp(0.0, 1.0);
}

enum ImportPhase { reading, matching, done, failed }

/// Reads a public YouTube or Spotify playlist URL and re-buys the songs on
/// JioSaavn.
///
/// Neither provider is used for playback here — their pages are only read for
/// *metadata* (title + artist), and every entry is then matched against the
/// 320 kbps JioSaavn catalogue. That keeps Musify's zero-key promise: no
/// Spotify credentials, no YouTube stream extraction, no proxy.
class PlaylistImporter {
  PlaylistImporter(this._dio, this._music);

  final Dio _dio;
  final MusicRepository _music;

  static final RegExp _youtube = RegExp(
    r'(?:youtube\.com|youtu\.be)/.*[?&]list=([A-Za-z0-9_-]{10,})',
    caseSensitive: false,
  );
  static final RegExp _spotify = RegExp(
    r'(?:open\.)?spotify\.com/(?:intl-\w+/)?playlist/([A-Za-z0-9]{10,})',
    caseSensitive: false,
  );

  bool get handlesSomething => true;

  /// What kind of link the user pasted, if any.
  String? detectProvider(String url) {
    if (_youtube.hasMatch(url)) return 'YOUTUBE';
    if (_spotify.hasMatch(url)) return 'SPOTIFY';
    return null;
  }

  /// Reads the playlist page. Returns `null` when the link is unsupported or
  /// the page could not be parsed — never throws into the UI.
  Future<ImportedSource?> read(
    String url,
    ValueChanged<ImportProgress> onProgress,
  ) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    onProgress(const ImportProgress.reading());

    final youtube = _youtube.firstMatch(trimmed);
    if (youtube != null) return _readYoutube(youtube.group(1)!);

    final spotify = _spotify.firstMatch(trimmed);
    if (spotify != null) return _readSpotify(spotify.group(1)!);

    // A bare URL with no recognisable id: fall back to the generic reader,
    // which sniffs Open Graph tags.
    return _readOpenGraph(trimmed);
  }

  /// Matches every entry against JioSaavn, best-effort, reporting progress.
  Future<List<Track>> match(
    List<ImportedEntry> entries,
    ValueChanged<ImportProgress> onProgress,
  ) async {
    final out = <Track>[];
    final seen = <String>{};
    var matched = 0;

    for (final entry in entries.take(200)) {
      onProgress(
        ImportProgress(
          matched: matched,
          total: entries.length,
          current: entry.title,
        ),
      );

      try {
        final candidates = await _music.searchSongs(entry.query, page: 1);
        final best = _bestMatch(entry, candidates);
        if (best != null && seen.add(best.id)) {
          out.add(best);
          matched++;
        }
      } catch (e) {
        debugPrint('Import match failed for "${entry.title}": $e');
      }
    }

    onProgress(
      ImportProgress(matched: matched, total: entries.length, phase: ImportPhase.done),
    );
    return out;
  }

  // -------------------------------------------------------------- provider I/O

  Future<ImportedSource?> _readYoutube(String listId) async {
    try {
      final response = await _dio.get<String>(
        'https://www.youtube.com/playlist',
        queryParameters: {'list': listId, 'hl': 'en'},
        options: Options(responseType: ResponseType.plain),
      );
      final html = response.data;
      if (html == null || html.isEmpty) return null;

      final name = _ogTitle(html) ?? 'Imported YouTube Playlist';
      final entries = _youtubeEntries(html);
      if (entries.isEmpty) return null;
      return ImportedSource(name: name, entries: entries, provider: 'YOUTUBE');
    } catch (e) {
      debugPrint('YouTube playlist read failed: $e');
      return null;
    }
  }

  Future<ImportedSource?> _readSpotify(String playlistId) async {
    try {
      final response = await _dio.get<String>(
        'https://open.spotify.com/embed/playlist/$playlistId',
        options: Options(responseType: ResponseType.plain),
      );
      final html = response.data;
      if (html == null || html.isEmpty) return null;

      final payload = _nextData(html);
      if (payload == null) return null;

      final entity = _findEntity(payload);
      if (entity == null) return null;

      final name = Fmt.cleanTitle(entity['name']?.toString() ?? 'Imported Spotify Playlist');
      final entries = <ImportedEntry>[];
      for (final raw in _asList(entity['trackList'])) {
        final title = raw['title']?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        entries.add(
          ImportedEntry(
            title: Fmt.cleanTitle(title),
            artist: Fmt.cleanTitle(raw['subtitle']?.toString() ?? ''),
          ),
        );
      }

      if (entries.isEmpty) return null;
      return ImportedSource(name: name, entries: entries, provider: 'SPOTIFY');
    } catch (e) {
      debugPrint('Spotify playlist read failed: $e');
      return null;
    }
  }

  Future<ImportedSource?> _readOpenGraph(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) return null;
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final html = response.data;
      if (html == null || html.isEmpty) return null;

      final title = _ogTitle(html);
      final entries = _youtubeEntries(html);
      if (title == null && entries.isEmpty) return null;
      return ImportedSource(
        name: title ?? 'Imported Playlist',
        entries: entries,
        provider: 'SOURCE',
      );
    } catch (e) {
      debugPrint('Generic playlist read failed: $e');
      return null;
    }
  }

  // ------------------------------------------------------------------ parsing

  String? _ogTitle(String html) {
    final match = RegExp(
      r'<meta[^>]+property="og:title"[^>]+content="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    final raw = match?.group(1);
    if (raw == null || raw.trim().isEmpty) return null;
    return Fmt.cleanTitle(_unescape(raw));
  }

  /// YouTube embeds its entire initial payload in `ytInitialData`. Rather than
  /// modelling that schema (which changes), the renderer blocks are walked with
  /// a tolerant scan that survives new keys and renamed shelves.
  List<ImportedEntry> _youtubeEntries(String html) {
    final entries = <ImportedEntry>[];
    final seen = <String>{};

    final block = RegExp(r'"playlistVideoRenderer":\{(.{0,4000}?)"navigationEndpoint"',
        dotAll: true);

    for (final match in block.allMatches(html)) {
      final chunk = match.group(1);
      if (chunk == null) continue;

      final videoId = RegExp(r'"videoId":"([A-Za-z0-9_-]{6,})"').firstMatch(chunk)?.group(1);
      if (videoId == null || !seen.add(videoId)) continue;

      final title = _firstTextField(chunk, 'title');
      if (title == null || title.isEmpty) continue;

      final artist = _firstTextField(chunk, 'longBylineText') ??
          _firstTextField(chunk, 'shortBylineText') ??
          _firstTextField(chunk, 'ownerText') ??
          '';

      entries.add(
        ImportedEntry(
          title: Fmt.cleanTitle(_unescape(title)),
          artist: Fmt.cleanTitle(_unescape(artist)),
        ),
      );
    }

    return entries;
  }

  /// Pulls the first human-readable string out of a named YouTube text field,
  /// handling both `{"runs":[{"text":…}]}` and `{"simpleText":…}` shapes.
  String? _firstTextField(String chunk, String field) {
    final start = chunk.indexOf('"$field":');
    if (start < 0) return null;
    final slice = chunk.substring(start, (start + 400).clamp(0, chunk.length));

    final simple = RegExp(r'"simpleText":"((?:[^"\\]|\\.)*)"').firstMatch(slice);
    if (simple != null) return _unescape(simple.group(1)!);

    final run = RegExp(r'"runs":\[\{"text":"((?:[^"\\]|\\.)*)"').firstMatch(slice);
    return run == null ? null : _unescape(run.group(1)!);
  }

  Map<String, dynamic>? _nextData(String html) {
    final match = RegExp(
      r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    final raw = match?.group(1);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// Depth-first search for the node that actually holds the track list.
  Map<String, dynamic>? _findEntity(Object? node, [int depth = 0]) {
    if (depth > 12) return null;
    if (node is Map) {
      final map = node.cast<String, dynamic>();
      if (map['trackList'] is List && map['trackList'].isNotEmpty) return map;
      for (final value in map.values) {
        final found = _findEntity(value, depth + 1);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findEntity(value, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _asList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  static String _unescape(String input) => input
      .replaceAll(r'\u0026', '&')
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', r'\');

  // ---------------------------------------------------------------- matching

  /// Picks the JioSaavn rendition that really is this song, or `null` rather
  /// than importing the wrong track.
  Track? _bestMatch(ImportedEntry entry, List<Track> candidates) {
    if (candidates.isEmpty) return null;

    final wantTitle = _normalise(entry.title);
    final wantArtist = _normalise(entry.artist);

    Track? best;
    var bestScore = 0.0;

    for (final candidate in candidates.take(8)) {
      final haveTitle = _normalise(candidate.title);
      final haveArtist = _normalise(candidate.artist);

      var score = 0.0;
      if (haveTitle == wantTitle) {
        score += 0.72;
      } else if (haveTitle.contains(wantTitle) || wantTitle.contains(haveTitle)) {
        score += 0.52;
      } else {
        score += 0.45 * _tokenOverlap(wantTitle, haveTitle);
      }

      if (wantArtist.isNotEmpty && haveArtist.isNotEmpty) {
        score += 0.28 * _tokenOverlap(wantArtist, haveArtist);
      } else {
        score += 0.12;
      }

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return bestScore >= 0.55 ? best : null;
  }

  static String _normalise(String input) {
    final cleaned = Fmt.cleanTitle(input).toLowerCase();
    return cleaned
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double _tokenOverlap(String a, String b) {
    final left = a.split(' ').where((t) => t.length > 1).toSet();
    final right = b.split(' ').where((t) => t.length > 1).toSet();
    if (left.isEmpty || right.isEmpty) return 0;
    final shared = left.intersection(right).length;
    return shared / left.length.clamp(1, 100);
  }
}

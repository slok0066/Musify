import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/utils/formatters.dart';
import '../models/track.dart';

typedef CanvasRemuxer = Future<bool> Function(
  String inputPath,
  String outputPath,
  int maxDurationMs,
);

class _CachedCanvas {
  _CachedCanvas(this.url, this.expiresAt);
  final String url;
  final DateTime expiresAt;
  bool get isValid => DateTime.now().isBefore(expiresAt);
}

/// Multi-source High-Definition Video Engine for Canvas playback.
///
/// Sources:
/// 1. Apple Music Video HD (1080p Full HD preview via iTunes).
/// 2. YouTube HD H.264 (720p/1080p): downloads a 10–15 s DASH clip via bounded
///    HTTP 206 ranges and losslessly remuxes it on Android via `MediaExtractor`
///    + `MediaMuxer` into a clean, standard non-fragmented local `.mp4` so
///    ExoPlayer loops it from disk with zero freezing or buffering stalls.
/// 3. Progressive muxed MP4 fallback + disk/memory cache.
class CanvasClient {
  CanvasClient(
    this._dio, [
    YoutubeExplode? explorer,
    @visibleForTesting this.remuxOverride,
    @visibleForTesting this.cacheDirOverride,
  ]) : _explorer = explorer;

  final Dio _dio;
  YoutubeExplode? _explorer;
  final CanvasRemuxer? remuxOverride;
  final Future<Directory> Function()? cacheDirOverride;
  HttpClient? _http;

  YoutubeExplode get _yt => _explorer ??= YoutubeExplode();
  HttpClient get _httpClient => _http ??= (HttpClient()
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 6)
    ..idleTimeout = const Duration(seconds: 15));

  static const MethodChannel _remuxChannel =
      MethodChannel('com.musify.musify/canvas_remux');
  static const String _itunesBase = 'https://itunes.apple.com';
  static const Duration _cacheTtl = Duration(hours: 3);
  static const int _probeSize = 64 * 1024;
  static const int _chunkSize = 512 * 1024;
  static const int _maxClipBytes = 10 * 1024 * 1024;
  static const int _maxDiskClips = 10;

  final Map<String, _CachedCanvas> _cache = {};

  Future<String?> fetch(Track track) async {
    final key = track.dedupeKey;
    final cached = _cache[key];
    if (cached != null && cached.isValid && _localFileValid(cached.url)) {
      // ignore: avoid_print
      print('[CANVAS] Cache hit for $key -> ${cached.url}');
      return cached.url;
    }

    // ignore: avoid_print
    print('[CANVAS] Fetching canvas for "${track.title}" by "${track.displayArtist}"');
    final url = await _fetchUncached(track);
    if (url != null) {
      _cache[key] = _CachedCanvas(url, DateTime.now().add(_cacheTtl));
    }
    // ignore: avoid_print
    print('[CANVAS] Result for "${track.title}": $url');
    return url;
  }

  Future<String?> _fetchUncached(Track track) async {
    final title = _cleanTitle(track.title);
    final artists = _artistList(track.displayArtist);
    final primaryArtist = artists.isNotEmpty ? artists.first : '';

    // Direct resolve if the track already carries a YouTube video ID
    final existingVideoId = track.videoId;
    if (existingVideoId != null && existingVideoId.isNotEmpty) {
      final streamUrl = await _resolveStream(track, existingVideoId);
      if (streamUrl != null) return streamUrl;
    }

    // Strategy 1: Apple Music Video HD (1080p Full HD, 1920w)
    final itunesQueries = <String>[
      if (primaryArtist.isNotEmpty) '$primaryArtist $title',
      title,
      for (final a in artists.skip(1).take(2)) '$a $title',
    ];

    // Strategy 2: YouTube Search via Innertube API + local remuxed 10–15s MP4
    final queries = <String>[
      if (primaryArtist.isNotEmpty) '$title $primaryArtist official video',
      '$title official video',
      if (primaryArtist.isNotEmpty) '$primaryArtist $title',
      title,
    ];

    // Race Apple iTunes (priority for 1080p without credits) and YouTube in parallel
    final itunesFuture = _searchItunesQueries(itunesQueries, title);
    final ytFuture = _searchYoutubeQueries(queries, track);

    final itunesUrl = await itunesFuture;
    if (itunesUrl != null && itunesUrl.isNotEmpty) {
      return itunesUrl;
    }

    return await ytFuture;
  }

  Future<String?> _searchItunesQueries(List<String> itunesQueries, String title) async {
    for (final itunesQuery in itunesQueries) {
      for (final country in const ['IN', 'US', 'GB']) {
        final itunesUrl = await _itunesSearch(
          itunesQuery,
          country: country,
          expectedTitle: title,
        );
        if (itunesUrl != null) return itunesUrl;
      }
    }
    return null;
  }

  Future<String?> _searchYoutubeQueries(List<String> queries, Track track) async {
    for (final query in queries) {
      final videoId = await _searchInnertube(query);
      if (videoId != null && videoId.isNotEmpty) {
        final streamUrl = await _resolveStream(track, videoId);
        if (streamUrl != null) return streamUrl;
      }
    }
    return null;
  }

  Future<String?> _searchInnertube(String query) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'https://www.youtube.com/youtubei/v1/search?prettyPrint=false',
        data: {
          'context': {
            'client': {
              'clientName': 'WEB',
              'clientVersion': '2.20231201.00.00',
              'hl': 'en',
              'gl': 'US',
            },
          },
          'query': query,
        },
        options: Options(
          headers: {'User-Agent': 'Mozilla/5.0'},
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );

      final data = response.data;
      if (data == null) return null;
      final raw = jsonEncode(data);
      final match = RegExp(r'"videoId":\s*"([a-zA-Z0-9_-]{11})"').firstMatch(raw);
      return match?.group(1);
    } catch (e) {
      debugPrint('Innertube search error for "$query": $e');
      return null;
    }
  }

  Future<String?> _resolveStream(Track track, String videoId) async {
    try {
      // Reuse already-remuxed local MP4 if still cached on disk.
      final cacheDir = await _getCacheDir();
      final safeId = videoId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      if (cacheDir != null) {
        final existing = File(
          '${cacheDir.path}${Platform.pathSeparator}canvas_$safeId.mp4',
        );
        if (existing.existsSync() && existing.lengthSync() > 32 * 1024) {
          return existing.path;
        }
      }

      final manifest = await _yt.videos.streams
          .getManifest(videoId, ytClients: [YoutubeApiClient.android])
          .timeout(const Duration(seconds: 6));

      // 1. Download a 10–15 s H.264 DASH clip and remux natively to standard MP4.
      if (cacheDir != null && (remuxOverride != null || Platform.isAndroid)) {
        final avcStreams = manifest.videoOnly
            .where((s) =>
                s.container.name == 'mp4' &&
                s.videoCodec.toLowerCase().startsWith('avc'))
            .toList()
          ..sort(_compareHdStreams);

        for (final stream in avcStreams.take(2)) {
          final localMp4 = await _downloadAndRemuxClip(
            stream.url,
            stream.size.totalBytes,
            cacheDir,
            safeId,
          );
          if (localMp4 != null) return localMp4;
        }
      }

      // 2. Progressive muxed MP4 fallback (accepts `Range: bytes=0-` directly).
      final muxedMp4 = manifest.muxed
          .where((s) => s.container.name == 'mp4')
          .toList()
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

      if (muxedMp4.isNotEmpty) {
        return muxedMp4.first.url.toString();
      }

      if (manifest.muxed.isNotEmpty) {
        return manifest.muxed.first.url.toString();
      }

      return null;
    } catch (e) {
      debugPrint('Failed to resolve stream for videoId $videoId: $e');
      return null;
    }
  }

  /// Prefer 720p30 (sharp behind the dimmed Now Playing scrim, ~1.5 MB for
  /// 12–15 s, effortless hardware decode), then 1080p30, 720p60, 1080p60.
  static int _compareHdStreams(VideoOnlyStreamInfo a, VideoOnlyStreamInfo b) {
    int rank(VideoOnlyStreamInfo s) {
      final q = s.qualityLabel;
      if (q.contains('720') && !q.contains('60')) return 4;
      if (q.contains('1080') && !q.contains('60')) return 3;
      if (q.contains('720')) return 2;
      if (q.contains('1080')) return 1;
      return 0;
    }

    final diff = rank(b).compareTo(rank(a));
    if (diff != 0) return diff;
    return b.bitrate.compareTo(a.bitrate);
  }

  Future<Directory?> _getCacheDir() async {
    try {
      final base = cacheDirOverride != null
          ? await cacheDirOverride!()
          : await getTemporaryDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}canvas_cache');
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Fetches 2–3 consecutive DASH segments (~10–15 s, skipping studio intros
  /// on full music videos) into a temporary `.fmp4` and remuxes natively via
  /// Android `MediaExtractor` + `MediaMuxer` into a clean standard `.mp4`.
  Future<String?> _downloadAndRemuxClip(
    Uri upstreamUrl,
    int declaredBytes,
    Directory cacheDir,
    String safeId,
  ) async {
    final sep = Platform.pathSeparator;
    final rawFile = File('${cacheDir.path}${sep}raw_$safeId.fmp4');
    final outFile = File('${cacheDir.path}${sep}canvas_$safeId.mp4');

    try {
      final probeEnd = declaredBytes > 0
          ? math.min(_probeSize - 1, declaredBytes - 1)
          : _probeSize - 1;
      final head = await _fetchRange(
        upstreamUrl,
        0,
        probeEnd,
        timeout: const Duration(seconds: 5),
      );
      if (head == null || head.isEmpty) return null;

      int? ftypStart, ftypEnd;
      int? moovStart, moovEnd;
      int? sidxStart, sidxEnd;

      var off = 0;
      while (off + 8 <= head.length) {
        final sz = _u32(head, off);
        if (sz < 8 || off + sz > head.length) break;
        final tp = _fourcc(head, off + 4);
        if (tp == 'ftyp') {
          ftypStart = off;
          ftypEnd = off + sz;
        } else if (tp == 'moov') {
          moovStart = off;
          moovEnd = off + sz;
        } else if (tp == 'sidx') {
          sidxStart = off;
          sidxEnd = off + sz;
          break;
        }
        off += sz;
      }

      if (ftypStart == null || moovStart == null || sidxStart == null) {
        return null;
      }

      final frags = _parseSidx(head, sidxStart, sidxEnd!);
      if (frags == null || frags.isEmpty) return null;

      final totalUs = frags.last.startUs + frags.last.durUs;
      var startIdx = 0;
      if (totalUs > 35 * 1000000) {
        final afterIntro = frags.indexWhere((f) => f.startUs >= 18 * 1000000);
        if (afterIntro >= 0) startIdx = afterIntro;
        while (startIdx > 0 && totalUs - frags[startIdx].startUs < 10 * 1000000) {
          startIdx--;
        }
      }

      var endIdx = startIdx;
      var clipDurUs = frags[startIdx].durUs;
      var clipSegBytes = frags[startIdx].size;
      while (endIdx + 1 < frags.length && clipDurUs < 11 * 1000000) {
        final next = frags[endIdx + 1];
        if (clipDurUs >= 10 * 1000000 && clipDurUs + next.durUs > 16 * 1000000) {
          break;
        }
        if (clipSegBytes + next.size > _maxClipBytes) break;
        endIdx++;
        clipDurUs += next.durUs;
        clipSegBytes += next.size;
      }

      if (clipSegBytes <= 0 || clipSegBytes > _maxClipBytes) return null;

      final byteStart = frags[startIdx].offset;
      final byteEnd = frags[endIdx].offset + frags[endIdx].size - 1;
      final segBuilder = BytesBuilder(copy: false);
      for (var cur = byteStart; cur <= byteEnd;) {
        final ce = math.min(cur + _chunkSize - 1, byteEnd);
        var chunk = await _fetchRange(upstreamUrl, cur, ce);
        if (chunk == null || chunk.isEmpty) {
          chunk = await _fetchRange(upstreamUrl, cur, ce);
        }
        if (chunk == null || chunk.isEmpty) return null;
        segBuilder.add(chunk);
        cur += chunk.length;
      }

      final segBytes = segBuilder.takeBytes();
      if (segBytes.length != clipSegBytes) return null;

      final rawBuilder = BytesBuilder(copy: false)
        ..add(Uint8List.sublistView(head, ftypStart, ftypEnd!))
        ..add(Uint8List.sublistView(head, moovStart, moovEnd!))
        ..add(segBytes);
      await rawFile.writeAsBytes(rawBuilder.takeBytes(), flush: true);

      final remuxed = await _remuxToMp4(rawFile.path, outFile.path, 16000);
      if (!remuxed || !outFile.existsSync() || outFile.lengthSync() < 32 * 1024) {
        return null;
      }

      _pruneCacheDir(cacheDir, keepPath: outFile.path);
      return outFile.path;
    } catch (e) {
      debugPrint('[CANVAS] Clip build/remux failed for $safeId: $e');
      return null;
    } finally {
      if (rawFile.existsSync()) {
        try {
          rawFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<bool> _remuxToMp4(
    String inputPath,
    String outputPath,
    int maxDurationMs,
  ) async {
    if (remuxOverride != null) {
      return remuxOverride!(inputPath, outputPath, maxDurationMs);
    }
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _remuxChannel.invokeMethod<bool>('remuxToMp4', {
        'inputPath': inputPath,
        'outputPath': outputPath,
        'maxDurationMs': maxDurationMs,
      });
      return ok == true;
    } catch (e) {
      debugPrint('[CANVAS] Native remux error: $e');
      return false;
    }
  }

  void _pruneCacheDir(Directory dir, {required String keepPath}) {
    try {
      final clips = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp4') && f.path != keepPath)
          .toList()
        ..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      final excess = clips.length - (_maxDiskClips - 1);
      for (var i = 0; i < excess; i++) {
        try {
          clips[i].deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<Uint8List?> _fetchRange(
    Uri url,
    int start,
    int end, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final req = await _httpClient.getUrl(url).timeout(timeout);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      final res = await req.close().timeout(timeout);

      if (res.statusCode != HttpStatus.partialContent &&
          res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        return null;
      }

      final builder = BytesBuilder(copy: false);
      await for (final data in res.timeout(timeout)) {
        builder.add(data);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    }
  }

  static List<({int offset, int size, int startUs, int durUs})>? _parseSidx(
    Uint8List d,
    int boxStart,
    int boxEnd,
  ) {
    final payload = boxStart + 8;
    if (boxEnd - payload < 24) return null;
    final version = d[payload];
    var at = payload + 8; // version/flags (4) + reference_id (4)
    final timescale = _u32(d, at);
    at += 4;
    if (timescale <= 0) return null;

    final int earliest;
    final int firstOffset;
    if (version == 0) {
      if (at + 8 > boxEnd) return null;
      earliest = _u32(d, at);
      firstOffset = _u32(d, at + 4);
      at += 8;
    } else {
      if (at + 16 > boxEnd) return null;
      earliest = _u64(d, at);
      firstOffset = _u64(d, at + 8);
      at += 16;
    }
    at += 2; // reserved
    if (at + 2 > boxEnd) return null;
    final refCount = (d[at] << 8) | d[at + 1];
    at += 2;

    var curOffset = boxEnd + firstOffset;
    var curTimeUs = (earliest * 1000000) ~/ timescale;
    final out = <({int offset, int size, int startUs, int durUs})>[];
    for (var i = 0; i < refCount; i++) {
      if (at + 12 > boxEnd) break;
      final size = _u32(d, at) & 0x7FFFFFFF;
      final durUnits = _u32(d, at + 4);
      at += 12;
      final durUs = (durUnits * 1000000) ~/ timescale;
      out.add((offset: curOffset, size: size, startUs: curTimeUs, durUs: durUs));
      curOffset += size;
      curTimeUs += durUs;
    }
    return out;
  }

  static String _fourcc(Uint8List d, int o) =>
      String.fromCharCodes(Uint8List.sublistView(d, o, o + 4));

  static int _u32(Uint8List d, int o) =>
      (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];

  static int _u64(Uint8List d, int o) => (_u32(d, o) << 32) | _u32(d, o + 4);

  Future<String?> _itunesSearch(
    String term, {
    required String country,
    required String expectedTitle,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '$_itunesBase/search',
        queryParameters: {
          'term': term,
          'entity': 'musicVideo',
          'country': country,
          'limit': '5',
        },
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
          validateStatus: (code) => code != null && code < 500,
        ),
      );

      final raw = response.data;
      if (raw is! String || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final results = decoded['results'];
      if (results is! List || results.isEmpty) return null;

      for (final first in results) {
        if (first is! Map) continue;

        final trackName = (first['trackName'] ?? '').toString().toLowerCase();
        final expected = expectedTitle.toLowerCase();
        if (!trackName.contains(expected) && !expected.contains(trackName)) {
          continue;
        }

        final previewUrl = first['previewUrl']?.toString();
        if (previewUrl == null || previewUrl.isEmpty) continue;

        if (previewUrl.contains('1920w') ||
            previewUrl.contains('1080') ||
            previewUrl.contains('720')) {
          return previewUrl;
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  void close() {
    _explorer?.close();
    _http?.close(force: true);
    _http = null;
  }

  /// Returns false only for a local file path that no longer exists on disk.
  static bool _localFileValid(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return true;
    final path = url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
    final file = File(path);
    return file.existsSync() && file.lengthSync() > 32 * 1024;
  }

  static String _cleanTitle(String raw) {
    var s = Fmt.cleanTitle(raw);
    while (s.contains('(') && s.contains(')')) {
      s = s.replaceAll(RegExp(r'\([^()]*\)'), '');
    }
    while (s.contains('[') && s.contains(']')) {
      s = s.replaceAll(RegExp(r'\[[^\[\]]*\]'), '');
    }
    s = s.replaceAll(RegExp(r'\s*[-–—|/]+\s*.*$'), '');
    s = s.replaceAll(RegExp(r'[()\[\]]'), '');
    return s.trim();
  }

  static List<String> _artistList(String raw) {
    return raw
        .split(RegExp(r'[,&]|\bfeat\.?\b|\bft\.?\b|\bwith\b', caseSensitive: false))
        .map((p) => Fmt.cleanTitle(p).trim())
        .where((p) => p.isNotEmpty && p.toLowerCase() != 'unknown')
        .toList();
  }
}

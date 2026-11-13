import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../data/models/track.dart';
import 'yt_first_config.dart';
import 'yt_first_search.dart';

class _CachedCandidate {
  _CachedCandidate(this.candidate, this.expiresAt);
  final YtAudioCandidate candidate;
  final DateTime expiresAt;
  bool get isValid => DateTime.now().isBefore(expiresAt);
}

/// YouTube as the primary source for the `test-yt-first` branch.
///
/// Search and playback query `youtube_explode_dart` first, then Invidious, then Piped.
/// Candidates are pre-cached with a 4-hour TTL for instant start (< 500 ms).
/// Playback ranks itag 140 AAC-LC, streaming progressively through [MediaCache]
/// and indexed directly using `sidx` fragmented MP4 boundaries.
class YoutubeService {
  YoutubeService({Dio? dio, YoutubeExplode? explorer})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: YtFirstConfig.requestTimeout,
                receiveTimeout: YtFirstConfig.requestTimeout,
                sendTimeout: YtFirstConfig.requestTimeout,
                headers: {'user-agent': YtFirstConfig.browserUserAgent},
              ),
            ),
        _explorer = explorer;

  final Dio _dio;
  YoutubeExplode? _explorer;

  YoutubeExplode get _yt => _explorer ??= YoutubeExplode();

  final Map<String, _CachedCandidate> _candidateCache = {};

  /// Prefetches and caches audio candidates for [track] ahead of playback.
  void prefetchCandidate(Track track) {
    final videoId = track.videoId;
    if (videoId == null) return;
    final cached = _candidateCache[videoId];
    if (cached != null && cached.isValid) return;
    unawaited(resolveAudioCandidate(track));
  }

  /// YouTube results, or an empty list when every YouTube path failed.
  Future<List<Track>> search(String query, {int page = 1}) async {
    final explode = await _explodeSearch(query, page: page);
    if (explode.isNotEmpty) return explode;
    return _pipedSearch(query, page: page);
  }

  /// Path of a previous staging of [track] still in the temp folder, or `null`.
  Future<String?> stagedPath(Track track) async {
    final videoId = track.videoId;
    if (videoId == null) return null;
    return _stagedFile(videoId);
  }

  /// Resolves playable streaming audio candidates (AAC/MP4 preferred
  /// for incremental fMP4 decoding) without performing a full download.
  ///
  /// Invidious proxy candidates are yielded first: their `/latest_version`
  /// endpoint redirects to streams signed with a PO token, avoiding the 403
  /// Forbidden errors returned by YouTube's direct CDN endpoints.
  Stream<YtAudioCandidate> resolveAudioCandidates(Track track) async* {
    final videoId = track.videoId;
    if (videoId == null) return;

    final cached = _candidateCache[videoId];
    if (cached != null && cached.isValid) {
      yield cached.candidate;
    }

    for (final candidate in _invidiousCandidates(videoId)) {
      _candidateCache[videoId] = _CachedCandidate(
        candidate,
        DateTime.now().add(const Duration(hours: 4)),
      );
      yield candidate;
    }

    final direct = await _explodeCandidates(videoId);
    for (final candidate
        in rankYtAudio(direct).where((c) => c.itag == 140 || c.isAacMp4)) {
      _candidateCache[videoId] = _CachedCandidate(
        candidate,
        DateTime.now().add(const Duration(hours: 4)),
      );
      yield candidate;
    }

    final piped = await _pipedCandidates(videoId);
    for (final candidate
        in rankYtAudio(piped).where((c) => c.itag == 140 || c.isAacMp4)) {
      _candidateCache[videoId] = _CachedCandidate(
        candidate,
        DateTime.now().add(const Duration(hours: 4)),
      );
      yield candidate;
    }
  }

  Future<YtAudioCandidate?> resolveAudioCandidate(Track track) async {
    try {
      return await resolveAudioCandidates(track).first;
    } catch (_) {
      return null;
    }
  }

  /// Downloads the best playable audio for [track] and returns its local path.
  ///
  /// Returns `null` when both stream candidates and the resolve failed; the
  /// repository then tries the Saavn match.
  Future<String?> stage(
    Track track, {
    ValueChanged<double?>? onProgress,
  }) async {
    final videoId = track.videoId;
    if (videoId == null) return null;

    // A finished staging is already playable: skip the resolve, its 403 and
    // the proxy round trip entirely. This is what makes a replay instant.
    final cached = await _stagedFile(videoId);
    if (cached != null) return cached;

    final proxied = await _stageFirst(
      track,
      _invidiousCandidates(videoId),
      maxAttempts: 1,
      onProgress: onProgress,
    );
    if (proxied != null) return proxied;

    final staged = await _stageFirst(
      track,
      await _explodeCandidates(videoId),
      maxAttempts: 2,
      onProgress: onProgress,
    );
    if (staged != null) return staged;

    final piped = await _stageFirst(
      track,
      await _pipedCandidates(videoId),
      maxAttempts: 1,
      onProgress: onProgress,
    );
    if (piped != null) return piped;

    debugPrint(
      'yt-first playback FAIL source=none title="${track.title}" '
      'host=- error=no playable stream',
    );
    return null;
  }

  Future<String?> _stageFirst(
    Track track,
    List<YtAudioCandidate> candidates, {
    required int maxAttempts,
    ValueChanged<double?>? onProgress,
  }) async {
    var attempts = 0;
    for (final candidate in rankYtAudio(candidates)) {
      if (attempts == maxAttempts) break;
      attempts++;
      final path = await _download(track, candidate, onProgress: onProgress);
      if (path != null) return path;
    }
    return null;
  }

  Future<List<Track>> _pipedSearch(String query, {int page = 1}) async {
    for (final base in YtFirstConfig.pipedInstances) {
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '$base/search',
          queryParameters: {
            'q': query,
            'filter': 'music_songs',
            if (page > 1) 'page': '$page',
          },
        );
        final items = response.data?['items'];
        if (items is! List) continue;

        final out = <Track>[];
        final seen = <String>{};
        for (final raw in items) {
          if (raw is! Map) continue;
          final item = raw.cast<Object?, Object?>();
          final videoId = _videoIdFromUrl(item['url']?.toString());
          if (videoId == null) continue;
          final seconds = _int(item['duration']);
          if (seconds <= 0) continue;

          final track = _track(
            videoId: videoId,
            title: item['title']?.toString() ?? '',
            uploader: item['uploaderName']?.toString() ?? '',
            duration: Duration(seconds: seconds),
            thumbnail: item['thumbnail']?.toString() ?? '',
          );
          if (seen.add(track.dedupeKey)) out.add(track);
          if (out.length >= YtFirstConfig.maxSearchResults) break;
        }
        if (out.isNotEmpty) return out;
      } catch (e) {
        debugPrint('yt-first: Piped search failed on $base: $e');
      }
    }
    return const [];
  }

  Future<List<Track>> _explodeSearch(String query, {int page = 1}) async {
    try {
      VideoSearchList? searchList = await _yt.search
          .search(query, filter: TypeFilters.video)
          .timeout(YtFirstConfig.requestTimeout);

      for (var p = 1; p < page; p++) {
        final next = await searchList?.nextPage().timeout(
              YtFirstConfig.requestTimeout,
              onTimeout: () => null,
            );
        if (next == null || next.isEmpty) {
          searchList = null;
          break;
        }
        searchList = next;
      }
      if (searchList == null) return const [];

      final out = <Track>[];
      final seen = <String>{};
      for (final video in searchList) {
        if (video.isLive) continue;
        final track = _track(
          videoId: video.id.value,
          title: video.title,
          uploader: video.author,
          duration: video.duration ?? Duration.zero,
          thumbnail: video.thumbnails.mediumResUrl,
        );
        if (seen.add(track.dedupeKey)) out.add(track);
        if (out.length >= YtFirstConfig.maxSearchResults) break;
      }
      return out;
    } catch (e) {
      debugPrint('yt-first: YouTube search fallback failed: $e');
      return const [];
    }
  }

  Track _track({
    required String videoId,
    required String title,
    required String uploader,
    required Duration duration,
    required String thumbnail,
  }) {
    final parsed = YtTitles.parse(title, uploader);
    return Track(
      id: 'yt:$videoId',
      title: parsed.title,
      artist: parsed.artist,
      imageUrl: thumbnail,
      duration: duration,
      bitrate: 128,
      has320: false,
      permaUrl: 'https://www.youtube.com/watch?v=$videoId',
      source: TrackSource.youtube,
    );
  }

  Future<List<YtAudioCandidate>> _pipedCandidates(String videoId) async {
    for (final base in YtFirstConfig.pipedInstances) {
      try {
        final response =
            await _dio.get<Map<String, dynamic>>('$base/streams/$videoId');
        final data = response.data;
        if (data == null || data['error'] != null) continue;

        final streams = data['audioStreams'];
        if (streams is! List) continue;

        final out = <YtAudioCandidate>[];
        for (final raw in streams) {
          if (raw is! Map) continue;
          final stream = raw.cast<Object?, Object?>();
          final url = stream['url']?.toString() ?? '';
          if (!url.startsWith('http')) continue;

          final mime = stream['mimeType']?.toString() ??
              stream['format']?.toString() ??
              '';
          final codec = stream['codec']?.toString() ?? '';
          out.add(
            YtAudioCandidate(
              itag: _int(stream['itag']),
              container: _containerFor(mime.isEmpty ? codec : mime),
              codec: codec.isEmpty ? mime : codec,
              bitrateKbps: _int(stream['bitrate']),
              url: url,
              userAgent: YtFirstConfig.browserUserAgent,
              source: 'piped',
            ),
          );
        }
        if (out.isNotEmpty) return out;
      } catch (e) {
        debugPrint('yt-first: Piped streams failed on $base: $e');
      }
    }
    return const [];
  }

  /// The Invidious proxy's `/latest_version` redirects to a stream signed with
  /// a PO token; direct clients get 403 on label uploads without one.
  List<YtAudioCandidate> _invidiousCandidates(String videoId) {
    return [
      YtAudioCandidate(
        itag: 140,
        container: YtContainer.mp4,
        codec: 'mp4a',
        bitrateKbps: 128,
        url: '${YtFirstConfig.invidiousInstance}/latest_version'
            '?id=$videoId&itag=140&local=true',
        userAgent: YtFirstConfig.browserUserAgent,
        source: 'invidious',
      ),
    ];
  }

  /// `android` is the only client that resolves popular label uploads; `ios`
  /// and `androidVr` answer 403 or a sign-in prompt after several seconds, so
  /// Invidious takes over instead of paying for that timeout.
  Future<List<YtAudioCandidate>> _explodeCandidates(String videoId) async {
    const client = YoutubeApiClient.android;
    try {
      final manifest = await _yt.videos.streams
          .getManifest(videoId, ytClients: [client])
          .timeout(YtFirstConfig.requestTimeout);
      final ua = _userAgent(client);
      return [
        for (final stream in manifest.audioOnly)
          YtAudioCandidate(
            itag: stream.tag,
            container: _containerFor(stream.container.name),
            codec: stream.audioCodec,
            bitrateKbps: stream.bitrate.kiloBitsPerSecond.round(),
            url: stream.url.toString(),
            userAgent: ua,
            source: 'youtube_explode_${_clientName(client)}',
          ),
      ];
    } catch (e) {
      debugPrint(
        'yt-first: YouTube streams failed with ${_clientName(client)}: $e',
      );
      return const [];
    }
  }

  Future<String?> _download(
    Track track,
    YtAudioCandidate candidate, {
    ValueChanged<double?>? onProgress,
  }) async {
    final host = Uri.tryParse(candidate.url)?.host ?? 'unknown';
    final extension = candidate.container == YtContainer.webm ? 'webm' : 'm4a';
    final watch = Stopwatch()..start();
    File? part;
    try {
      final dir = await _stagingDir();
      final target = File(
        '${dir.path}${Platform.pathSeparator}'
        'yt_${track.videoId}_${candidate.itag}.$extension',
      );
      if (target.existsSync() && await target.length() > 0) return target.path;

      part = File('${target.path}.part');
      if (part.existsSync()) await part.delete();

      final response = await _dio.download(
        candidate.url,
        part.path,
        deleteOnError: true,
        options: Options(headers: {
          'user-agent': candidate.userAgent,
          // YouTube throttles a full GET to ~32 KB/s; a range request is not
          // throttled and fetches the same whole file at full speed.
          'range': 'bytes=0-',
        }, receiveTimeout: YtFirstConfig.downloadTimeout),
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );

      // A dropped connection ends the body early without throwing, and the
      // short MP4 then plays a few seconds and stops. Only a body of the
      // promised size, and never an HTML error page, may be handed on.
      final length = await part.length();
      final declared = _declaredBytes(response.headers);
      final type = response.headers.value(Headers.contentTypeHeader) ?? '';
      if (type.contains('text/html')) {
        throw FormatException('error page instead of audio ($length bytes)');
      }
      if (length == 0 || (declared != null && length != declared)) {
        throw FormatException('body is $length of ${declared ?? '?'} bytes');
      }

      if (target.existsSync()) await target.delete();
      await part.rename(target.path);
      debugPrint(
        'yt-first playback OK source=${candidate.source} '
        'title="${track.title}" itag=${candidate.itag} '
        'bytes=$length ms=${watch.elapsedMilliseconds}',
      );
      return target.path;
    } catch (e) {
      debugPrint(
        'yt-first playback FAIL source=${candidate.source} '
        'title="${track.title}" host=$host itag=${candidate.itag} error=$e',
      );
      try {
        if (part != null && part.existsSync()) await part.delete();
      } catch (_) {}
      return null;
    }
  }

  /// A previous staging of [videoId] that is still in the temp folder.
  Future<String?> _stagedFile(String videoId) async {
    final dir = await _stagingDir();
    for (final itag in const [140, 139]) {
      final file = File(
        '${dir.path}${Platform.pathSeparator}yt_${videoId}_$itag.m4a',
      );
      if (file.existsSync() && await file.length() > 0) return file.path;
    }
    return null;
  }

  /// Where staged audio lands.
  // shortcut: this is the OS cache folder, which the system may clear but this
  // app never prunes; add age-based cleanup if the test becomes permanent.
  Future<Directory> _stagingDir() async {
    final root = await getTemporaryDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}musify_yt');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// The whole-file size the response promised: a 206 totals it in
  /// `content-range`, a plain 200 in `content-length`.
  static int? _declaredBytes(Headers headers) {
    final range = headers.value('content-range');
    if (range != null) {
      final slash = range.lastIndexOf('/');
      final total = slash < 0 ? null : int.tryParse(range.substring(slash + 1));
      if (total != null && total > 0) return total;
    }
    final length = int.tryParse(headers.value('content-length') ?? '');
    return length != null && length > 0 ? length : null;
  }

  static String _clientName(YoutubeApiClient client) {
    final context = client.payload['context'];
    if (context is Map) {
      final name = context['client'];
      if (name is Map) return name['clientName']?.toString() ?? 'unknown';
    }
    return 'unknown';
  }

  static String _userAgent(YoutubeApiClient client) {
    final context = client.payload['context'];
    if (context is Map) {
      final c = context['client'];
      if (c is Map) {
        final ua = c['userAgent'];
        if (ua is String && ua.isNotEmpty) return ua;
      }
    }
    return YtFirstConfig.browserUserAgent;
  }

  static YtContainer _containerFor(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('mp4') ||
        value.contains('m4a') ||
        value.contains('aac')) {
      return YtContainer.mp4;
    }
    if (value.contains('webm') ||
        value.contains('opus') ||
        value.contains('vorbis')) {
      return YtContainer.webm;
    }
    return YtContainer.other;
  }

  static String? _videoIdFromUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(
      raw.startsWith('http') ? raw : 'https://www.youtube.com$raw',
    );
    if (uri == null) return null;
    final fromQuery = uri.queryParameters['v'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    if (uri.host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return null;
  }

  static int _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}


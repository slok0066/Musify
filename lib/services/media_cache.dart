import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Where a cached file came from.
enum CacheEntryKind { stream, download }

/// A staged file plus its metadata.
class CacheEntry {
  const CacheEntry({
    required this.path,
    required this.bytes,
    required this.kind,
    required this.accessedAt,
  });

  final String path;
  final int bytes;
  final CacheEntryKind kind;
  final DateTime accessedAt;
}

/// Progress of an in-flight transfer.
class TransferProgress {
  const TransferProgress({
    required this.received,
    required this.total,
    required this.fraction,
  });

  const TransferProgress.indeterminate()
      : received = 0,
        total = 0,
        fraction = null;

  final int received;
  final int total;

  /// `null` when the server does not send `Content-Length`.
  final double? fraction;

  bool get isDeterminate => fraction != null;
}

/// What a one-byte range probe learned about a media URL.
class _Probe {
  const _Probe({required this.total, required this.dead});

  /// The file's full length, or `null` when the server refused ranges or did
  /// not report one.
  final int? total;

  /// The URL answered with an error page instead of media.
  final bool dead;
}

/// The single owner of every audio byte Musify writes to disk.
///
/// Two responsibilities, one implementation:
///
/// * **Rolling stream cache** — a bounded (500 MB) LRU of media fetched for
///   playback. Because `flutter_soloud` stages remote URLs by downloading them
///   in full before a single sample is decoded, Musify downloads deliberately:
///   it can then show real progress, reuse the file on every replay, prefetch
///   the next queue entry, and honour the Settings cache meter and
///   `CLEAR STREAM CACHE` button.
/// * **Offline downloads** — the same transfer written to a permanent folder,
///   so "download" and "cache" can never disagree about a file.
class MediaCache {
  MediaCache(this._dio);

  final Dio _dio;

  static const int maxCacheBytes = 20 * 1024 * 1024;
  static const Duration _staleAfter = Duration(hours: 12);

  /// Parallel connections used for one stream file when the CDN allows ranges.
  static const int laneCount = 4;

  /// Below this, splitting a transfer costs more than it saves.
  static const int chunkThreshold = 2 * 1024 * 1024;

  Directory? _cacheDir;
  Directory? _downloadsDir;

  final Map<String, String> _urlToPath = {};
  final ValueNotifier<int> cacheBytes = ValueNotifier<int>(0);
  final Map<String, CancelToken> _inFlight = {};

  /// Transfers that are written *and read at the same time* — the engine plays
  /// from them while the rest of the file is still arriving. See [openStream].
  final Map<String, _LiveTransfer> _live = {};

  /// Transfers whose reader has detached but which are still finishing so the
  /// track lands in the cache. Bounded by [_maxFinishers]: a listener who skips
  /// ten songs in a row must not open ten sockets.
  final List<_LiveTransfer> _finishers = [];

  static const int _maxFinishers = 2;

  /// Files smaller than this cannot hold a `moov` plus a single frame.
  static const int _minStreamBytes = 32 * 1024;

  bool get isReady => _cacheDir != null && _downloadsDir != null;

  /// How many read-while-writing transfers are running (diagnostics).
  int get activeStreams => _live.length;

  /// Points the cache at explicit directories.
  ///
  /// The app never calls this — `path_provider` decides where the bytes go —
  /// but tests need a cache that is a temporary folder rather than a device.
  @visibleForTesting
  Future<void> useDirectories({
    required Directory cache,
    required Directory downloads,
  }) async {
    _cacheDir = cache;
    _downloadsDir = downloads;
    await _cacheDir!.create(recursive: true);
    await _downloadsDir!.create(recursive: true);
  }

  Future<void> init() async {
    try {
      final root = await getApplicationSupportDirectory();
      _cacheDir = Directory('${root.path}${Platform.pathSeparator}stream_cache');
      _downloadsDir = Directory('${root.path}${Platform.pathSeparator}downloads');
      await _cacheDir!.create(recursive: true);
      await _downloadsDir!.create(recursive: true);
      await clearStreamCache();
      await _prune();
    } catch (e) {
      debugPrint('MediaCache init failed (playback will use direct URLs): $e');
    }
  }

  /// A stable, filesystem-safe name for a remote URL.
  String _fileNameFor(String url) {
    final uri = Uri.tryParse(url);
    final last = uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : 'audio';
    final safe = last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${url.hashCode.toUnsigned(20).toRadixString(36)}_$safe';
  }

  String? cachedPathFor(String url) {
    final known = _urlToPath[url];
    if (known != null && File(known).existsSync()) return known;

    final dir = _cacheDir;
    if (dir == null) return null;
    final candidate = File('${dir.path}${Platform.pathSeparator}${_fileNameFor(url)}');
    if (candidate.existsSync()) {
      _urlToPath[url] = candidate.path;
      return candidate.path;
    }
    return null;
  }

  /// Path of a completed offline download, or `null`.
  String? downloadedPathFor(String fileName) {
    final dir = _downloadsDir;
    if (dir == null || fileName.isEmpty) return null;
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    return file.existsSync() ? file.path : null;
  }

  /// Path of a completed stream-cache entry by its file name, or `null`.
  ///
  /// The mirror of [downloadedPathFor] for the rolling cache: the progressive
  /// player checks both before it touches the network.
  String? streamPathFor(String fileName) {
    final dir = _cacheDir;
    if (dir == null || fileName.isEmpty) return null;
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    return file.existsSync() ? file.path : null;
  }

  /// Makes sure [url] exists locally, returning its path.
  ///
  /// Returns `null` for [CacheEntryKind.stream] when the transfer fails — the
  /// caller can then hand the raw URL to the engine as a last resort.
  ///
  /// The transfer is split over [laneCount] connections whenever the server
  /// supports ranges. A 320 kbps track is ~10 MB and JioSaavn's CDN throttles a
  /// single socket well below a phone's bandwidth, so one connection used to
  /// mean 10–15 seconds of `BUFFERING` before the first sample; four of them
  /// land the same file in a fraction of that, and the bytes are still written
  /// through the same `.part` → rename path so a killed transfer can never
  /// masquerade as a playable file.
  Future<String?> ensure({
    required String url,
    required String fileName,
    CacheEntryKind kind = CacheEntryKind.stream,
    ValueChanged<TransferProgress>? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (url.isEmpty) return null;

    final targetDir = kind == CacheEntryKind.download ? _downloadsDir : _cacheDir;
    if (targetDir == null) return null;

    final target = File('${targetDir.path}${Platform.pathSeparator}$fileName');
    if (target.existsSync() && await target.length() > 0) {
      if (kind == CacheEntryKind.stream) {
        _urlToPath[url] = target.path;
        await _touch(target);
      }
      onProgress?.call(
        TransferProgress(
          received: await target.length(),
          total: await target.length(),
          fraction: 1,
        ),
      );
      return target.path;
    }

    // A live playback transfer already owns this URL's bytes: wait for it
    // rather than buying the same file a second time.
    if (kind == CacheEntryKind.stream) {
      final live = _live[url];
      if (live != null &&
          !live.failed &&
          !live.stopped &&
          live.target.path == target.path) {
        final path = await live.awaitComplete(onProgress: onProgress);
        if (path != null) return path;
      }
    }

    onProgress?.call(const TransferProgress.indeterminate());

    final partial = File('${target.path}.part');
    try {
      // 1. One probe request buys the length (so the file can be split) and
      //    catches a delisted rendition before a byte of its error page lands.
      final probe = await _probe(url, cancelToken);
      if (probe == null) return null;
      if (probe.dead) {
        debugPrint('MediaCache: $url answered with an error page, not audio');
        return null;
      }

      // 2. Several connections when the file is big enough to be worth it…
      final total = probe.total;
      var received = 0;
      if (total != null && total > chunkThreshold) {
        received = await _downloadChunked(
              url: url,
              partial: partial,
              total: total,
              cancelToken: cancelToken,
              onProgress: onProgress,
            ) ??
            0;
      }

      // 3. …one otherwise, or when the CDN refused ranges.
      if (received == 0) {
        received = await _downloadSingle(
              url: url,
              partial: partial,
              cancelToken: cancelToken,
              onProgress: onProgress,
            ) ??
            0;
      }
      if (received == 0) {
        await _safeDelete(partial);
        return null;
      }

      // 4. Whatever the headers claimed, the container's magic bytes have the
      //    final word.
      if (!await _fileLooksLikeAudio(partial)) {
        debugPrint('MediaCache: $url staged a non-audio payload');
        await _safeDelete(partial);
        return null;
      }

      onProgress?.call(
        TransferProgress(received: received, total: received, fraction: 1),
      );

      // Rename only once the whole body landed, so a killed transfer can never
      // masquerade as a playable file.
      final staged = await partial.rename(target.path);
      if (kind == CacheEntryKind.stream) {
        _urlToPath[url] = staged.path;
        await _recount();
        unawaited(_prune());
      }
      return staged.path;
    } on DioException catch (e) {
      await _safeDelete(partial);
      if (e.type == DioExceptionType.cancel) rethrow;
      debugPrint('MediaCache transfer failed for $url: ${e.type} ${e.message}');
      return null;
    } catch (e) {
      await _safeDelete(partial);
      debugPrint('MediaCache transfer failed for $url: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------- streaming

  /// Opens a **read-while-writing** transfer for [url].
  ///
  /// [ensure] answers "give me the whole file"; this answers "give me bytes as
  /// they land". The returned [StreamSession] can be read after ~200 ms (the
  /// MP4 header), and the engine decodes frames while the rest of the file is
  /// still on the wire — which is what makes a tap audible immediately instead
  /// of after a 10 MB download *plus* a full AAC decode.
  ///
  /// The transfer is not abandoned when playback detaches: it finishes in the
  /// background so the track still lands in the cache, and a later replay reads
  /// it straight from disk.
  ///
  /// Returns `null` when the URL is not audio, the server reports no length, or
  /// anything else makes streaming unsafe — the caller then falls back to the
  /// classic staged download.
  Future<StreamSession?> openStream({
    required String url,
    required String fileName,
    ValueChanged<TransferProgress>? onProgress,
  }) async {
    if (url.isEmpty || fileName.isEmpty) return null;
    final dir = _cacheDir;
    if (dir == null) return null;

    final target = File('${dir.path}${Platform.pathSeparator}$fileName');

    // 1. Already whole on disk: no network involved at all. This is the replay
    //    path, and it is instant even in flight mode.
    if (target.existsSync()) {
      final length = await target.length();
      if (length > 0) {
        _urlToPath[url] = target.path;
        await _touch(target);
        onProgress?.call(
          TransferProgress(received: length, total: length, fraction: 1),
        );
        return StreamSession._staged(target, length);
      }
    }

    // 2. A transfer is already running for this URL (the prefetch, or a second
    //    tap on the same song): attach to it instead of opening a second one.
    final existing = _live[url];
    if (existing != null) {
      if (!existing.failed &&
          !existing.stopped &&
          existing.target.path == target.path) {
        existing.attach();
        return StreamSession._live(existing);
      }
      await existing.abandon();
    }

    // 3. One probe buys the length (so the engine can be told the exact size)
    //    and rejects a delisted rendition before a byte of an error page lands.
    final probe = await _probe(url, null);
    final total = probe?.total;
    if (probe == null || probe.dead || total == null || total < _minStreamBytes) {
      if (probe != null && !probe.dead && total == null) {
        debugPrint('MediaCache: $url does not report a length, cannot stream');
      }
      return null;
    }

    final partial = File('${target.path}.part');

    // A second caller (a prefetch racing a tap) may have finished probing while
    // this one did. Attach to its transfer rather than opening a second
    // connection to the same file.
    final raced = _live[url];
    if (raced != null) {
      if (!raced.failed &&
          !raced.stopped &&
          raced.target.path == target.path) {
        raced.attach();
        return StreamSession._live(raced);
      }
      await raced.abandon();
    }

    await _safeDelete(partial);

    final transfer = _LiveTransfer(
      cache: this,
      url: url,
      target: target,
      partial: partial,
      total: total,
      onProgress: onProgress,
    );
    _live[url] = transfer;
    transfer.attach();
    unawaited(transfer.run());
    onProgress?.call(const TransferProgress.indeterminate());
    return StreamSession._live(transfer);
  }

  void _registerFinisher(_LiveTransfer transfer) {
    _finishers.remove(transfer);
    _finishers.add(transfer);
    while (_finishers.length > _maxFinishers) {
      final oldest = _finishers.removeAt(0);
      if (!oldest.complete && !oldest.stopped) unawaited(oldest.abandon());
    }
  }

  void _unregister(_LiveTransfer transfer) {
    _finishers.remove(transfer);
    _live.removeWhere((_, value) => identical(value, transfer));
  }

  /// True for a `.part` file a live transfer is writing right now. Pruning or
  /// clearing must skip those: deleting one would strand playback.
  bool _isLivePart(String path) {
    for (final transfer in _live.values) {
      if (transfer.partial.path == path) return true;
    }
    return false;
  }

  /// A one-byte range request: the cheapest way to learn a file's real length,
  /// whether the server honours `Range`, and whether the URL still resolves to
  /// audio at all.
  Future<_Probe?> _probe(String url, CancelToken? cancelToken) async {
    ResponseBody? body;
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          headers: const {'Accept': '*/*', 'Range': 'bytes=0-0'},
        ),
      );
      body = response.data;
      if (isErrorPage(response.headers.value(Headers.contentTypeHeader))) {
        return const _Probe(total: null, dead: true);
      }
      final ranged = response.statusCode == 206;
      final total = ranged
          ? _totalFromContentRange(response.headers.value('content-range'))
          : null;
      return _Probe(total: total, dead: false);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      debugPrint('MediaCache probe failed for $url: ${e.type} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('MediaCache probe failed for $url: $e');
      return null;
    } finally {
      // Drop the probe body: it is either one byte or a whole file we do not
      // want to pay for twice.
      await _abandon(body);
    }
  }

  /// Splits [total] bytes into contiguous `(start, end)` ranges, largest first
  /// so a slow lane cannot become the tail of the transfer.
  @visibleForTesting
  static List<(int, int)> chunkRanges(
    int total, {
    int lanes = laneCount,
    int minLaneBytes = 1 << 18,
  }) {
    if (total <= 0) return const [];
    final count = lanes < 1
        ? 1
        : (total / minLaneBytes).ceil().clamp(1, lanes);
    final per = (total / count).ceil();
    final out = <(int, int)>[];
    for (var i = 0; i < count; i++) {
      final start = i * per;
      if (start >= total) break;
      final end = (start + per - 1).clamp(0, total - 1);
      out.add((start, end));
    }
    return out;
  }

  /// Downloads [total] bytes over one connection per range, each into its own
  /// file, then concatenates them in order.
  ///
  /// Returns the bytes written, or `null` when any lane failed — the caller
  /// then re-runs the transfer over a single connection.
  Future<int?> _downloadChunked({
    required String url,
    required File partial,
    required int total,
    CancelToken? cancelToken,
    ValueChanged<TransferProgress>? onProgress,
  }) async {
    final ranges = chunkRanges(total);
    if (ranges.length < 2) return null;

    final lanes = [
      for (var i = 0; i < ranges.length; i++) File('${partial.path}.lane$i'),
    ];
    var received = 0;
    var reported = 0;

    void report() {
      if (received != total && received - reported < (1 << 16)) return;
      reported = received;
      onProgress?.call(
        TransferProgress(
          received: received,
          total: total,
          fraction: (received / total).clamp(0.0, 1.0),
        ),
      );
    }

    try {
      final results = await Future.wait([
        for (var i = 0; i < ranges.length; i++)
          _downloadLane(
            url: url,
            target: lanes[i],
            start: ranges[i].$1,
            end: ranges[i].$2,
            cancelToken: cancelToken,
            onBytes: (int bytes) {
              received += bytes;
              report();
            },
          ),
      ]);
      if (results.contains(false)) return null;
      report();

      // One sequential pass over the slices — a few milliseconds for ~10 MB.
      final sink = partial.openWrite();
      try {
        for (final lane in lanes) {
          await sink.addStream(lane.openRead());
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      var written = 0;
      for (final lane in lanes) {
        written += await lane.length();
      }
      if (written != total) {
        debugPrint('MediaCache chunked transfer short: $written of $total bytes');
        return null;
      }
      return written;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      debugPrint('MediaCache chunked transfer failed for $url: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('MediaCache chunked transfer failed for $url: $e');
      return null;
    } finally {
      for (final lane in lanes) {
        await _safeDelete(lane);
      }
    }
  }

  Future<bool> _downloadLane({
    required String url,
    required File target,
    required int start,
    required int end,
    required void Function(int bytes) onBytes,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          headers: {'Accept': '*/*', 'Range': 'bytes=$start-$end'},
        ),
      );

      final body = response.data;
      if (body == null) return false;

      final sink = target.openWrite();
      try {
        await for (final chunk in body.stream) {
          sink.add(chunk);
          onBytes(chunk.length);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      return await target.length() == end - start + 1;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      debugPrint('MediaCache lane $start-$end failed: ${e.type} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('MediaCache lane $start-$end failed: $e');
      return false;
    }
  }

  /// The original single-connection transfer — the fallback whenever the CDN
  /// does not honour `Range`, on every platform that streams without it, and
  /// the path a failed chunked attempt retries through.
  Future<int?> _downloadSingle({
    required String url,
    required File partial,
    CancelToken? cancelToken,
    ValueChanged<TransferProgress>? onProgress,
  }) async {
    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        headers: const {'Accept': '*/*'},
      ),
    );

    final body = response.data;
    if (body == null) return null;

    if (isErrorPage(response.headers.value(Headers.contentTypeHeader))) {
      debugPrint('MediaCache: $url answered with an error page, not audio');
      return null;
    }

    final total = int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        0;
    var received = 0;

    final sink = partial.openWrite();
    try {
      await for (final chunk in body.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          TransferProgress(
            received: received,
            total: total,
            fraction: total > 0 ? (received / total).clamp(0.0, 1.0) : null,
          ),
        );
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return received;
  }

  /// True when a `Content-Type` header describes an error page rather than a
  /// media container.
  @visibleForTesting
  static bool isErrorPage(String? contentType) {
    final type = (contentType ?? '').toLowerCase();
    return type.contains('text/html') ||
        type.contains('application/json') ||
        type.contains('xml');
  }

  /// Sniffs a payload's magic bytes. An MP4/M4A (what JioSaavn serves) starts
  /// with a box size followed by `ftyp`; MP3 with `ID3` or a frame sync.
  ///
  /// Public because the progressive player uses it to decide whether a payload
  /// can be fed to the engine raw.
  static bool looksLikeAudio({String? contentType, required List<int> head}) {
    if (head.isEmpty) return false;

    // An error page is never audio, whatever the headers claimed.
    final first = head.first;
    if (first == 0x3C || first == 0x7B || first == 0x5B) return false; // < { [

    final type = (contentType ?? '').toLowerCase();
    if (type.startsWith('audio/') || type.startsWith('video/')) return true;

    bool ascii(String value, [int at = 0]) {
      if (head.length < at + value.length) return false;
      for (var i = 0; i < value.length; i++) {
        if (head[at + i] != value.codeUnitAt(i)) return false;
      }
      return true;
    }

    if (ascii('ftyp', 4)) return true; // MP4 / M4A / AAC-in-MP4
    if (ascii('ID3')) return true; // MP3 with an ID3 tag
    if (ascii('OggS')) return true;
    if (ascii('fLaC')) return true;
    if (ascii('RIFF')) return true;
    if (head.length >= 2 && head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) {
      return true; // MPEG frame sync
    }
    return false;
  }

  Future<bool> _fileLooksLikeAudio(File file) async {
    try {
      final handle = await file.open();
      try {
        final head = await handle.read(16);
        return looksLikeAudio(head: head);
      } finally {
        await handle.close();
      }
    } catch (e) {
      // Unreadable for a reason we cannot see here: let the engine judge.
      debugPrint('MediaCache could not verify $file: $e');
      return true;
    }
  }

  static int? _totalFromContentRange(String? contentRange) {
    final header = contentRange;
    if (header == null) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0) return null;
    final value = header.substring(slash + 1).trim();
    if (value.isEmpty || value == '*') return null;
    return int.tryParse(value);
  }

  /// Closes a response we asked for but do not intend to read.
  Future<void> _abandon(ResponseBody? body) async {
    if (body == null) return;
    try {
      final subscription = body.stream.listen(null);
      await subscription.cancel();
    } catch (_) {
      // Already closed or never opened: nothing to release.
    }
  }

  /// Kicks off a background fetch (used to prefetch the next queue entry).
  /// Returns the staged path once the bytes have landed, or `null`.
  Future<String?> prefetch({
    required String url,
    required String fileName,
    CacheEntryKind kind = CacheEntryKind.stream,
  }) async {
    if (url.isEmpty) return null;
    final known = cachedPathFor(url);
    if (known != null) return known;
    if (_inFlight.containsKey(url)) return null;

    final token = CancelToken();
    _inFlight[url] = token;
    try {
      return await ensure(
        url: url,
        fileName: fileName,
        kind: kind,
        cancelToken: token,
      );
    } finally {
      _inFlight.remove(url);
    }
  }

  /// Size of the rolling stream cache on disk.
  Future<int> measureCache() async {
    final dir = _cacheDir;
    if (dir == null) return 0;
    var total = 0;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    } catch (e) {
      debugPrint('MediaCache measure failed: $e');
    }
    cacheBytes.value = total;
    return total;
  }

  Future<void> _recount() async {
    cacheBytes.value = await measureCache();
  }

  /// Evicts least-recently-used stream files until the cache is under budget,
  /// and drops anything untouched for three weeks.
  Future<void> _prune() async {
    final dir = _cacheDir;
    if (dir == null) return;
    try {
      final files = <FileSystemEntity>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) files.add(entity);
      }

      final now = DateTime.now();
      final survivors = <({File file, DateTime accessed, int size})>[];

      for (final entity in files) {
        final file = entity as File;
        try {
          final stat = await file.stat();
          // A live transfer's `.part` is being written right now: never sweep
          // it, and rank it as the freshest thing in the cache.
          final live = _isLivePart(file.path);
          if (!live && now.difference(stat.accessed) > _staleAfter) {
            await _safeDelete(file);
            continue;
          }
          survivors.add((
            file: file,
            accessed: live ? now : stat.accessed,
            size: stat.size,
          ));
        } catch (_) {
          // A file we cannot stat is not worth keeping.
        }
      }

      var total = survivors.fold<int>(0, (sum, e) => sum + e.size);
      if (total <= maxCacheBytes) {
        cacheBytes.value = total;
        return;
      }

      // Oldest first.
      survivors.sort((a, b) => a.accessed.compareTo(b.accessed));
      for (final entry in survivors) {
        if (total <= maxCacheBytes) break;
        await _safeDelete(entry.file);
        total -= entry.size;
      }
      cacheBytes.value = total < 0 ? 0 : total;
    } catch (e) {
      debugPrint('MediaCache prune failed: $e');
    }
  }

  /// `CLEAR STREAM CACHE` — never touches offline downloads.
  Future<int> clearStreamCache() async {
    for (final token in _inFlight.values) {
      if (!token.isCancelled) token.cancel('cache cleared');
    }
    _inFlight.clear();
    _urlToPath.clear();

    final dir = _cacheDir;
    if (dir == null) return 0;
    var freed = 0;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          // A live transfer is writing into this directory: leave its file
          // alone, or the song that is playing right now would die with it.
          if (_isLivePart(entity.path)) continue;
          freed += await entity.length();
          await _safeDelete(entity);
        }
      }
    } catch (e) {
      debugPrint('MediaCache clear failed: $e');
    }
    cacheBytes.value = 0;
    return freed;
  }

  /// Total size of the offline vault.
  Future<int> measureDownloads() async {
    final dir = _downloadsDir;
    if (dir == null) return 0;
    var total = 0;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
    } catch (e) {
      debugPrint('MediaCache download measure failed: $e');
    }
    return total;
  }

  Future<void> deleteDownload(String fileName) async {
    final path = downloadedPathFor(fileName);
    if (path == null) return;
    await _safeDelete(File(path));
    _urlToPath.removeWhere((_, value) => value == path);
  }

  Future<int> deleteAllDownloads() async {
    final dir = _downloadsDir;
    if (dir == null) return 0;
    var freed = 0;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          freed += await entity.length();
          await _safeDelete(entity);
        }
      }
    } catch (e) {
      debugPrint('MediaCache download purge failed: $e');
    }
    return freed;
  }

  /// Deterministic on-disk name for an offline download.
  static String downloadFileName({required String songId, required int kbps}) {
    final safe = songId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return 'musify_${safe}_$kbps.m4a';
  }

  Future<void> _touch(File file) async {
    try {
      await file.setLastAccessed(DateTime.now());
    } catch (_) {
      // Not supported on every platform/filesystem; harmless.
    }
  }

  Future<void> _safeDelete(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) await entity.delete();
    } catch (_) {
      // Best effort.
    }
  }
}

/// Which byte ranges of a file have landed.
///
/// A read-while-writing transfer has one writer but more than one *order*: a
/// seek moves the connection forward, which leaves a hole behind it, and what
/// arrives later can only fill that hole by going back. So "how much have we
/// downloaded" is a different question from "which byte ranges can be read",
/// and this class answers the second one — it merges arriving ranges, reports
/// the first hole (what the pump connects to next), and decides when the file
/// is whole enough to be renamed into the cache.
class ByteCoverage {
  final List<(int, int)> _ranges = [];

  /// The downloaded ranges: sorted, disjoint, merged.
  List<(int, int)> get ranges => List.unmodifiable(_ranges);

  /// Bytes on disk. A hole contributes nothing.
  int get bytes {
    var sum = 0;
    for (final range in _ranges) {
      sum += range.$2 - range.$1;
    }
    return sum;
  }

  /// True when every byte of `[start, end)` is on disk.
  bool covers(int start, int end) {
    if (end <= start) return true;
    for (final range in _ranges) {
      if (range.$1 <= start && end <= range.$2) return true;
      if (range.$1 > start) return false;
    }
    return false;
  }

  /// The merged range containing [offset], or `null` when it is a hole.
  (int, int)? runAt(int offset) {
    for (final range in _ranges) {
      if (range.$1 <= offset && offset < range.$2) return range;
      if (range.$1 > offset) return null;
    }
    return null;
  }

  /// The first byte not on disk yet, or `null` when the file is whole.
  int? firstGap(int total) {
    var at = 0;
    for (final range in _ranges) {
      if (range.$1 > at) return at;
      if (range.$2 > at) at = range.$2;
    }
    return at >= total ? null : at;
  }

  /// True when `[0, total)` is covered by a single run.
  bool isComplete(int total) {
    if (_ranges.isEmpty) return false;
    final first = _ranges.first;
    return first.$1 <= 0 && first.$2 >= total;
  }

  /// Records `[start, end)` as on disk, merging it with its neighbours.
  void add(int start, int end) {
    if (end <= start) return;

    // Insert in order, then one sweep merges everything that now touches —
    // including the case that matters most: a range that bridges two existing
    // runs (seek forward, then fill the hole that was left behind).
    var at = 0;
    while (at < _ranges.length && _ranges[at].$1 < start) {
      at++;
    }
    _ranges.insert(at, (start, end));

    if (_ranges.length < 2) return;
    final merged = <(int, int)>[_ranges.first];
    for (var i = 1; i < _ranges.length; i++) {
      final last = merged.last;
      final next = _ranges[i];
      if (next.$1 <= last.$2) {
        // Overlapping or adjacent: widen the run in place.
        if (next.$2 > last.$2) {
          merged[merged.length - 1] = (last.$1, next.$2);
        }
      } else {
        merged.add(next);
      }
    }
    _ranges
      ..clear()
      ..addAll(merged);
  }
}

/// A track resolved to a readable byte source, plus where it came from.
///
/// The [url] is empty when the bytes were already on disk (a download or a
/// completed cache entry), which is how the playback service knows a start
/// needed no network at all.
class StreamSource {
  const StreamSource({
    required this.session,
    required this.url,
    required this.bitrate,
  });

  final StreamSession session;
  final String url;
  final int bitrate;
}

/// A byte source for the progressive AAC decoder.
///
/// Backed either by a file that is already whole (a cache hit, an offline
/// download) or by a live transfer that is still arriving. [read] waits for the
/// range it is asked for and never for the whole file, which is what turns
/// "tap a song" into "audio in a few hundred milliseconds".
class StreamSession {
  StreamSession._staged(File file, int length)
      : _file = file,
        _fileLength = length,
        _transfer = null;

  StreamSession._live(_LiveTransfer transfer)
      : _file = null,
        _fileLength = null,
        _transfer = transfer;

  final File? _file;
  final int? _fileLength;
  final _LiveTransfer? _transfer;

  RandomAccessFile? _raf;
  bool _closed = false;

  /// Opens a session over a local file — an offline download, a cache entry, a
  /// file the user copied in. Returns `null` when it is missing or empty.
  static StreamSession? overFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final length = file.lengthSync();
      if (length <= 0) return null;
      return StreamSession._staged(file, length);
    } catch (_) {
      return null;
    }
  }

  /// Total bytes in the file, or `null` when the server never said.
  int? get total => _transfer?.total ?? _fileLength;

  /// The file is fully written (a staged file always is).
  bool get isComplete => _transfer?.complete ?? true;

  /// The transfer is still running behind this session.
  bool get isLive => _transfer != null && !_transfer.complete;

  /// Bytes that can be read right now.
  int get bytesAvailable => _transfer?.coveredBytes ?? (_fileLength ?? 0);

  /// Why a live transfer stopped, when it stopped badly.
  String? get error => _transfer?.error;

  /// Proactively repositions the underlying transfer to [offset] on seek.
  void jumpTo(int offset) {
    _transfer?.jumpTo(offset);
  }

  /// The whole file this session reads from, or `null` while it is still
  /// arriving (a half-written `.part` is not a path the engine can be given).
  String? get path {
    final file = _file;
    if (file != null) return file.path;
    final transfer = _transfer;
    if (transfer != null && transfer.complete) return transfer.target.path;
    return null;
  }

  /// Reads bytes `[start, end)`, waiting for a live transfer to cover them.
  ///
  /// Returns `null` when the bytes cannot be produced — a dead connection, a
  /// short read, a closed session — which the caller treats as a failed feed
  /// rather than an error to throw at the engine.
  Future<Uint8List?> read(int start, int end) async {
    if (_closed || end <= start || start < 0) return null;
    final transfer = _transfer;
    if (transfer != null) return transfer.readRange(start, end);
    return _readFile(start, end);
  }

  Future<Uint8List?> _readFile(int start, int end) async {
    final file = _file;
    if (file == null) return null;
    try {
      final raf = _raf ??= await file.open();
      await raf.setPosition(start);
      final bytes = await raf.read(end - start);
      return bytes.length == end - start ? bytes : null;
    } catch (e) {
      debugPrint('StreamSession read failed on $file: $e');
      return null;
    }
  }

  /// Detaches the player.
  ///
  /// A live transfer keeps running in the background so the whole file still
  /// lands in the cache; the next play is then a plain disk read.
  void release() {
    if (_closed) return;
    _closed = true;
    final raf = _raf;
    _raf = null;
    if (raf != null) {
      unawaited(() async {
        try {
          await raf.close();
        } catch (_) {
          // A handle we no longer need: nothing to report.
        }
      }());
    }
    _transfer?.release();
  }
}

/// One sequential connection whose cursor follows the read head.
///
/// The transfer writes into `<target>.part` at real file offsets, so a URL that
/// is played to the end (the common case) leaves a byte-for-byte complete file
/// behind — exactly what [MediaCache.ensure] would have produced, minus the
/// wait. A seek that jumps far ahead closes the connection and reopens it at
/// the new offset; the skipped region is remembered as a hole and filled later,
/// in the background, so the cache entry still completes.
class _LiveTransfer {
  _LiveTransfer({
    required this.cache,
    required this.url,
    required this.target,
    required this.partial,
    required this.total,
    this.onProgress,
  });

  final MediaCache cache;
  final String url;
  final File target;
  final File partial;
  final int total;
  final ValueChanged<TransferProgress>? onProgress;

  /// Which byte ranges are on disk. *Coverage* — not bytes received — decides
  /// whether a read can be served and when the file is whole.
  final ByteCoverage _coverage = ByteCoverage();

  RandomAccessFile? _write;
  RandomAccessFile? _read;
  CancelToken? _token;
  int _readers = 0;
  int _cursor = 0;
  int? _restartAt;
  int _reported = 0;
  int _retries = 0;
  bool _stopped = false;
  bool _finalized = false;
  String? _error;

  /// A read more than this far ahead of the connection restarts it there:
  /// reconnecting beats waiting for sequential bytes to download.
  static const int _jumpBytes = 64 * 1024;

  /// How long [readRange] waits before giving up on a range.
  static const Duration _readTimeout = Duration(seconds: 25);

  bool get failed => _error != null;
  bool get stopped => _stopped;
  bool get complete => _coverage.isComplete(total);
  String? get error => _error;

  int get coveredBytes => _coverage.bytes;

  double? get fraction =>
      total > 0 ? (coveredBytes / total).clamp(0.0, 1.0) : null;

  void attach() => _readers++;

  void release() {
    if (_readers > 0) _readers--;
    if (_readers > 0 || _stopped) return;
    if (complete) {
      unawaited(_closeReadHandle());
      return;
    }
    // Nobody is listening, but the file is still worth caching: finish it in
    // the background, within a bounded number of sockets.
    cache._registerFinisher(this);
  }

  /// Proactively reposition the connection to [offset] on seek so reads are instant.
  void jumpTo(int offset) {
    if (complete || _stopped || failed) return;
    if (_covers(offset, offset + 1)) return;
    _restartAt = offset;
    final token = _token;
    if (token != null && !token.isCancelled) {
      token.cancel('reposition');
    }
  }

  // ---------------------------------------------------------------- reading

  /// Waits for `[start, end)` to be on disk, then reads it.
  Future<Uint8List?> readRange(int start, int end) async {
    var from = start;
    var to = end;
    if (from < 0) from = 0;
    if (to > total) to = total;
    if (to <= from) return Uint8List(0);

    final deadline = DateTime.now().add(_readTimeout);
    while (!_covers(from, to)) {
      if (_stopped || failed) return null;
      if (!DateTime.now().isBefore(deadline)) return null;
      _maybeJump(from);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return _readFromDisk(from, to);
  }

  Future<Uint8List?> _readFromDisk(int start, int end) async {
    // After finalization the bytes live under `target`, but an open handle
    // keeps working across the rename, so try the live handle first.
    final candidates = <File>[partial, if (_finalized) target];
    for (final file in candidates) {
      try {
        final raf = file == partial
            ? (_read ??= await file.open())
            : await file.open();
        await raf.setPosition(start);
        final bytes = await raf.read(end - start);
        if (bytes.length == end - start) return bytes;
      } catch (e) {
        debugPrint('MediaCache read at $start failed: $e');
      }
    }
    return null;
  }

  bool _covers(int start, int end) => _coverage.covers(start, end);

  /// Moves the connection when the read head outruns it by more than
  /// [_jumpBytes], instead of making the listener wait for bytes in between.
  void _maybeJump(int start) {
    if (complete || _stopped || failed) return;
    if (_covers(start, start + 1)) return;
    if (_cursor <= start && start <= _cursor + _jumpBytes) return;
    if (_restartAt != null && _restartAt! <= start && start <= _restartAt! + _jumpBytes) return;
    _restartAt = start;
    final token = _token;
    if (token != null && !token.isCancelled) token.cancel('reposition');
  }

  // --------------------------------------------------------------- transfer

  Future<void> run() async {
    while (!_stopped && !complete) {
      var from = _restartAt;
      _restartAt = null;
      if (from == null) {
        final gap = _coverage.firstGap(total);
        if (gap == null) break;
        from = gap;
      }
      if (from >= total) break;
      if (!await _pumpFrom(from)) break;
    }
    if (complete && !_stopped) {
      unawaited(_finalize());
    } else if (_stopped) {
      cache._unregister(this);
    }
  }

  /// One connection, from [from] onwards, until the read head moves.
  /// Returns `false` when the transfer is dead.
  Future<bool> _pumpFrom(int from) async {
    final token = CancelToken();
    _token = token;
    try {
      final response = await cache._dio.get<ResponseBody>(
        url,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          headers: {'Accept': '*/*', if (from > 0) 'Range': 'bytes=$from-'},
        ),
      );
      final body = response.data;
      if (body == null) return _fail('empty response');

      // A server that ignores `Range` answers 200 with the whole file: write it
      // from zero rather than at the offset we asked for.
      var offset = (from == 0 || response.statusCode == 206) ? from : 0;
      final write = _write ??= await partial.open(mode: FileMode.write);
      _cursor = offset;

      await for (final chunk in body.stream) {
        if (_stopped || token.isCancelled) break;
        if (chunk.isEmpty) continue;
        final start = offset;
        offset += chunk.length;
        final already = _covers(start, offset);
        await write.setPosition(start);
        await write.writeFrom(chunk);
        _cursor = offset;
        _coverage.add(start, offset);
        _report();
        if (complete) break;
        if (already) {
          // The pump caught up with bytes it already owns (a seek left a hole
          // behind it): jump to the next hole instead of re-buying the run.
          final run = _coverage.runAt(offset - 1);
          if (run != null && run.$2 > offset) {
            token.cancel('skip');
            break;
          }
        }
      }

      if (_stopped) return false;
      if (complete) return true;
      if (token.isCancelled) return true; // repositioned: the caller decides
      if (offset >= total) return true; // tail received; holes remain at most
      if (offset == from) return _fail('connection stalled at $from');
      _retries = 0;
      return true;
    } on DioException catch (e) {
      if (_stopped) return false;
      if (e.type == DioExceptionType.cancel) return true;
      _retries++;
      if (_retries > 3) return _fail('network error (${e.type.name})');
      await Future<void>.delayed(Duration(milliseconds: 200 * _retries));
      return true;
    } catch (e) {
      return _fail('$e');
    }
  }

  void _report({bool force = false}) {
    final covered = coveredBytes;
    if (!force && covered < total && covered - _reported < (1 << 18)) return;
    _reported = covered;
    onProgress?.call(
      TransferProgress(received: covered, total: total, fraction: fraction),
    );
  }

  /// Waits for the whole file — used when something else needs this URL's bytes
  /// on disk (a download was requested for the track that is already playing).
  Future<String?> awaitComplete({
    ValueChanged<TransferProgress>? onProgress,
  }) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (!complete && !failed && !_stopped) {
      onProgress?.call(
        TransferProgress(
          received: coveredBytes,
          total: total,
          fraction: fraction,
        ),
      );
      if (!DateTime.now().isBefore(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!complete) return null;
    while (!_finalized && !failed && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return target.existsSync() ? target.path : null;
  }

  /// Stops the transfer and removes its partial file.
  Future<void> abandon() async {
    _stopped = true;
    final token = _token;
    if (token != null && !token.isCancelled) token.cancel('abandoned');
    await _closeHandles();
    cache._unregister(this);
    if (!complete) await cache._safeDelete(partial);
  }

  bool _fail(String reason) {
    if (_error == null) {
      _error = reason;
      debugPrint('MediaCache stream failed for $url: $reason');
    }
    _stopped = true;
    cache._unregister(this);
    unawaited(_closeHandles());
    return false;
  }

  Future<void> _finalize() async {
    if (_finalized) return;
    _finalized = true;

    final write = _write;
    _write = null;
    try {
      await write?.close();
    } catch (_) {
      // Done with it either way.
    }

    // Whatever the headers claimed, the container's magic bytes have the final
    // word — an error page must never masquerade as a cache entry.
    if (!await cache._fileLooksLikeAudio(partial)) {
      _error = 'not audio';
      _stopped = true;
      await cache._safeDelete(partial);
      cache._unregister(this);
      return;
    }

    _report(force: true);
    try {
      final staged = await partial.rename(target.path);
      cache._urlToPath[url] = staged.path;
      await cache._recount();
      unawaited(cache._prune());
    } catch (e) {
      debugPrint('MediaCache could not finalize $url: $e');
    }
    cache._unregister(this);
  }

  Future<void> _closeReadHandle() async {
    final read = _read;
    _read = null;
    try {
      await read?.close();
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> _closeHandles() async {
    final write = _write;
    _write = null;
    try {
      await write?.close();
    } catch (_) {
      // Best effort.
    }
    await _closeReadHandle();
  }
}

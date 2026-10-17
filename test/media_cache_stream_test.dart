// Guards for the streaming cache — the parts that make replay instant.
//
// The interesting behaviour of `MediaCache` while streaming is *which bytes*
// it will hand out and when, and that depends entirely on what is already on
// disk. These tests drive the file-system side of it (a complete entry, an
// offline download, a missing file) with a temporary directory, so nothing here
// needs a network, a device or an audio engine.

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/media_cache.dart';

/// A short payload that passes the magic-byte gate (`ftyp` at offset 4).
Uint8List _audioBytes([int length = 64]) {
  final bytes = Uint8List(length);
  bytes.setRange(0, 8, [0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70]); // ftyp
  bytes.setRange(8, 12, 'M4A '.codeUnits);
  for (var i = 12; i < length; i++) {
    bytes[i] = i & 0xFF;
  }
  return bytes;
}

void main() {
  late Directory root;
  late Directory cacheDir;
  late Directory downloadsDir;
  late MediaCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('musify_cache_test');
    cacheDir = Directory('${root.path}${Platform.pathSeparator}cache');
    downloadsDir = Directory('${root.path}${Platform.pathSeparator}downloads');
    cache = MediaCache(Dio());
    await cache.useDirectories(cache: cacheDir, downloads: downloadsDir);
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {
      // A leaked temp folder is not worth failing a test over.
    }
  });

  Future<File> writeCacheFile(String name, {int length = 64}) async {
    final file = File('${cacheDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(_audioBytes(length));
    return file;
  }

  group('staged sessions', () {
    test('a complete cache entry is served without touching the network',
        () async {
      final file = await writeCacheFile('musify_abc_320.m4a', length: 128);

      final progress = <double?>[];
      final session = await cache.openStream(
        url: 'https://cdn.example/abc_320.mp4',
        fileName: 'musify_abc_320.m4a',
        onProgress: (value) => progress.add(value.fraction),
      );

      expect(session, isNotNull, reason: 'the file is right there');
      expect(session!.isComplete, isTrue);
      expect(session.isLive, isFalse);
      expect(session.total, 128);
      expect(session.bytesAvailable, 128);
      expect(session.path, file.path);
      expect(progress, [1.0], reason: 'a cache hit is 100% done');

      final head = await session.read(0, 16);
      expect(head, hasLength(16));
      expect(head!.sublist(4, 8), 'ftyp'.codeUnits,
          reason: 'the caller must get the real file bytes');

      session.release();
      // The playback path must not delete what it just read.
      expect(file.existsSync(), isTrue);
      expect(cache.streamPathFor('musify_abc_320.m4a'), file.path);
    });

    test('reads are exact at any offset', () async {
      final file = await writeCacheFile('musify_offset_160.m4a', length: 300);
      final session = (await cache.openStream(
        url: 'https://cdn.example/offset_160.mp4',
        fileName: 'musify_offset_160.m4a',
      ))!;

      final middle = await session.read(100, 140);
      expect(middle, hasLength(40));
      expect(middle, (await file.readAsBytes()).sublist(100, 140));

      expect(await session.read(290, 400), isNull,
          reason: 'a range past the end must fail, not wrap');
      expect(await session.read(10, 10), isNull,
          reason: 'an empty request is not a read');
      session.release();
    });

    test('overFile refuses a missing or empty file', () async {
      expect(StreamSession.overFile('${root.path}/nope.m4a'), isNull);
      final empty = File('${root.path}${Platform.pathSeparator}empty.m4a');
      await empty.writeAsBytes(const []);
      expect(StreamSession.overFile(empty.path), isNull,
          reason: 'a zero-byte file has no sample table to index');

      final good = await writeCacheFile('musify_good_96.m4a');
      final session = StreamSession.overFile(good.path);
      expect(session, isNotNull);
      expect(session!.total, 64);
      expect(session.read(0, 8), completion(isNotEmpty));
      session.release();
      expect(session.read(0, 8), completion(isNull),
          reason: 'a released session must not keep answering');
    });
  });

  group('ensure', () {
    test('short-circuits for a file that is already staged', () async {
      final file = await writeCacheFile('musify_cached_320.m4a');
      final progress = <double?>[];

      final path = await cache.ensure(
        url: 'https://cdn.example/cached_320.mp4',
        fileName: 'musify_cached_320.m4a',
        onProgress: (value) => progress.add(value.fraction),
      );

      expect(path, file.path);
      expect(progress, [1.0]);
    });

    test('an unreachable URL yields null instead of throwing', () async {
      // Port 1 is not listening, so the connection is refused immediately.
      final session = await cache.openStream(
        url: 'http://127.0.0.1:1/nope.mp4',
        fileName: 'musify_nope_320.m4a',
      );
      expect(session, isNull, reason: 'the caller then falls back to ensure()');
      expect(cache.activeStreams, 0);
    });
  });

  group('ByteCoverage arithmetic used by the download pump', () {
    test('a forward seek leaves a hole that later fills in', () {
      final coverage = ByteCoverage()..add(0, 10);
      // The read head jumps ahead: the pump restarts there and the bytes in
      // between are only fetched afterwards.
      coverage.add(40, 50);
      expect(coverage.firstGap(60), 10);
      expect(coverage.covers(40, 50), isTrue);

      coverage.add(10, 40);
      expect(coverage.ranges, [(0, 50)]);
      coverage.add(50, 60);
      expect(coverage.isComplete(60), isTrue);
      expect(coverage.firstGap(60), isNull);
    });
  });
}

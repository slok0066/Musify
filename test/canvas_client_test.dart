import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/data/datasources/canvas_client.dart';
import 'package:musify/data/models/track.dart';

void main() {
  HttpOverrides.global = null;

  group('CanvasClient', () {
    test('cleans track titles and keeps Apple Music unchanged', () async {
      final dio = Dio();
      final client = CanvasClient(dio);
      addTearDown(client.close);

      const track = Track(
        id: 'test_123',
        title: 'Starboy (Official Music Video) [feat. Daft Punk]',
        artist: 'The Weeknd',
      );

      final url = await client.fetch(track);
      expect(url, isNotNull);
      expect(url!.contains('itunes.apple.com'), isTrue);
    });

    test('downloads 10-15s HD YouTube fMP4 clip and remuxes to local MP4', () async {
      final tempDir = await Directory.systemTemp.createTemp('musify_canvas_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      var remuxCalls = 0;
      late Uint8List capturedRawBytes;
      late String capturedRawPath;

      final client = CanvasClient(
        Dio(),
        null,
        (inputPath, outputPath, maxDurationMs) async {
          remuxCalls++;
          capturedRawPath = inputPath;
          capturedRawBytes = await File(inputPath).readAsBytes();
          expect(maxDurationMs, inInclusiveRange(10000, 16000));
          // Simulate native MediaMuxer producing the final local .mp4 file.
          await File(outputPath).writeAsBytes(capturedRawBytes, flush: true);
          return true;
        },
        () async => tempDir,
      );
      addTearDown(client.close);

      const track = Track(
        id: 'saavn_casa',
        title: 'Casa Tupka Anthemo',
        artist: 'Yo Yo Honey Singh',
      );

      final path = await client.fetch(track);
      expect(path, isNotNull);
      expect(remuxCalls, 1);
      expect(path!.endsWith('.mp4'), isTrue);
      expect(File(path).existsSync(), isTrue);
      // Intermediate raw .fmp4 must be deleted after remux.
      expect(File(capturedRawPath).existsSync(), isFalse);

      // Verify raw DASH clip handed to Android MediaExtractor: 64 KB..10 MB,
      // ftyp -> moov -> moof structure.
      expect(capturedRawBytes.length, greaterThan(64 * 1024));
      expect(capturedRawBytes.length, lessThan(10 * 1024 * 1024));

      int u32(int o) =>
          (capturedRawBytes[o] << 24) |
          (capturedRawBytes[o + 1] << 16) |
          (capturedRawBytes[o + 2] << 8) |
          capturedRawBytes[o + 3];
      String fourcc(int o) =>
          String.fromCharCodes(capturedRawBytes.sublist(o, o + 4));

      final ftypSize = u32(0);
      expect(fourcc(4), 'ftyp');
      final moovSize = u32(ftypSize);
      expect(fourcc(ftypSize + 4), 'moov');
      final afterMoov = ftypSize + moovSize;
      expect(fourcc(afterMoov + 4), 'moof');

      // Second fetch must hit cache without re-downloading or re-remuxing.
      final cachedPath = await client.fetch(track);
      expect(cachedPath, path);
      expect(remuxCalls, 1);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

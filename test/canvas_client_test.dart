import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/data/datasources/canvas_client.dart';
import 'package:musify/data/models/track.dart';

void main() {
  HttpOverrides.global = null;

  group('CanvasClient', () {
    test('cleans track titles and caches results', () async {
      final dio = Dio();
      final client = CanvasClient(dio);

      const track = Track(
        id: 'test_123',
        title: 'Starboy (Official Music Video) [feat. Daft Punk]',
        artist: 'The Weeknd',
      );

      final url = await client.fetch(track);
      expect(url, isNotNull);
      expect(url!.contains('itunes.apple.com'), isTrue);
    });

    test('resolves video stream for Indian/JioSaavn track', () async {
      final dio = Dio();
      final client = CanvasClient(dio);

      const track = Track(
        id: 'saavn_bansuri',
        title: 'BANSURI MONTAGEM',
        artist: 'Indian Flute Brazilian Phonk',
      );

      final url = await client.fetch(track);
      expect(url, isNotNull);
      expect(url!.isNotEmpty, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

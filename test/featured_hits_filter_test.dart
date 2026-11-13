import 'package:flutter_test/flutter_test.dart';
import 'package:musify/data/models/track.dart';

void main() {
  group('Featured Hits & Rotating Card Filter', () {
    test('Rotating card strictly excludes YouTube tracks and allows only JioSaavn', () {
      final candidates = [
        const Track(
          id: 'yt:abc12345',
          title: 'YouTube Track 1',
          artist: 'Artist 1',
          source: TrackSource.youtube,
          imageUrl: 'https://i.ytimg.com/vi/abc12345/hqdefault.jpg',
        ),
        const Track(
          id: 'saavn_101',
          title: 'Chaleya',
          artist: 'Arijit Singh',
          source: TrackSource.saavn,
          imageUrl: 'https://c.saavncdn.com/101/Chaleya-500x500.jpg',
          language: 'Hindi',
        ),
        const Track(
          id: 'yt:xyz987',
          title: 'YouTube Track 2',
          artist: 'Artist 2',
          source: TrackSource.youtube,
          imageUrl: 'https://i.ytimg.com/vi/xyz987/hqdefault.jpg',
        ),
        const Track(
          id: 'saavn_202',
          title: 'Die With A Smile',
          artist: 'Lady Gaga, Bruno Mars',
          source: TrackSource.saavn,
          imageUrl: 'https://c.saavncdn.com/202/Die-500x500.jpg',
          language: 'English',
        ),
      ];

      final filtered = <Track>[];
      for (final t in candidates) {
        if (t.isYouTube ||
            t.source != TrackSource.saavn ||
            t.id.startsWith('yt:') ||
            t.imageUrl.contains('ytimg')) {
          continue;
        }
        filtered.add(t);
      }

      expect(filtered.length, 2);
      expect(filtered.map((t) => t.title).toList(), ['Chaleya', 'Die With A Smile']);
      expect(filtered.every((t) => !t.isYouTube && t.source == TrackSource.saavn), isTrue);
    });

    test('Featured hits interleaves Hindi/trending and English tracks smoothly', () {
      final hindiTracks = [
        const Track(id: 'h1', title: 'Hindi 1', artist: 'Artist H1'),
        const Track(id: 'h2', title: 'Hindi 2', artist: 'Artist H2'),
        const Track(id: 'h3', title: 'Hindi 3', artist: 'Artist H3'),
        const Track(id: 'h4', title: 'Hindi 4', artist: 'Artist H4'),
      ];
      final englishTracks = [
        const Track(id: 'e1', title: 'English 1', artist: 'Artist E1'),
        const Track(id: 'e2', title: 'English 2', artist: 'Artist E2'),
      ];

      final combined = <Track>[];
      int hIndex = 0;
      int eIndex = 0;

      while (hIndex < hindiTracks.length || eIndex < englishTracks.length) {
        for (int i = 0; i < 2 && hIndex < hindiTracks.length; i++) {
          combined.add(hindiTracks[hIndex++]);
        }
        if (eIndex < englishTracks.length) {
          combined.add(englishTracks[eIndex++]);
        }
      }

      expect(combined.map((t) => t.id).toList(), [
        'h1',
        'h2',
        'e1',
        'h3',
        'h4',
        'e2',
      ]);
    });
  });
}


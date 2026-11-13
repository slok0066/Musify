import 'package:flutter_test/flutter_test.dart';
import 'package:musify/data/models/track.dart';

void main() {
  group('Track deduplication and mixing', () {
    test('isDuplicate detects duplicates across Saavn and YouTube metadata', () {
      const saavnTrack = Track(
        id: 'saavn_1',
        title: 'Kesariya (From "Brahmastra")',
        artist: 'Pritam, Arijit Singh, Amitabh Bhattacharya',
        duration: Duration(seconds: 268),
      );

      const ytTrack = Track(
        id: 'yt:abc1234',
        source: TrackSource.youtube,
        title: 'Kesariya - Official Video',
        artist: 'Arijit Singh',
        duration: Duration(seconds: 270),
      );

      const differentTrack = Track(
        id: 'yt:xyz5678',
        source: TrackSource.youtube,
        title: 'Apna Bana Le',
        artist: 'Arijit Singh',
        duration: Duration(seconds: 260),
      );

      expect(Track.isDuplicate(saavnTrack, ytTrack), isTrue);
      expect(Track.isDuplicate(saavnTrack, differentTrack), isFalse);
    });

    test('mixAndDedupe interleaves sources cleanly without duplicates', () {
      const s1 = Track(id: 's1', title: 'Kesariya', artist: 'Pritam, Arijit Singh');
      const s2 = Track(id: 's2', title: 'Apna Bana Le', artist: 'Sachin-Jigar, Arijit');
      const s3 = Track(id: 's3', title: 'O Bedardeya', artist: 'Pritam, Arijit Singh');

      const y1 = Track(id: 'yt:v1', source: TrackSource.youtube, title: 'Kesariya (Official Video)', artist: 'Arijit Singh');
      const y2 = Track(id: 'yt:v2', source: TrackSource.youtube, title: 'Heeriye', artist: 'Jasleen Royal, Arijit Singh');
      const y3 = Track(id: 'yt:v3', source: TrackSource.youtube, title: 'Channa Mereya (Live)', artist: 'Arijit Singh');

      final mixed = Track.mixAndDedupe([s1, s2, s3], [y1, y2, y3]);

      // s1 is kept, y1 (duplicate of s1) is skipped!
      // Next is y2 (Heeriye), then s2 (Apna Bana Le), then y3 (Channa Mereya), then s3 (O Bedardeya)
      expect(mixed.length, 5);
      expect(mixed.map((t) => t.id).toList(), ['s1', 'yt:v2', 's2', 'yt:v3', 's3']);
    });

    test('dedupeKey unifies feat, ft, and secondary artist variations', () {
      const t1 = Track(id: '1', title: 'Starboy', artist: 'The Weeknd');
      const t2 = Track(id: '2', title: 'Starboy (feat. Daft Punk)', artist: 'The Weeknd, Daft Punk');
      const t3 = Track(id: '3', title: 'Starboy - Official Music Video', artist: 'The Weeknd VEVO');

      expect(t1.dedupeKey, t2.dedupeKey);
      expect(t1.dedupeKey, t3.dedupeKey);
      expect(Track.isDuplicate(t1, t2), isTrue);
      expect(Track.isDuplicate(t1, t3), isTrue);

      final deduped = Track.dedupe([t1, t2, t3]);
      expect(deduped.length, 1);
      expect(deduped.first.id, '1');
    });
  });
}

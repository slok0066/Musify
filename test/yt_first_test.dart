import 'package:flutter_test/flutter_test.dart';
import 'package:musify/data/models/track.dart';
import 'package:musify/services/settings_service.dart';
import 'package:musify/services/yt_first/youtube_service.dart';
import 'package:musify/services/yt_first/yt_first_search.dart';

void main() {
  group('Track YouTube extensions', () {
    test('Track with source: youtube survives toMap/fromMap', () {
      const track = Track(
        id: 'yt:dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        source: TrackSource.youtube,
      );

      expect(track.isYouTube, isTrue);
      expect(track.videoId, 'dQw4w9WgXcQ');
      expect(track.sourceTag, 'YT');

      final map = track.toMap();
      expect(map['source'], 'youtube');

      final roundTrip = Track.fromMap(map);
      expect(roundTrip, isNotNull);
      expect(roundTrip!.source, TrackSource.youtube);
      expect(roundTrip.isYouTube, isTrue);
      expect(roundTrip.videoId, 'dQw4w9WgXcQ');
      expect(roundTrip.sourceTag, 'YT');
    });

    test('Old maps without source default to saavn', () {
      final oldMap = {
        'id': 'abc1234',
        'title': 'Test Song',
        'artist': 'Test Artist',
      };
      final track = Track.fromMap(oldMap);
      expect(track, isNotNull);
      expect(track!.source, TrackSource.saavn);
      expect(track.isYouTube, isFalse);
      expect(track.videoId, isNull);
      expect(track.sourceTag, 'Saavn');
    });
  });

  group('YtTitles parsing', () {
    test('cleans official video noise and separates artist', () {
      final parsed = YtTitles.parse(
        'Kesariya - Arijit Singh (Official Video)',
        'T-Series',
      );
      expect(parsed.title, 'Kesariya');
      expect(parsed.artist, 'Arijit Singh');
    });

    test('avoids treating "Official Video" as artist in Song - Official Video', () {
      final parsed = YtTitles.parse(
        'Believer - Official Music Video',
        'ImagineDragons',
      );
      expect(parsed.title, 'Believer');
      expect(parsed.artist, 'ImagineDragons');
    });
  });

  group('Audio ranking', () {
    test('puts itag 140 first, then AAC/MP4, then WebM', () {
      const candidates = [
        YtAudioCandidate(
          itag: 251,
          container: YtContainer.webm,
          codec: 'opus',
          bitrateKbps: 160,
          url: 'http://example.com/251',
          userAgent: 'ua',
          source: 'test',
        ),
        YtAudioCandidate(
          itag: 140,
          container: YtContainer.mp4,
          codec: 'mp4a',
          bitrateKbps: 128,
          url: 'http://example.com/140',
          userAgent: 'ua',
          source: 'test',
        ),
        YtAudioCandidate(
          itag: 139,
          container: YtContainer.mp4,
          codec: 'mp4a',
          bitrateKbps: 48,
          url: 'http://example.com/139',
          userAgent: 'ua',
          source: 'test',
        ),
      ];

      final ranked = rankYtAudio(candidates);
      expect(ranked.first.itag, 140);
      expect(ranked[1].itag, 139);
      expect(ranked.last.itag, 251);
    });
  });

  group('Settings ytFirstEnabled', () {
    test('defaults to true and survives json round-trip', () {
      const settings = MusifySettings();
      expect(settings.ytFirstEnabled, isTrue);

      final json = settings.toJson();
      final loaded = MusifySettings.fromJson(json);
      expect(loaded.ytFirstEnabled, isTrue);

      final toggled = settings.copyWith(ytFirstEnabled: false);
      expect(toggled.ytFirstEnabled, isFalse);
      final toggledJson = toggled.toJson();
      final loadedToggled = MusifySettings.fromJson(toggledJson);
      expect(loadedToggled.ytFirstEnabled, isFalse);
    });
  });

  group('YoutubeService candidate resolution', () {
    test('resolveAudioCandidate yields Invidious first', () async {
      final service = YoutubeService();
      const track = Track(
        id: 'yt:dQw4w9WgXcQ',
        title: 'Song',
        artist: 'Artist',
        source: TrackSource.youtube,
      );

      final candidate = await service.resolveAudioCandidate(track);
      expect(candidate, isNotNull);
      expect(candidate!.source, 'invidious');
      expect(candidate.itag, 140);
      expect(candidate.url, contains('dQw4w9WgXcQ'));
      expect(candidate.isAacMp4, isTrue);
    });
  });
}


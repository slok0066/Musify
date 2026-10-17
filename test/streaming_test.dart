// Guards for the three fixes that came out of the first device session:
//
// * playback start — the transfer that fills the stream cache, its range
//   splitting and its "this payload is an error page" gate;
// * the rendition ladder — a `has320: false` track must not waste a rung;
// * storage — a box that failed to open must never make a write disappear,
//   which is what a "like" that does nothing really is.
//
// Everything here is pure: no network, no Hive, no audio device.

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/data/models/track.dart';
import 'package:musify/data/repositories/music_repository.dart';
import 'package:musify/data/sources/local_store.dart';
import 'package:musify/services/media_cache.dart';

/// The first 16 bytes of the containers JioSaavn actually serves.
List<int> _mp4Head() => [0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34];
List<int> _ascii(String value) => value.codeUnits;

void main() {
  group('payload sniffing', () {
    test('recognises the containers the catalogue serves', () {
      expect(MediaCache.looksLikeAudio(head: _mp4Head()), isTrue,
          reason: 'M4A/MP4: a box size followed by ftyp');
      expect(MediaCache.looksLikeAudio(head: _ascii('ID3\x04')), isTrue,
          reason: 'MP3 with an ID3 tag');
      expect(MediaCache.looksLikeAudio(head: const [0xFF, 0xFB, 0x90]), isTrue,
          reason: 'MP3 frame sync with no tag');
      expect(MediaCache.looksLikeAudio(head: _ascii('OggS')), isTrue);
      expect(MediaCache.looksLikeAudio(head: _ascii('fLaC')), isTrue);
      expect(MediaCache.looksLikeAudio(head: _ascii('RIFF')), isTrue);
    });

    test('an error page is never audio, whatever the headers claim', () {
      expect(
        MediaCache.looksLikeAudio(
          contentType: 'audio/mp4',
          head: _ascii('<html><body>Access Denied'),
        ),
        isFalse,
        reason: 'CDNs serve the error page with the media content type',
      );
      expect(
        MediaCache.looksLikeAudio(
          contentType: 'audio/mpeg',
          head: _ascii('{"error":"not found"}'),
        ),
        isFalse,
      );
      expect(MediaCache.looksLikeAudio(head: const []), isFalse);
    });

    test('a declared audio type is trusted when the magic is unreadable', () {
      expect(
        MediaCache.looksLikeAudio(
          contentType: 'audio/mp4',
          head: const [0x00, 0x01, 0x02, 0x03],
        ),
        isTrue,
      );
      expect(MediaCache.isErrorPage('text/html; charset=utf-8'), isTrue);
      expect(MediaCache.isErrorPage('application/json'), isTrue);
      expect(MediaCache.isErrorPage('application/xml'), isTrue);
      expect(MediaCache.isErrorPage('audio/mp4'), isFalse);
      expect(MediaCache.isErrorPage(null), isFalse);
    });
  });

  group('range splitting', () {
    test('covers the file contiguously and never overlaps', () {
      const total = 10 * 1024 * 1024;
      final ranges = MediaCache.chunkRanges(total);

      expect(ranges.length, MediaCache.laneCount);
      expect(ranges.first.$1, 0);
      expect(ranges.last.$2, total - 1);
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].$1, ranges[i - 1].$2 + 1,
            reason: 'one byte must not be fetched twice');
      }
    });

    test('a file too small to split is one range', () {
      expect(MediaCache.chunkRanges(64 * 1024).length, 1);
      expect(MediaCache.chunkRanges(0), isEmpty);
    });
  });

  group('rendition ladder', () {
    test('walks 320 → 160 → 96 for a track that has them', () {
      expect(
        MusicRepository.renditionLadder(target: 320, has320: true),
        [320, 160, 96],
      );
      expect(
        MusicRepository.renditionLadder(target: 160, has320: true),
        [320, 160, 96],
      );
    });

    test('skips the 320 rung the catalogue already ruled out', () {
      expect(
        MusicRepository.renditionLadder(target: 320, has320: false),
        [160, 96],
        reason: 'a failed 320 fetch is a wasted round trip per track',
      );
      expect(
        MusicRepository.renditionLadder(target: 96, has320: false),
        [160, 96],
        reason: 'the chosen quality is a floor, never a ceiling',
      );
    });
  });

  group('storage degradation', () {
    late LocalStore store;

    setUp(() => store = LocalStore());

    test('a store with no open boxes still round-trips every Library write',
        () async {
      final track = Track(id: 'trk1', title: 'Kesariya', artist: 'Arijit');

      await store.writeLiked([track]);
      await store.writeDownloads([track.copyWith(localPath: '/tmp/a.m4a')]);
      await store.pushHistory(track);
      await store.pushSearch('arijit');
      await store.pushRecentCollection({'id': 'c1', 'title': 'Chill'});

      expect(store.readLiked().single.id, 'trk1');
      expect(store.readLiked().single.title, 'Kesariya');
      expect(store.readDownloads().single.localPath, '/tmp/a.m4a');
      expect(store.readHistory().single.id, 'trk1');
      expect(store.readSearches(), ['arijit']);
      expect(store.readRecentCollections().single['id'], 'c1');
    });

    test('degraded storage says so instead of pretending it saved', () async {
      await store.writeLiked([Track(id: 'a', title: 'A', artist: 'X')]);

      expect(store.storageWarning, isTrue);
      expect(store.isReady, isFalse);
      expect(store.diagnostics(), contains('DEGRADED'));
      expect(store.diagnostics(), contains('liked=1'));
    });

    test('a like toggles off again in the same session', () async {
      final track = Track(id: 'a', title: 'A', artist: 'X');

      await store.writeLiked([track]);
      await store.writeLiked(<Track>[]);

      expect(store.readLiked(), isEmpty);
    });
  });
}

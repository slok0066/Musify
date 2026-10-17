// Law 7 — "Null-safe JSON parsing": one malformed row from JioSaavn must never
// poison a rail, the queue or the Hive boxes.
//
// These tests exist because the parse layer used to be reachable only through a
// live network call, so the PRD's seventh defensive law was covered by hand
// testing alone. They run offline against `JioSaavnClient`'s `@visibleForTesting`
// seams (see the "Law 7 test seams" block in
// `lib/data/datasources/jiosaavn_client.dart`).
//
// Payloads here are deliberately *hostile*: missing keys, nulls, numbers where
// strings are advertised, `'false'` strings, empty sentinels and HTML entities.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/data/datasources/jiosaavn_client.dart';
import 'package:musify/data/models/collection.dart';
import 'package:musify/data/models/track.dart';

void main() {
  late JioSaavnClient client;

  setUp(() => client = JioSaavnClient(Dio()));

  group('parseSong survives hostile payloads', () {
    test('a song with no id is dropped instead of being half-created', () {
      expect(client.parseSong(const {}), isNull);
      expect(client.parseSong(const {'id': ''}), isNull);
      expect(client.parseSong(const {'id': '   '}), isNull);
      // No id, but a title: still dropped — id is the queue key.
      expect(client.parseSong(const {'title': 'Ghost'}), isNull);
    });

    test('every optional field can be missing at once', () {
      final track = client.parseSong(const {'id': 'a'})!;

      expect(track.id, 'a');
      // `Fmt.cleanTitle` turns an empty/missing title into the sentinel rather
      // than an empty string, so the UI never renders a blank row.
      expect(track.title, 'Unknown');
      expect(track.artist, 'Unknown');
      expect(track.album, 'Unknown');
      expect(track.imageUrl, '');
      expect(track.duration, Duration.zero);
      expect(track.streamUrl, isNull);
      expect(track.has320, isTrue, reason: 'default assumes the 320 rendition');
      expect(track.artistId, isNull);
      expect(track.albumId, isNull);
      expect(track.year, isNull);
      expect(track.language, isNull);
      expect(track.hasLyrics, isFalse);
      expect(track.playCount, isNull);
      expect(track.hasPlayableSource, isFalse);
    });

    test('wrong types are coerced, never thrown', () {
      final track = client.parseSong(const {
        'id': 7,
        'title': 42,
        'more_info': 'this is not a map',
        'year': 'not a number',
      })!;

      expect(track.id, '7', reason: 'int id → string id');
      expect(track.title, '42');
      expect(track.year, isNull, reason: 'unparseable year is dropped, not 0');
      expect(track.duration, Duration.zero);
    });

    test('durations arrive as seconds in three different encodings', () {
      expect(
        client.parseSong(const {
          'id': 'x',
          'more_info': {'duration': 215},
        })!.duration,
        const Duration(seconds: 215),
      );
      expect(
        client.parseSong(const {
          'id': 'x',
          'more_info': {'duration': '216'},
        })!.duration,
        const Duration(seconds: 216),
        reason: 'JioSaavn sometimes sends the duration as a string',
      );
      expect(
        client.parseSong(const {
          'id': 'x',
          'more_info': {'duration': 217.9},
        })!.duration,
        const Duration(seconds: 217),
      );
      expect(
        client.parseSong(const {
          'id': 'x',
          'more_info': {'duration': 'unknown'},
        })!.duration,
        Duration.zero,
      );
    });

    test('the 320 kbps flag is read from bool, int and string forms', () {
      bool has320(Object? raw) => client.parseSong({
            'id': 'x',
            'more_info': {'320kbps': raw},
          })!.has320;

      expect(has320(true), isTrue);
      expect(has320('true'), isTrue);
      expect(has320('1'), isTrue);
      expect(has320(1), isTrue);
      expect(has320(false), isFalse);
      expect(has320('false'), isFalse);
      expect(has320('0'), isFalse);
      expect(has320(0), isFalse);
      expect(has320(null), isTrue,
          reason: 'absent flag falls back to "assume 320"');
      expect(has320('maybe'), isTrue,
          reason: 'garbage falls back, never throws');
    });

    test('HTML entities in titles are cleaned', () {
      expect(
        client.parseSong(const {'id': 'h', 'title': 'Rock &amp; Roll'})!.title,
        'Rock & Roll',
      );
      expect(
        client
            .parseSong(const {'id': 'h', 'title': 'Kesariya &#8217;22'})!.title,
        'Kesariya ’22',
      );
      expect(
        client.parseSong(const {'id': 'h', 'title': '  A   B  '})!.title,
        'A B',
        reason: 'whitespace is collapsed',
      );
    });

    test('artists come from the artist map, then the subtitle, then a sentinel',
        () {
      final mapped = client.parseSong(const {
        'id': 'art',
        'more_info': {
          'artistMap': {
            'primary_artists': [
              {'id': 9, 'name': 'Arijit Singh'},
              {'name': 'Shreya Ghoshal'},
            ],
            'featured_artists': [
              {'name': 'Badshah'},
            ],
          },
        },
      })!;

      expect(mapped.artist, 'Arijit Singh, Shreya Ghoshal');
      expect(mapped.artistsFull, 'Arijit Singh, Shreya Ghoshal, Badshah');
      expect(mapped.artistId, '9');

      // No map: the comma-joined subtitle line supplies the primary artist.
      final fromSubtitle = client.parseSong(const {
        'id': 'sub',
        'subtitle': 'Arijit Singh, Pritam',
      })!;
      expect(fromSubtitle.artist, 'Arijit Singh');
      expect(fromSubtitle.artistsFull, 'Arijit Singh, Pritam');

      // The artist map can be present but empty — one blank name must not
      // produce an empty artist string.
      final blank = client.parseSong(const {
        'id': 'blank',
        'more_info': {
          'artistMap': {
            'primary_artists': [
              {'name': '   '},
            ],
          },
        },
      })!;
      expect(blank.artist, isNotEmpty);
      expect(blank.artist, 'Unknown');
      expect(blank.artistId, isNull,
          reason: 'a nameless entry has no id either — never an empty string');
    });

    test('a missing id-like field in the artist map does not break the track',
        () {
      final track = client.parseSong(const {
        'id': 'noartid',
        'more_info': {
          'artistMap': {
            'primary_artists': [
              {'name': 'Solo'},
            ],
          },
        },
      })!;
      expect(track.artistId, isNull);
      expect(track.artist, 'Solo');
    });

    test(
        'images are upgraded from the thumbnail size, missing images are blank',
        () {
      expect(
        client.parseSong(const {
          'id': 'i',
          'image': 'https://c.saavncdn.com/123/x-150x150.jpg',
        })!.imageUrl,
        'https://c.saavncdn.com/123/x-500x500.jpg',
      );
      expect(client.parseSong(const {'id': 'i'})!.imageUrl, '');
    });

    test('the encrypted media url is remembered for the resolver', () {
      client.parseSong(const {
        'id': 'enc',
        'more_info': {
          'encrypted_media_url': '  QkJCQkJCQkJCQkJCQkJCQkJCQkJC  '
        },
      });
      expect(client.rememberedEncrypted('enc'), 'QkJCQkJCQkJCQkJCQkJCQkJCQkJC');

      // Absent / empty: nothing is cached, and the resolver will fetch it.
      client.parseSong(const {'id': 'plain'});
      expect(client.rememberedEncrypted('plain'), isNull);
      client.parseSong(const {
        'id': 'empty',
        'more_info': {'encrypted_media_url': '   '},
      });
      expect(client.rememberedEncrypted('empty'), isNull);
    });
  });

  group('parseRailItem keeps the rail union honest', () {
    test('a song becomes a playable rail entry', () {
      final item = client.parseRailItem(const {
        'type': 'song',
        'id': 's1',
        'title': 'Track',
      })!;
      expect(item.isTrack, isTrue);
      expect(item.isCollection, isFalse);
      expect(item.track!.id, 's1');
      expect(item.dedupeKey, startsWith('t:'));
    });

    test('each collection type maps to its own kind', () {
      CollectionKind kindOf(String type) => client
          .parseRailItem({'type': type, 'id': 'c1', 'title': 'T'})!
          .collection!
          .kind;

      expect(kindOf('album'), CollectionKind.album);
      expect(kindOf('ALBUM'), CollectionKind.album, reason: 'case-insensitive');
      expect(kindOf('playlist'), CollectionKind.playlist);
      expect(kindOf('artist'), CollectionKind.artist);
      expect(kindOf('channel'), CollectionKind.genre);
      // Unknown `type` — and a missing one — must not be dropped, they are
      // rendered with the fallback kind.
      expect(kindOf('mystery'), CollectionKind.playlist);
      expect(kindOf(''), CollectionKind.playlist);
    });

    test('id-less entries are dropped, never rendered as blanks', () {
      expect(client.parseRailItem(const {}), isNull);
      expect(client.parseRailItem(const {'type': 'song'}), isNull);
      expect(client.parseRailItem(const {'type': 'album', 'id': ''}), isNull);
      expect(client.parseRailItem(const {'type': 'album', 'title': 'No id'}),
          isNull);
    });
  });

  group('parseCollection survives hostile payloads', () {
    test('counts are read from every field JioSaavn uses, as string or int',
        () {
      // `song_count` lives inside `more_info`; `list_count` and `count` are
      // top-level — the parser is expected to accept all three.
      int? songCountInMore(Object? more) =>
          client.parseCollection({'id': 'c', 'more_info': more})!.songCount;

      expect(songCountInMore(const {'song_count': '12'}), 12);
      expect(songCountInMore(const {'song_count': 13}), 13);
      expect(songCountInMore(const {'song_count': 'many'}), isNull);
      expect(songCountInMore(const {'song_count': null}), isNull);
      expect(
        client
            .parseCollection(const {'id': 'c', 'list_count': '14'})!.songCount,
        14,
      );
      expect(
        client.parseCollection(const {'id': 'c', 'count': 15})!.songCount,
        15,
      );
      expect(
        client.parseCollection(const {
          'id': 'c',
          'more_info': <String, dynamic>{},
        })!.songCount,
        isNull,
        reason: 'absent everywhere: null, never 0',
      );
    });

    test('the subtitle falls back to the music line, then to the kind', () {
      expect(
        client.parseCollection(const {
          'id': 'c',
          'type': 'album',
          'more_info': {'music': 'Pritam'},
        })!.subtitle,
        'Pritam',
      );
      expect(
        client.parseCollection(const {'id': 'c', 'type': 'album'})!.subtitle,
        'ALBUM',
      );
      expect(
        client.parseCollection(const {'id': 'c', 'type': 'playlist'})!.subtitle,
        'PLAYLIST',
      );
      expect(
        client.parseCollection(
            const {'id': 'c', 'subtitle': 'Unknown'})!.subtitle,
        'PLAYLIST',
        reason: 'the sentinel is treated as empty',
      );
    });

    test('perma_url yields the token the resolution calls need', () {
      final withSlash = client.parseCollection(const {
        'id': 'c',
        'perma_url': 'https://www.jiosaavn.com/album/foo/AbC-D/',
      })!;
      expect(withSlash.permaToken, 'AbC-D');
      expect(withSlash.token, 'AbC-D');

      final withoutUrl = client.parseCollection(const {'id': 'c'})!;
      expect(withoutUrl.permaToken, isNull);
      expect(withoutUrl.token, isNull, reason: 'no crash on a missing url');

      final emptyUrl =
          client.parseCollection(const {'id': 'c', 'perma_url': '   '})!;
      expect(emptyUrl.permaToken, isNull);
    });

    test('language and year are optional and type-tolerant', () {
      final out = client.parseCollection(const {
        'id': 'c',
        'language': 'hindi',
        'year': 2024,
      })!;
      expect(out.language, 'hindi');
      expect(out.year, 2024);

      final missing = client.parseCollection(const {'id': 'c'})!;
      expect(missing.language, isNull);
      expect(missing.year, isNull);
    });
  });

  group('media url decryption and the 320 kbps rung', () {
    // The fixture is the one proven by `tool/des_check.dart`.
    const encrypted =
        'ID2ieOjCrwfgWvL5sXl4B1ImC5QfbsDy8nVlJ30W/JWSHLJuuQw3aQwm7MpPuw33buRfgf8pZQ4/IwtEzJQ4+Rw7tS9a8Gtq';
    const decrypted =
        'https://aac.saavncdn.com/423/852ad6cc81d7733c5e9bfc46d7b063e2_96.mp4';

    test('a real catalogue payload decrypts to the CDN url', () {
      expect(JioSaavnClient.decryptMediaUrl(encrypted), decrypted);
    });

    test('url-safe base64 (the `-`/`_` alphabet) decrypts identically', () {
      final urlSafe = encrypted.replaceAll('+', '-').replaceAll('/', '_');
      expect(urlSafe, isNot(encrypted), reason: 'fixture must exercise both');
      expect(JioSaavnClient.decryptMediaUrl(urlSafe), decrypted);
    });

    test('broken input returns null instead of throwing', () {
      expect(JioSaavnClient.decryptMediaUrl(''), isNull);
      expect(JioSaavnClient.decryptMediaUrl('not base64 at all !!!'), isNull);
      expect(JioSaavnClient.decryptMediaUrl('AAAA'), isNull,
          reason: '3 bytes is not a whole DES block');
      expect(JioSaavnClient.decryptMediaUrl('===='), isNull,
          reason: 'padding-only input decodes to nothing');
    });

    test('the rendition suffix is rewritten to the requested bitrate', () {
      expect(
        JioSaavnClient.rewriteBitrate(decrypted, 320),
        'https://aac.saavncdn.com/423/852ad6cc81d7733c5e9bfc46d7b063e2_320.mp4',
      );
      expect(
        JioSaavnClient.rewriteBitrate('https://x/y_96.mp3', 160),
        'https://x/y_160.mp3',
      );
      expect(
        JioSaavnClient.rewriteBitrate('https://x/y_96.MP4', 320),
        'https://x/y_320.MP4',
        reason: 'the suffix match is case-insensitive',
      );
      expect(
        JioSaavnClient.rewriteBitrate('https://x/y.mp4', 320),
        'https://x/y.mp4',
        reason: 'no rendition marker: assumed to be the master, left alone',
      );
    });

    test('artwork is upscaled to 500x500 for every extension', () {
      expect(JioSaavnClient.hires('https://c/x-150x150.jpg'),
          'https://c/x-500x500.jpg');
      expect(JioSaavnClient.hires('https://c/x-50x50.webp'),
          'https://c/x-500x500.webp');
      expect(JioSaavnClient.hires('https://c/x.jpg'), 'https://c/x.jpg');
      expect(JioSaavnClient.hires(''), '');
    });
  });

  group('Track.fromMap survives hostile persisted maps (Law 8)', () {
    test('non-map and empty input yield nothing', () {
      expect(Track.fromMap(null), isNull);
      expect(Track.fromMap('a string'), isNull);
      expect(Track.fromMap(42), isNull);
      expect(Track.fromMap(const <Object?, Object?>{}), isNull);
    });

    test('an entry with only a title is repaired with a derived id', () {
      final track = Track.fromMap(const {'title': 'Offline Song'})!;
      expect(track.id, startsWith('local-'));
      expect(track.title, 'Offline Song');
      expect(track.artist, 'Unknown');
      expect(track.bitrate, 320);
      expect(track.has320, isTrue);
    });

    test('wrong types in an old box do not poison the queue', () {
      final track = Track.fromMap(const {
        'id': 12,
        'title': 'T',
        'durationMs': '34000',
        'bitrate': '160',
        'addedAt': 'yesterday',
        'year': null,
        'localPath': '',
      })!;

      expect(track.id, '12');
      expect(track.duration, const Duration(seconds: 34));
      expect(track.bitrate, 160);
      expect(track.addedAt, isNull);
      expect(track.year, isNull);
      expect(track.localPath, isNull,
          reason: 'empty string means "not downloaded"');
      expect(track.isDownloaded, isFalse);
    });

    test('listFrom skips the rotten entries and keeps the good ones', () {
      final list = Track.listFrom(const [
        {'id': '1', 'title': 'One'},
        'garbage',
        null,
        <String, dynamic>{},
        {'id': '2', 'title': 'Two'},
      ]);
      expect(list.map((t) => t.id), ['1', '2']);
      expect(Track.listFrom('not a list'), isEmpty);
      expect(Track.listFrom(null), isEmpty);
    });

    test('toMap → fromMap is lossless for the playable fields', () {
      const original = Track(
        id: 'round',
        title: 'Round Trip',
        artist: 'Artist',
        artistsFull: 'Artist, Other',
        album: 'Album',
        imageUrl: 'https://c/x-500x500.jpg',
        duration: Duration(seconds: 181),
        streamUrl: 'https://aac.saavncdn.com/1/x_320.mp4',
        bitrate: 320,
        has320: true,
        localPath: 'C:/music/round.mp4',
        year: 2023,
        language: 'hindi',
        hasLyrics: true,
        playCount: 9,
        sizeBytes: 1024,
        sourceLabel: 'SEARCH // 320 KBPS AAC',
      );

      final restored = Track.fromMap(original.toMap())!;
      expect(restored.props, original.props);
      expect(restored.artistsFull, original.artistsFull);
      expect(restored.year, 2023);
      expect(restored.language, 'hindi');
      expect(restored.hasLyrics, isTrue);
      expect(restored.playCount, 9);
      expect(restored.sizeBytes, 1024);
      expect(restored.sourceLabel, 'SEARCH // 320 KBPS AAC');
      expect(restored.isDownloaded, isTrue);
      expect(restored.bitrateLabel, '320 KBPS');
    });

    test('dedupeKey folds punctuation, case and the (From "…") suffix', () {
      const a = Track(
          id: '1',
          title: 'Kesariya (From "Brahmastra")',
          artist: 'Arijit Singh');
      const b = Track(id: '2', title: 'kesariya', artist: 'arijit singh');
      expect(a.dedupeKey, b.dedupeKey);
      expect(Track.dedupe(const [a, b]).length, 1);
    });
  });
}

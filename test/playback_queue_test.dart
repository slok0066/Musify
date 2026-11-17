import 'package:flutter_test/flutter_test.dart';
import 'package:musify/data/models/track.dart';
import 'package:musify/data/repositories/library_repository.dart';
import 'package:musify/data/sources/local_store.dart';
import 'package:musify/presentation/cubits/player_cubit.dart';
import 'package:musify/services/player/playback_service.dart';
import 'package:musify/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;
  late PlaybackService player;
  late LocalStore store;
  late LibraryRepository library;
  late PlayerCubit cubit;

  final testTracks = [
    const Track(id: 'song_0', title: 'Song Zero', artist: 'Artist A'),
    const Track(id: 'song_1', title: 'Song One', artist: 'Artist B'),
    const Track(id: 'song_2', title: 'Song Two', artist: 'Artist C'),
    const Track(id: 'song_3', title: 'Song Three', artist: 'Artist D'),
  ];

  setUp(() {
    settings = SettingsService();
    store = LocalStore();
    library = LibraryRepository(store);
    player = PlaybackService(
      resolveSource: (track, {onProgress, prefetch = false}) async => null,
      settings: settings,
    );
    cubit = PlayerCubit(player: player, library: library, store: store);
  });

  tearDown(() async {
    await cubit.close();
  });

  group('Playlist track selection & queue preservation', () {
    test('tapping track in playlist preserves natural queue order and sets correct startIndex', () async {
      await cubit.playTrack(
        testTracks[2],
        context: testTracks,
        source: 'PLAYLIST // TEST',
      );

      // Natural order of testTracks [0, 1, 2, 3] must be preserved, not scrambled!
      expect(player.queue.value.length, 4);
      expect(player.queue.value[0].id, 'song_0');
      expect(player.queue.value[1].id, 'song_1');
      expect(player.queue.value[2].id, 'song_2');
      expect(player.queue.value[3].id, 'song_3');

      // The selected track is at index 2
      expect(player.queueIndex.value, 2);
    });

    test('tapping another track in the same playlist jumps to index without mutating queue', () async {
      await cubit.playTrack(
        testTracks[1],
        context: testTracks,
        source: 'PLAYLIST // TEST',
      );

      expect(player.queueIndex.value, 1);
      expect(player.queue.value.map((t) => t.id).toList(), [
        'song_0',
        'song_1',
        'song_2',
        'song_3',
      ]);

      // Tapping song 3 in the same playlist
      await cubit.playTrack(
        testTracks[3],
        context: testTracks,
        source: 'PLAYLIST // TEST',
      );

      // Queue is identical, index jumped to 3
      expect(player.queueIndex.value, 3);
      expect(player.queue.value.map((t) => t.id).toList(), [
        'song_0',
        'song_1',
        'song_2',
        'song_3',
      ]);
    });

    test('single track play without context sets 1-track queue', () async {
      await cubit.playTrack(testTracks[0]);

      expect(player.queue.value.length, 1);
      expect(player.queue.value.first.id, 'song_0');
      expect(player.queueIndex.value, 0);
    });
  });

  group('Rapid skip & repeat handling', () {
    test('rapid skips advance queue without dropping target or prematurely resetting to 0', () async {
      await cubit.playCollection(testTracks, startIndex: 0);
      expect(player.queueIndex.value, 0);

      // Rapidly skip 3 times
      await player.skipToNext();
      expect(player.queueIndex.value, 1);

      await player.skipToNext();
      expect(player.queueIndex.value, 2);

      await player.skipToNext();
      expect(player.queueIndex.value, 3);

      // At end of playlist with repeatMode.off, skipToNext pauses and stays on current track
      await player.skipToNext();
      expect(player.queueIndex.value, 3);
    });

    test('repeatMode.all wraps to 0 only when explicitly enabled', () async {
      await cubit.playCollection(testTracks, startIndex: 3);
      expect(player.queueIndex.value, 3);

      player.setRepeatMode(RepeatMode.all);
      await player.skipToNext();
      expect(player.queueIndex.value, 0);
    });
  });
}

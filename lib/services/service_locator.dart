import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../data/datasources/artwork_client.dart';
import '../data/datasources/jiosaavn_client.dart';
import '../data/datasources/lyrics_client.dart';
import '../data/datasources/playlist_importer.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/music_repository.dart';
import '../data/sources/local_store.dart';
import '../presentation/cubits/home_cubit.dart';
import '../presentation/cubits/library_cubit.dart';
import '../presentation/cubits/navigation_cubit.dart';
import '../presentation/cubits/player_cubit.dart';
import '../presentation/cubits/search_cubit.dart';
import '../presentation/cubits/settings_cubit.dart';
import 'backup_service.dart';
import 'media_cache.dart';
import 'network_monitor.dart';
import 'settings_service.dart';
import 'update_service.dart';
import 'player/playback_service.dart';

/// The one and only service locator.
final GetIt locator = GetIt.instance;

/// A desktop browser UA. JioSaavn gates `api.php` on a mobile-ish client and
/// returns a login wall to the default Dart agent, but no key or cookie is
/// involved — this is simply the header a phone browser would send.
const String _mobileUserAgent =
    'Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

bool get isMobilePlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Registers every dependency. Call once, before `runApp`.
///
/// Registration is synchronous and cheap so it can never be the reason a cold
/// start is slow; the *work* (opening Hive boxes, reading preferences) happens
/// in [bootstrapServices], which the caller time-boxes.
void configureDependencies() {
  if (locator.isRegistered<Dio>()) return;

  locator.registerLazySingleton<Dio>(() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 25),
        sendTimeout: const Duration(seconds: 12),
        followRedirects: true,
        maxRedirects: 5,
        headers: const {
          'User-Agent': _mobileUserAgent,
          'Accept': '*/*',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          // One silent retry for flaky mobile networks; a hard 4xx is final.
          final status = error.response?.statusCode ?? 0;
          final options = error.requestOptions;
          final attempts = (options.extra['attempts'] as int?) ?? 0;
          final retryable = error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              status == 429 ||
              status >= 500;

          if (retryable && attempts < 1 && !CancelToken.isCancel(error)) {
            options.extra['attempts'] = attempts + 1;
            unawaited(
              Future<void>.delayed(const Duration(milliseconds: 400)).then((_) {
                dio.fetch<dynamic>(options).then(
                  (response) => handler.resolve(response),
                  onError: (Object e) => handler.next(
                    e is DioException
                        ? e
                        : DioException(requestOptions: options, error: e),
                  ),
                );
              }),
            );
            return;
          }
          handler.next(error);
        },
      ),
    );

    return dio;
  });

  locator.registerLazySingleton<LocalStore>(LocalStore.new);
  locator.registerLazySingleton<SettingsService>(SettingsService.new);
  locator.registerLazySingleton<NetworkMonitor>(NetworkMonitor.new);
  locator.registerLazySingleton<MediaCache>(() => MediaCache(locator<Dio>()));

  locator.registerLazySingleton<JioSaavnClient>(() => JioSaavnClient(locator<Dio>()));
  locator.registerLazySingleton<LyricsClient>(() => LyricsClient(locator<Dio>()));
  locator.registerLazySingleton<ArtworkClient>(() => ArtworkClient(locator<Dio>()));

  locator.registerLazySingleton<LibraryRepository>(
    () => LibraryRepository(locator<LocalStore>()),
  );

  locator.registerLazySingleton<MusicRepository>(
    () => MusicRepository(
      saavn: locator<JioSaavnClient>(),
      lyrics: locator<LyricsClient>(),
      artwork: locator<ArtworkClient>(),
      cache: locator<MediaCache>(),
      settings: locator<SettingsService>(),
      network: locator<NetworkMonitor>(),
    ),
  );

  locator.registerLazySingleton<BackupService>(
    () => BackupService(
      store: locator<LocalStore>(),
      settings: locator<SettingsService>(),
    ),
  );

  locator.registerLazySingleton<UpdateService>(
    () => UpdateService(locator<Dio>()),
  );

  locator.registerLazySingleton<PlaylistImporter>(
    () => PlaylistImporter(locator<Dio>(), locator<MusicRepository>()),
  );

  locator.registerLazySingleton<PlaybackService>(
    () => PlaybackService(
      resolveSource: locator<MusicRepository>().resolvePlayable,
      openStream: locator<MusicRepository>().openStream,
      completedPath: locator<MusicRepository>().completedPathFor,
      settings: locator<SettingsService>(),
    ),
  );

  // Cubits are factories: a screen owns its instance and disposes it, so a
  // rebuilt route can never inherit stale scroll or query state.
  locator.registerFactory<NavigationCubit>(NavigationCubit.new);
  locator.registerFactory<HomeCubit>(
    () => HomeCubit(
      music: locator<MusicRepository>(),
      library: locator<LibraryRepository>(),
      store: locator<LocalStore>(),
      network: locator<NetworkMonitor>(),
    ),
  );
  locator.registerFactory<SearchCubit>(
    () => SearchCubit(
      music: locator<MusicRepository>(),
      library: locator<LibraryRepository>(),
    ),
  );
  // The Library is app-wide: its state is local, its toast channel is shared by
  // every screen, and the track options sheet reads it from anywhere.
  locator.registerLazySingleton<LibraryCubit>(
    () => LibraryCubit(
      library: locator<LibraryRepository>(),
      music: locator<MusicRepository>(),
      store: locator<LocalStore>(),
      backup: locator<BackupService>(),
      importer: locator<PlaylistImporter>(),
    ),
  );
  locator.registerFactory<SettingsCubit>(
    () => SettingsCubit(
      settings: locator<SettingsService>(),
      music: locator<MusicRepository>(),
      library: locator<LibraryRepository>(),
      backup: locator<BackupService>(),
      player: locator<PlaybackService>(),
      network: locator<NetworkMonitor>(),
    ),
  );
  locator.registerLazySingleton<PlayerCubit>(
    () => PlayerCubit(
      player: locator<PlaybackService>(),
      library: locator<LibraryRepository>(),
      music: locator<MusicRepository>(),
      store: locator<LocalStore>(),
    ),
  );
}

/// Opens every local store and hydrates settings.
///
/// Each step is independently guarded: a failure degrades that one subsystem
/// (Hive unavailable → empty Library) instead of blocking the others. The
/// caller wraps this in a timeout, so a hung disk can never hang the app.
Future<void> bootstrapServices() async {
  final steps = <String, Future<void> Function()>{
    'library': () => locator<LocalStore>().init(),
    'settings': () => locator<SettingsService>().load(),
    'network': () => locator<NetworkMonitor>().init(),
    'cache': () => locator<MediaCache>().init(),
  };

  await Future.wait(
    steps.entries.map((entry) async {
      try {
        await entry.value();
      } catch (e) {
        debugPrint('Bootstrap step "${entry.key}" failed, continuing: $e');
      }
    }),
  );
}

/// Boots the C++ audio engine and applies the persisted 8D configuration.
///
/// Called *after* the first frame so the UI is on screen before a single
/// sample is decoded — this is what keeps cold start under the PRD's 1.2 s.
Future<void> warmUpAudio() async {
  final player = locator<PlaybackService>();
  try {
    await player.initEngine();
    // Honour "auto 8D on headphones" if the device is already connected when
    // the engine comes up.
    final settings = locator<SettingsService>().value;
    if (settings.auto8DOnHeadphones && player.headphonesConnected.value) {
      await player.set8DEnabled(true);
    }
  } catch (e) {
    debugPrint('Audio warm-up skipped: $e');
  }
}

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/build_info.dart';
import 'core/theme/swiss_error_card.dart';
import 'data/repositories/library_repository.dart';
import 'data/sources/local_store.dart';
import 'services/media_cache.dart';
import 'services/player/audio_handler.dart';
import 'services/player/playback_service.dart';
import 'services/service_locator.dart';
import 'services/settings_service.dart';

/// Musify's entry point.
///
/// Every startup step is time-boxed and non-fatal (PRD Law 1): a dead network,
/// a locked disk or a missing audio device degrades one subsystem, and the user
/// still sees `01 // HOME` within the first frame or two.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // LAW 4 — a widget exception renders a Swiss recovery card, never the red
  // error box or a blank screen.
  ErrorWidget.builder = (details) => SwissErrorCard(details: details);

  configureDependencies();

  // Give the fault card enough context to name a *storage* failure, which is
  // otherwise invisible from the UI: a heart that does not fill and a library
  // that does not grow look identical whether the write failed or the button
  // never ran.
  SwissErrorCard.reportExtra = () {
    final store = locator<LocalStore>();
    final cache = locator<MediaCache>();
    return 'BUILD: $kBuildLabel\n'
        '${store.diagnostics()}\n'
        'CACHE: ready=${cache.isReady} bytes=${cache.cacheBytes.value}\n'
        'STREAM: live=${cache.activeStreams}\n'
        'SETTINGS: wifi=${locator<SettingsService>().value.wifiQuality} '
        'mobile=${locator<SettingsService>().value.mobileQuality} '
        'instant=${locator<SettingsService>().value.instantStart}';
  };

  await _guarded(
    'local stores',
    bootstrapServices,
    const Duration(seconds: 4),
  );

  // LAW 2's runtime half: the platform-specific audio session and lock screen
  // service come up before the first frame on mobile, and are simply absent on
  // desktop (where the same engine is driven directly).
  if (isMobilePlatform) {
    await _guarded(
      'audio service',
      () => _startAudioService(locator<PlaybackService>()),
      const Duration(seconds: 4),
    );
  }

  runApp(const MusifyApp());

  // The C++ engine is warmed up *after* the first frame, so no user-facing
  // paint ever waits on an audio device.
  unawaited(warmUpAudio());
}

Future<void> _startAudioService(PlaybackService player) async {
  final handler = await AudioService.init(
    builder: () => MusifyAudioHandler(
      player,
      likeDelegate: (track, liked) async {
        final library = locator<LibraryRepository>();
        if (liked) {
          await library.like(track);
        } else {
          await library.unlike(track.id);
        }
      },
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.musify.musify.audio',
      androidNotificationChannelName: 'Musify playback',
      androidNotificationChannelDescription: 'Playback controls for Musify',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidShowNotificationBadge: false,
    ),
  );

  locator.registerSingleton<MusifyAudioHandler>(handler);
  await handler.configureSession();
}

/// Home reloads the live rails the moment the transport comes back.
Future<void> _guarded(
  String label,
  Future<void> Function() task,
  Duration timeout,
) async {
  try {
    await task().timeout(timeout);
  } catch (e) {
    debugPrint('Startup step "$label" skipped: $e');
  }
}

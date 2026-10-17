package com.musify.musify

import com.ryanheise.audioservice.AudioServiceActivity

/**
 * CRITICAL: extends [AudioServiceActivity], never a plain FlutterActivity.
 *
 * Using FlutterActivity with audio_service causes a fatal crash / blank screen
 * on Android launch because the media notification and foreground service
 * lifecycle cannot bind to the engine.
 */
class MainActivity : AudioServiceActivity()

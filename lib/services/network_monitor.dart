import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Watches the device's transport and reports the two facts the app cares
/// about: *are we online* (Home switches to the offline fallback) and *are we
/// on unmetered Wi-Fi* (which streaming quality tier to pick).
///
/// Failures default to "online, not Wi-Fi" so a plugin hiccup can never lock
/// the user out of a feature.
class NetworkMonitor {
  NetworkMonitor();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isUnmetered = ValueNotifier<bool>(false);
  final ValueNotifier<ConnectivityResult?> transport =
      ValueNotifier<ConnectivityResult?>(null);

  Future<void> init() async {
    try {
      apply(await _connectivity.checkConnectivity());
      _sub = _connectivity.onConnectivityChanged.listen(apply);
    } catch (e) {
      debugPrint('NetworkMonitor init failed (assuming online): $e');
      isOnline.value = true;
      isUnmetered.value = false;
    }
  }

  @visibleForTesting
  void apply(List<ConnectivityResult> results) {
    final hasData = results.any(
      (r) => r != ConnectivityResult.none,
    );
    final wifi = results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet) ||
        results.contains(ConnectivityResult.vpn);

    transport.value = results.isEmpty ? null : results.first;
    isOnline.value = hasData;
    isUnmetered.value = wifi;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    isOnline.dispose();
    isUnmetered.dispose();
    transport.dispose();
  }
}

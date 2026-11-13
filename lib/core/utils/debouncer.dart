import 'dart:async';

import 'package:flutter/foundation.dart';

/// Collapses a burst of calls into a single trailing invocation.
///
/// Used by the search field so a fast typist fires one network request instead
/// of one per keystroke (the PRD specifies a 350ms window).
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 350)});

  final Duration duration;
  Timer? _timer;

  void call(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Runs [action] immediately and cancels anything pending.
  void runNow(VoidCallback action) {
    _timer?.cancel();
    action();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}

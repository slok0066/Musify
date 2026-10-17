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

  bool get isPending => _timer?.isActive ?? false;

  void dispose() => cancel();
}

/// Trailing-edge debouncer for streams.
extension DebounceStream<T> on Stream<T> {
  Stream<T> debounce(Duration duration) {
    Timer? timer;
    late StreamController<T> controller;
    T? latest;
    var hasValue = false;

    controller = StreamController<T>(
      onListen: () {
        final sub = listen(
          (event) {
            latest = event;
            hasValue = true;
            timer?.cancel();
            timer = Timer(duration, () {
              if (hasValue && !controller.isClosed) controller.add(latest as T);
            });
          },
          onError: (Object e, StackTrace s) {
            if (!controller.isClosed) controller.addError(e, s);
          },
          onDone: () {
            timer?.cancel();
            if (!controller.isClosed) controller.close();
          },
        );
        controller.onCancel = () async {
          timer?.cancel();
          await sub.cancel();
        };
      },
    );
    return controller.stream;
  }
}

import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

/// Lifecycle-aware, jittered background revalidation for one visible screen.
///
/// A poll is only a signal: [onPoll] reuses the screen provider's authorized
/// HTTP read. Calls never overlap, the app lifecycle pauses them, and
/// [canPoll] lets a screen suppress work while its route is covered or a list
/// is being reordered.
class PollingSignals with WidgetsBindingObserver {
  PollingSignals({
    required this.interval,
    required this.onPoll,
    this.canPoll,
    Random? random,
    this.jitter = true,
  }) : _random = random ?? Random();

  final Duration interval;
  final Future<void> Function() onPoll;
  final bool Function()? canPoll;
  final bool jitter;
  final Random _random;

  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _running = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();

    if (_foreground) {
      // Revalidate promptly after an unknown-length background gap, then
      // return to the ordinary cadence. [_tick] remains non-overlapping.
      unawaited(_tick());
    }
  }

  Duration get _nextDelay {
    if (!jitter) return interval;
    final factor = 0.9 + (_random.nextDouble() * 0.2);
    return Duration(
      microseconds: max(1, (interval.inMicroseconds * factor).round()),
    );
  }

  void _schedule() {
    if (_disposed || !_started || !_foreground) return;
    _timer = Timer(_nextDelay, _tick);
  }

  Future<void> _tick() async {
    _timer = null;
    if (_disposed || !_foreground) return;
    if (_running) return;

    _running = true;
    try {
      if (canPoll?.call() ?? true) await onPoll();
    } finally {
      _running = false;
      _schedule();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }
}

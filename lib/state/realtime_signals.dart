import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ports/filament_event_transport.dart';

/// Lifecycle-aware coalescing of private-channel events into HTTP refreshes.
///
/// Events received while a screen is temporarily unable to refresh remain
/// pending until [flush] is called (screens call it from build). Bursts never
/// overlap HTTP reads; at most one follow-up refresh runs after the current
/// one completes.
class RealtimeSignals with WidgetsBindingObserver {
  RealtimeSignals({
    required this.transport,
    required this.channels,
    required this.onSignal,
    this.canSignal,
  });

  final FilamentEventTransport transport;
  final List<String> channels;
  final Future<void> Function() onSignal;
  final bool Function()? canSignal;

  final List<StreamSubscription<RealtimeEvent>> _subscriptions = [];
  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _running = false;
  bool _pending = false;

  void start() {
    if (_started || _disposed || channels.isEmpty) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;

    for (final channel in channels.toSet()) {
      _subscriptions.add(
        transport
            .events(channel)
            .listen(
              (_) => _queue(),
              onError: (_) {
                // Transport failures are connectivity state, not screen failure.
                // The host adapter reconnects and emits RealtimeEvent.reconnected;
                // polling remains the fallback when no adapter is supplied.
              },
            ),
      );
    }
  }

  void _queue() {
    if (_disposed) return;
    _pending = true;
    unawaited(flush());
  }

  /// Attempts a pending refresh. Safe to call on every screen build.
  Future<void> flush() async {
    if (_disposed || !_foreground || _running || !_pending) return;
    if (!(canSignal?.call() ?? true)) return;

    _pending = false;
    _running = true;
    try {
      await onSignal();
    } finally {
      _running = false;
      if (_pending) unawaited(flush());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      // The socket may have reconnected or buffered events during an unknown
      // background gap. One authorized revalidation closes that gap.
      _pending = true;
      unawaited(flush());
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}

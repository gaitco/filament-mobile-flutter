import 'dart:async';

import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _EventTransport implements FilamentEventTransport {
  final controllers = <String, StreamController<RealtimeEvent>>{};

  @override
  Stream<RealtimeEvent> events(String channel) =>
      (controllers[channel] ??= StreamController.broadcast(sync: true)).stream;

  void add(String channel, RealtimeEvent event) {
    controllers[channel]!.add(event);
  }

  Future<void> close() async {
    for (final controller in controllers.values) {
      await controller.close();
    }
  }
}

void main() {
  test('realtime schema parses leniently and propagates resource channels', () {
    final panel = PanelSchema.fromJson(const {
      'version': 1,
      'panel': {
        'id': 'mobile',
        'title': 'Panel',
        'realtime': {
          'driver': 'reverb',
          'key': 'public',
          'host': 'ws.example.test',
          'port': 443,
          'scheme': 'wss',
          'authEndpoint': '/broadcasting/auth',
        },
      },
      'resources': [
        {
          'key': 'orders',
          'labels': {'singular': 'Order', 'plural': 'Orders'},
          'channel': 'mobile.orders',
        },
      ],
    });

    expect(panel.realtime?.host, 'ws.example.test');
    expect(panel.realtime?.scheme, 'wss');
    expect(panel.resources.single.channel, 'mobile.orders');
  });

  test('malformed realtime settings and channels disable push', () {
    expect(RealtimeConfig.fromJson(null), isNull);
    expect(
      RealtimeConfig.fromJson(const {
        'driver': 'reverb',
        'key': 'public',
        'host': 'host',
        'port': '443',
        'scheme': 'wss',
        'authEndpoint': '/broadcasting/auth',
      }),
      isNull,
    );

    final resource = ResourceSchema.fromJson(const {
      'key': 'orders',
      'labels': {'singular': 'Order', 'plural': 'Orders'},
      'channel': '',
    }, 'resources[0]');
    expect(resource.channel, isNull);
  });

  testWidgets('events coalesce and wait until the screen gate reopens', (
    tester,
  ) async {
    final transport = _EventTransport();
    var allowed = false;
    var calls = 0;
    final blocker = Completer<void>();
    final signals = RealtimeSignals(
      transport: transport,
      channels: const ['mobile.orders'],
      canSignal: () => allowed,
      onSignal: () async {
        calls++;
        if (calls == 1) await blocker.future;
      },
    )..start();

    transport.add(
      'mobile.orders',
      const RealtimeEvent.changed(resourceKey: 'orders'),
    );
    expect(calls, 0);

    allowed = true;
    final first = signals.flush();
    expect(calls, 1);

    transport.add(
      'mobile.orders',
      const RealtimeEvent.changed(resourceKey: 'orders'),
    );
    transport.add('mobile.orders', const RealtimeEvent.reconnected());
    expect(calls, 1, reason: 'a refresh must never overlap itself');

    blocker.complete();
    await tester.runAsync(() async {
      await first;
      await Future<void>.delayed(Duration.zero);
    });
    expect(calls, 2, reason: 'the burst becomes one follow-up refresh');

    await tester.runAsync(() async {
      await signals.dispose();
      await transport.close();
    });
  });

  testWidgets('resume performs one gap-closing revalidation', (tester) async {
    final transport = _EventTransport();
    var calls = 0;
    final signals = RealtimeSignals(
      transport: transport,
      channels: const ['mobile.orders'],
      onSignal: () async => calls++,
    )..start();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(calls, 1);

    await tester.runAsync(() async {
      await signals.dispose();
      await transport.close();
    });
  });
}

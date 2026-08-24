import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('panel poll config parses and propagates into every resource', () {
    final panel = PanelSchema.fromJson(const {
      'version': 1,
      'panel': {
        'id': 'mobile',
        'title': 'Panel',
        'poll': {'lists': 15, 'detail': 20, 'dashboard': 5},
      },
      'resources': [
        {
          'key': 'orders',
          'labels': {'singular': 'Order', 'plural': 'Orders'},
        },
      ],
    });

    expect(panel.poll?.lists, const Duration(seconds: 15));
    expect(panel.poll?.detail, const Duration(seconds: 20));
    expect(panel.poll?.dashboard, const Duration(seconds: 5));
    expect(panel.resources.single.poll, panel.poll);
  });

  test('malformed or absent poll config disables polling leniently', () {
    for (final value in <Object?>[
      null,
      false,
      const {'lists': 0, 'detail': 15, 'dashboard': 5},
      const {'lists': '15', 'detail': 15, 'dashboard': 5},
    ]) {
      expect(PollConfig.fromJson(value), isNull);
    }
  });

  testWidgets('polling fires on cadence and honours the screen gate', (
    tester,
  ) async {
    var calls = 0;
    var allowed = false;
    final signals = PollingSignals(
      interval: const Duration(seconds: 1),
      jitter: false,
      canPoll: () => allowed,
      onPoll: () async => calls++,
    )..start();

    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);

    allowed = true;
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);

    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);

    signals.dispose();
    await tester.pump();
  });

  testWidgets('polling pauses in background and revalidates on resume', (
    tester,
  ) async {
    var calls = 0;
    final signals = PollingSignals(
      interval: const Duration(seconds: 1),
      jitter: false,
      onPoll: () async => calls++,
    )..start();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 1);

    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);

    signals.dispose();
    await tester.pump();
  });
}

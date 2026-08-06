import 'package:flutter_test/flutter_test.dart';

/// Pumps [tester] until [finder] matches at least one widget, then returns.
///
/// A fixed pump count is not a wait: it either settles well before the real
/// work finishes (masking a bug that would show up under real latency) or
/// stalls short of it and asserts against a loading frame. This polls instead,
/// and **throws** rather than returning silently when [timeout] elapses, so a
/// test that never reaches the state it expects fails loudly instead of
/// passing against the wrong frame.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  const step = Duration(milliseconds: 50);
  var elapsed = Duration.zero;

  while (finder.evaluate().isEmpty) {
    if (elapsed >= timeout) {
      throw TestFailure(
        'pumpUntilFound timed out after $timeout waiting for $finder',
      );
    }
    await tester.pump(step);
    elapsed += step;
  }
}

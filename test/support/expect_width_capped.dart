import 'package:flutter_test/flutter_test.dart';

/// Asserts the widget matched by [finder] is really width-capped: no wider
/// than [cap], actually filling (not a zero-width degenerate), and centred in
/// a viewport of [viewportWidth] logical pixels.
void expectWidthCapped(
  WidgetTester tester,
  Finder finder, {
  required double cap,
  required double viewportWidth,
}) {
  final rect = tester.getRect(finder);
  expect(rect.width, lessThanOrEqualTo(cap), reason: 'width ≤ cap');
  expect(rect.width, greaterThan(cap * 0.5), reason: 'fills the cap');
  expect(
    (rect.left - (viewportWidth - rect.width) / 2).abs(),
    lessThan(1.0),
    reason: 'centred in the viewport',
  );
}

/// Asserts the widget matched by [finder] spans the whole viewport width.
void expectFullWidth(
  WidgetTester tester,
  Finder finder, {
  required double viewportWidth,
}) {
  final rect = tester.getRect(finder);
  expect(rect.left, lessThan(1.0));
  expect((rect.width - viewportWidth).abs(), lessThan(1.0));
}

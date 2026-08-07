import 'dart:ui';

import 'package:filament_mobile/ui/stat_sparkline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sparklinePoints', () {
    test('fewer than two points draws nothing', () {
      expect(sparklinePoints(const [], const Size(100, 40)), isEmpty);
      expect(sparklinePoints(const [5], const Size(100, 40)), isEmpty);
    });

    test('all-equal values draw a flat line at mid-height, not a NaN from a '
        'zero-range divide', () {
      final points = sparklinePoints(const [4, 4, 4], const Size(100, 40));

      expect(points, hasLength(3));
      for (final point in points) {
        expect(point.dy, 20);
        expect(point.dy.isNaN, isFalse);
      }
    });

    test('normalises the highest value to the top, lowest to the bottom', () {
      final points = sparklinePoints(const [0, 10], const Size(100, 40));

      expect(points.first.dy, 40); // lowest value -> bottom
      expect(points.last.dy, 0); // highest value -> top
    });

    test('spaces points evenly across the width', () {
      final points = sparklinePoints(const [1, 2, 3, 4], const Size(90, 40));

      expect(points.map((p) => p.dx), [0, 30, 60, 90]);
    });
  });
}

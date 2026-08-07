import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'semantic_badge.dart';

/// A stat's trend as a minimal line — no axes, no labels, no touch.
///
/// Hand-rolled `CustomPainter` rather than a charting package: this package
/// ships exactly two dependencies (`flutter`, `equatable`), and that is a
/// headline feature, not an oversight. A sparkline is small enough that
/// drawing it directly costs less than a third dependency would.
class StatSparkline extends StatelessWidget {
  const StatSparkline({
    required this.values,
    this.color,
    this.height = 32,
    super.key,
  });

  final List<double> values;

  /// A semantic colour name (`success`, `danger`, …) — the same vocabulary
  /// [SemanticBadge.colorFor] already maps.
  final String? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final resolved =
        SemanticBadge.colorFor(color) ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparklinePainter(values, resolved)),
    );
  }
}

/// Computes the polyline points for [values] within [size], with the
/// highest value at the top and the lowest at the bottom.
///
/// `@visibleForTesting` and free of any painting: the two degenerate cases —
/// fewer than two points, and a zero range (all values equal) — are the
/// specification, and are unit-tested directly against this function rather
/// than by inspecting a canvas.
@visibleForTesting
List<Offset> sparklinePoints(List<double> values, Size size) {
  if (values.length < 2) return const [];

  final minValue = values.reduce((a, b) => a < b ? a : b);
  final maxValue = values.reduce((a, b) => a > b ? a : b);
  final range = maxValue - minValue;
  final dx = size.width / (values.length - 1);

  return [
    for (var i = 0; i < values.length; i++)
      Offset(
        dx * i,
        // A zero range must not divide by zero — draw a flat line at
        // mid-height instead of a NaN-poisoned point.
        range == 0
            ? size.height / 2
            : size.height - ((values[i] - minValue) / range) * size.height,
      ),
  ];
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final points = sparklinePoints(values, size);
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      !listEquals(oldDelegate.values, values) || oldDelegate.color != color;
}

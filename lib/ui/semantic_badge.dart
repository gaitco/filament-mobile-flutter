import 'package:flutter/material.dart';

/// A value rendered as a chip, coloured by the semantic name the server maps
/// it to.
///
/// Shared by the card's badges and the infolist's `badge_entry` so both speak
/// the same colour language — a `status` that reads green in a list must not
/// read grey on the record it opens.
class SemanticBadge extends StatelessWidget {
  const SemanticBadge({required this.value, required this.colors, super.key});

  final String value;

  /// Value → semantic colour name, straight from the contract.
  final Map<String, String> colors;

  /// Semantic colour names the server may send. An unmapped value falls
  /// through to the theme's default chip colour rather than an alarming one.
  static const _palette = <String, Color>{
    'success': Color(0xFF16A34A),
    'warning': Color(0xFFF59E0B),
    'danger': Color(0xFFDC2626),
    'info': Color(0xFF2563EB),
    'gray': Color(0xFF6B7280),
  };

  @override
  Widget build(BuildContext context) {
    final semantic = colors[value];
    final colour = semantic == null ? null : _palette[semantic];

    return Chip(
      label: Text(value),
      backgroundColor: colour?.withValues(alpha: 0.12),
      labelStyle: colour == null ? null : TextStyle(color: colour),
      visualDensity: VisualDensity.compact,
    );
  }
}

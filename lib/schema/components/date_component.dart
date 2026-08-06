part of '../schema_component.dart';

enum DateKind { date, datetime }

final class DateComponent extends SchemaComponent {
  DateComponent._({
    required _CommonProperties common,
    required this.kind,
    required this.minDate,
    required this.maxDate,
    required this.defaultValue,
  }) : super._common(common);

  factory DateComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};
    return DateComponent._(
      common: common,
      kind: common.type == 'datetime' ? DateKind.datetime : DateKind.date,
      minDate: _parseDate(opt<String>(config, 'minDate')),
      maxDate: _parseDate(opt<String>(config, 'maxDate')),
      defaultValue: opt<String>(json, 'default'),
    );
  }

  /// A malformed bound reads as "no bound". A date picker with a wrong limit
  /// is a nuisance; a crashed form is an outage.
  ///
  /// A date-only string parses as local midnight, so it is reinterpreted as
  /// UTC — bounds are calendar dates, not instants, and must not shift by
  /// timezone.
  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || parsed.isUtc) return parsed;
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
    );
  }

  final DateKind kind;
  final DateTime? minDate;
  final DateTime? maxDate;

  /// Kept as the raw ISO string — the renderer owns formatting.
  final String? defaultValue;
}

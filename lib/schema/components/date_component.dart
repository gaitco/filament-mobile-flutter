part of '../schema_component.dart';

enum DateKind { date, datetime, time }

/// `date` / `datetime` / `time`. One class, because the three differ only in
/// which parts of a moment they carry.
///
/// **The step keys are advisory and nothing here acts on them.** A
/// `datetime`/`time` node publishes `hoursStep`/`minutesStep`/`secondsStep`
/// only when the panel configured a value > 1 — the contract states what the
/// field was configured with, for a host rendering its own picker (the
/// repeater `reorderable` precedent). This client parses them so a host
/// reading the same document sees one model, but the stock Material pickers
/// have no step grid (they derive their behaviour from the device locale,
/// like first-day-of-week), and the server does not enforce steps either —
/// silently snapping or rejecting a picked time would make mobile stricter
/// than the web panel it mirrors. Nothing reading this contract should infer
/// server-side enforcement from these keys.
final class DateComponent extends SchemaComponent {
  DateComponent._({
    required _CommonProperties common,
    required this.kind,
    required this.minDate,
    required this.maxDate,
    required this.seconds,
    required this.hoursStep,
    required this.minutesStep,
    required this.secondsStep,
    required this.defaultValue,
    required this.unreadableBounds,
  }) : super._common(common);

  factory DateComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};
    final kind = _kindOf(common.type);
    final minRaw = opt<String>(config, 'minDate');
    final maxRaw = opt<String>(config, 'maxDate');
    final minDate = _parseBound(minRaw, kind);
    final maxDate = _parseBound(maxRaw, kind);

    return DateComponent._(
      common: common,
      kind: kind,
      minDate: minDate,
      maxDate: maxDate,
      seconds: opt<bool>(config, 'seconds') ?? false,
      // Absent means 1, the vendor default — the walker publishes a step
      // only when it is > 1. Wrong-typed degrades to the same default
      // through `opt`, like any other advisory hint.
      hoursStep: opt<int>(config, 'hoursStep') ?? 1,
      minutesStep: opt<int>(config, 'minutesStep') ?? 1,
      secondsStep: opt<int>(config, 'secondsStep') ?? 1,
      defaultValue: opt<String>(json, 'default'),
      // A bound that arrived and could not be read is not the same event as
      // one that was never declared — see [unreadableBounds].
      unreadableBounds: {
        if (minRaw != null && minDate == null) 'minDate',
        if (maxRaw != null && maxDate == null) 'maxDate',
      },
    );
  }

  /// Genuinely three-way. This used to be `type == 'datetime' ? datetime :
  /// date`, under which a third type reads as `date` with nothing to notice
  /// it — and a `time` node read as a date is exactly how its bounds get
  /// thrown away (see [parseTime]).
  static DateKind _kindOf(String type) => switch (type) {
    'datetime' => DateKind.datetime,
    'time' => DateKind.time,
    _ => DateKind.date,
  };

  /// A malformed bound reads as "no bound". A picker with a wrong limit is a
  /// nuisance; a crashed form is an outage.
  ///
  /// It is still a contract violation, so the key is recorded in
  /// [unreadableBounds] rather than being indistinguishable from a bound the
  /// panel never declared — the distinction [RichDocument] draws between an
  /// absent `content` key and a malformed one.
  static DateTime? _parseBound(String? raw, DateKind kind) {
    if (raw == null) return null;
    return kind == DateKind.time ? parseTime(raw) : _parseDate(raw);
  }

  /// A date-only string parses as local midnight, so it is reinterpreted as
  /// UTC — bounds are calendar dates, not instants, and must not shift by
  /// timezone.
  static DateTime? _parseDate(String raw) {
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

  /// Reads a clock time — a `time` node's bound, and its stored value.
  ///
  /// **`DateTime.tryParse('09:00')` returns null.** The server publishes a
  /// time bound exactly as the panel declared it (`getMinDate()` is
  /// `evaluate($this->minDate)` and nothing more, measured in vendor), so
  /// `"09:00"` is the ordinary case — and reading it with the date parse
  /// would silently delete a bound the panel really set, then offer the user
  /// times the server rejects, through the very path written to be safe.
  ///
  /// A panel that declared its bound as a Carbon publishes
  /// `"2026-01-01 09:00:00"` instead, which [DateTime.tryParse] does read.
  /// Only the clock reading is meaningful for a time field, so both shapes
  /// normalise onto one comparable value.
  ///
  /// Public because the renderer parses a stored `"14:05:00"` the same way it
  /// parses a bound; one parser, so the two cannot drift.
  static DateTime? parseTime(String raw) {
    final full = DateTime.tryParse(raw);
    if (full != null) return timeOfDay(full.hour, full.minute, full.second);

    final match = _clockTime.firstMatch(raw.trim());
    if (match == null) return null;

    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    final second = int.parse(match[3] ?? '0');
    // `DateTime.utc(1970, 1, 1, 25)` is a perfectly valid DateTime — 01:00
    // the next day — so without this check a nonsense bound would arrive as a
    // plausible one.
    if (hour > 23 || minute > 59 || second > 59) return null;

    return timeOfDay(hour, minute, second);
  }

  static final RegExp _clockTime = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$');

  /// A time carries no date — the panel never chose one — so every `time`
  /// value is anchored to the same arbitrary UTC day and only its [hour],
  /// [minute] and [second] mean anything.
  static DateTime timeOfDay(int hour, int minute, int second) =>
      DateTime.utc(1970, 1, 1, hour, minute, second);

  final DateKind kind;

  /// For [DateKind.time] these are times of day on the canonical day
  /// [timeOfDay] anchors to, not calendar instants.
  final DateTime? minDate;
  final DateTime? maxDate;

  /// Whether the picker offers seconds. Also decides the wire format of a
  /// `time` value — `HH:mm:ss` against `HH:mm`, matching TimePicker's own
  /// `H:i:s`/`H:i`.
  final bool seconds;

  /// The panel's picker steps, 1 when unpublished. Advisory only — see the
  /// class doc for why the widgets deliberately ignore them.
  final int hoursStep;
  final int minutesStep;
  final int secondsStep;

  /// Config keys (`minDate` / `maxDate`) the server sent and this build could
  /// not read. Empty in the normal case, **including** when the panel
  /// declared no bound at all — that is not a violation, and conflating the
  /// two is how a deleted bound stays invisible.
  final Set<String> unreadableBounds;

  /// Kept as the raw ISO string — the renderer owns formatting.
  final String? defaultValue;
}

import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../schema/card_layout.dart';
import '../schema/media_set.dart';
import 'bidi_text.dart';
import 'semantic_badge.dart';

/// The field-reading/formatting logic shared by [ResourceCard] and
/// [ResourceRow] — extracted rather than duplicated once a second widget
/// needed the exact same title/subtitle/badge/meta rendering rules
/// (P23 Task 2).
///
/// [formatDates] gates the ISO-8601 → localised-short-date rewrite — only the
/// `meta` caller sets it, preserving the pre-P6f behaviour (a title/subtitle/
/// badge holding a timestamp-shaped string prints it raw). [context] is
/// unconditional regardless of that flag: every returned string still needs
/// it to resolve the ambient [Directionality] for [isolateBidi].
///
/// [isolate] defaults to true and is set false only by the badge caller: a
/// badge's value is about to become [SemanticBadge]'s colour-lookup key, and
/// isolating it here first would isolate the *key* before the lookup runs,
/// breaking `colors[value]` for any value that matches the grouped-digit
/// pattern (fix round 1, finding 1). `SemanticBadge` isolates its own
/// displayed text after doing that lookup on the raw value.
String? cardFieldText(
  ResourceRecord record,
  BuildContext context,
  String? field, {
  bool formatDates = false,
  bool isolate = true,
}) {
  if (field == null) return null;

  String raw;

  // A rich column publishes its plain text on a flat sibling key,
  // `<field>.__rich.text` (design spec, "Cards") — read that instead of the
  // raw markup the base field still holds. Absent sibling means nothing to
  // convert, and falls through to the raw value below like any other field.
  if (record.get<Map<String, dynamic>>('$field.__rich') case {
    'text': final String text,
  }) {
    raw = text;
  } else {
    final value = record.get<Object>(field);

    if (value == null) return null;

    // A timestamp arrives as raw ISO 8601 — printing it verbatim puts LTR
    // digits and a `T` in the middle of an RTL card. `MaterialLocalizations`
    // formats it in the app's own locale with no new dependency.
    final date = formatDates ? _asDate(value) : null;

    raw = date != null
        ? MaterialLocalizations.of(context).formatShortDate(date)
        : value.toString();
  }

  if (!isolate) return raw;

  // Grouped digits (a phone number, a spaced IBAN, a hyphenated tax number)
  // reverse inside an RTL card otherwise — see `bidi_text.dart`.
  return isolateBidi(raw, Directionality.of(context));
}

/// An ISO-8601 timestamp, or null for anything else.
///
/// Deliberately strict: a bare number or a short code must not be coaxed into
/// a date, so only a string Dart itself parses as one counts. Parsed as UTC
/// then shown locally, matching what the panel displays.
DateTime? _asDate(Object value) {
  if (value is DateTime) return value.toLocal();
  if (value is! String || value.length < 10) return null;

  return DateTime.tryParse(value)?.toLocal();
}

/// One badge slot's widget, or null when the field has no renderable value.
///
/// A boolean value becomes a [BooleanBadge] — detected on the raw typed
/// value, upstream of [cardFieldText]'s `toString()`: after stringification a
/// real bool and the string "true" are indistinguishable, and the string must
/// keep rendering as an ordinary text badge. Every other type takes the text
/// path.
Widget? cardBadgeWidget(
  CardBadge badge,
  ResourceRecord record,
  BuildContext context,
) {
  if (record.get<Object>(badge.field) case final raw? when raw is bool) {
    return BooleanBadge(value: raw, colors: badge.colors);
  }

  if (cardFieldText(record, context, badge.field, isolate: false)
      case final value?) {
    return SemanticBadge(value: value, colors: badge.colors);
  }

  return null;
}

/// The leading avatar image/icon a card or row shows when [CardLayout.leading]
/// is set — the same size/shape logic for both, extracted so a wide list's
/// row and its narrow-screen card never drift apart.
class CardLeadingAvatar extends StatelessWidget {
  const CardLeadingAvatar({
    required this.leading,
    required this.record,
    required this.title,
    super.key,
  });

  final CardLeading leading;
  final ResourceRecord record;
  final String? title;

  @override
  Widget build(BuildContext context) {
    // A medialibrary-backed field's raw value is an opaque uuid token, not a
    // URL — the flat `<field>.__media` sibling (design spec, "Wire shape")
    // is where the resolved URL lives. No sibling falls back to the raw
    // value.
    final media = MediaSet.of(record, leading.field);
    final url = media != null && media.items.isNotEmpty
        ? media.items.first.displayUrl
        : record.get<String>(leading.field);

    // A media-library image serialises as null today (a known server-side
    // gap). Falling back silently is deliberate: an empty optional image
    // must not look like a failure.
    if (url == null || url.isEmpty) {
      return CircleAvatar(child: Text(_initial));
    }

    // `foregroundImage`, not `backgroundImage`: the foreground paints OVER the
    // child, so the initial below shows through when the URL 404s or the
    // device is offline. With a background image the child had to be null to
    // avoid drawing the initial across the photo, which left a dead URL
    // rendering as a blank coloured disc.
    return CircleAvatar(
      foregroundImage: NetworkImage(url),
      onForegroundImageError: (_, _) {},
      child: Text(_initial),
    );
  }

  String get _initial {
    final source = title?.trim() ?? '';
    return source.isEmpty ? '?' : source.characters.first;
  }
}

import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../schema/card_layout.dart';
import 'bidi_text.dart';
import 'semantic_badge.dart';

/// One record as a list card — the mobile answer to Filament's data table.
///
/// Every slot is optional and a slot whose field resolves to null is omitted
/// entirely. Degraded data (a null media image, a badge value with no declared
/// colour) renders as though it were intentional: the gaps are surfaced to
/// developers through the server's `_warnings` and `doctor`, never to the user.
class ResourceCard extends StatelessWidget {
  const ResourceCard({
    required this.layout,
    required this.record,
    this.onTap,
    super.key,
  });

  final CardLayout layout;
  final ResourceRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _text(layout.titleField, context);
    final subtitle = _text(layout.subtitleField, context);

    // A hairline outline instead of the default elevated fill. Filled cards
    // stacked with no gap read as a wall of grey slabs — the owner's
    // screenshot of a relation section showed exactly that. An outline keeps
    // each row distinct while letting the page background stay the surface.
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (layout.leading != null) ...[
                _Leading(
                  leading: layout.leading!,
                  record: record,
                  title: title,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null)
                      Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null)
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    if (layout.badges.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final badge in layout.badges)
                            if (_text(badge.field, context, isolate: false)
                                case final value?)
                              SemanticBadge(value: value, colors: badge.colors),
                        ],
                      ),
                    ],
                    if (layout.meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      for (final meta in layout.meta)
                        if (_text(meta.field, context, formatDates: true)
                            case final value?)
                          Text(value, style: theme.textTheme.labelSmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [formatDates] gates the ISO-8601 → localised-short-date rewrite below —
  /// today only the caller passing `meta` sets it, preserving the pre-P6f
  /// behaviour exactly (a title/subtitle/badge holding a timestamp-shaped
  /// string prints it raw, same as always). [context] is unconditional
  /// regardless of that flag: every returned string still needs it to
  /// resolve the ambient [Directionality] for [isolateBidi].
  ///
  /// [isolate] defaults to true and is set false only by the badge caller:
  /// a badge's value is about to become [SemanticBadge]'s colour-lookup key,
  /// and isolating it here first would isolate the *key* before the lookup
  /// runs, breaking `colors[value]` for any value that matches the
  /// grouped-digit pattern (fix round 1, finding 1). `SemanticBadge` isolates
  /// its own displayed text after doing that lookup on the raw value.
  String? _text(
    String? field,
    BuildContext context, {
    bool formatDates = false,
    bool isolate = true,
  }) {
    if (field == null) return null;

    String raw;

    // A rich column publishes its plain text on a flat sibling key,
    // `<field>.__rich.text` (design spec, "Cards") — read that instead of
    // the raw markup the base field still holds. Absent sibling means
    // nothing to convert (or a `->prose()`-only entry, which `index()` never
    // resolves), and falls through to the raw value below like any other
    // field.
    if (record.get<Map<String, dynamic>>('$field.__rich') case {
      'text': final String text,
    }) {
      raw = text;
    } else {
      final value = record.get<Object>(field);

      if (value == null) return null;

      // A timestamp arrives as raw ISO 8601 — `2026-03-24T08:41:19.000000Z` —
      // and printing it verbatim puts LTR digits and a `T` in the middle of an
      // RTL card. `MaterialLocalizations` formats it in the app's own locale
      // with no new dependency, which is why this needs no `intl`.
      final date = formatDates ? _asDate(value) : null;

      raw = date != null
          ? MaterialLocalizations.of(context).formatShortDate(date)
          : value.toString();
    }

    if (!isolate) return raw;

    // Grouped digits (a phone number, a spaced IBAN, a hyphenated tax
    // number) reverse inside an RTL card otherwise — see `bidi_text.dart`.
    // A no-op under LTR and on plain prose with no such run.
    return isolateBidi(raw, Directionality.of(context));
  }

  /// An ISO-8601 timestamp, or null for anything else.
  ///
  /// Deliberately strict: a bare number or a short code must not be coaxed
  /// into a date, so only a string Dart itself parses as one counts. Parsed as
  /// UTC then shown locally, matching what the panel displays.
  static DateTime? _asDate(Object value) {
    if (value is DateTime) return value.toLocal();
    if (value is! String || value.length < 10) return null;

    return DateTime.tryParse(value)?.toLocal();
  }
}

class _Leading extends StatelessWidget {
  const _Leading({
    required this.leading,
    required this.record,
    required this.title,
  });

  final CardLeading leading;
  final ResourceRecord record;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final url = record.get<String>(leading.field);

    // A media-library image serialises as null today (a known server-side gap).
    // Falling back silently is deliberate: an empty optional image must not
    // look like a failure.
    if (url == null || url.isEmpty) {
      return CircleAvatar(child: Text(_initial));
    }

    return CircleAvatar(
      backgroundImage: NetworkImage(url),
      onBackgroundImageError: (_, _) {},
      child: url.isEmpty ? Text(_initial) : null,
    );
  }

  String get _initial {
    final source = title?.trim() ?? '';
    return source.isEmpty ? '?' : source.characters.first;
  }
}

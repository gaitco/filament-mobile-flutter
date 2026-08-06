import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../schema/card_layout.dart';
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
    final title = _text(layout.titleField);
    final subtitle = _text(layout.subtitleField);

    return Card(
      child: InkWell(
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
                            if (_text(badge.field) case final value?)
                              SemanticBadge(value: value, colors: badge.colors),
                        ],
                      ),
                    ],
                    if (layout.meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      for (final meta in layout.meta)
                        if (_text(meta.field, context) case final value?)
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

  String? _text(String? field, [BuildContext? context]) {
    if (field == null) return null;
    final value = record.get<Object>(field);

    if (value == null) return null;

    // A timestamp arrives as raw ISO 8601 — `2026-03-24T08:41:19.000000Z` —
    // and printing it verbatim puts LTR digits and a `T` in the middle of an
    // RTL card. `MaterialLocalizations` formats it in the app's own locale
    // with no new dependency, which is why this needs no `intl`.
    if (context != null) {
      final date = _asDate(value);

      if (date != null) {
        return MaterialLocalizations.of(context).formatShortDate(date);
      }
    }

    return value.toString();
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

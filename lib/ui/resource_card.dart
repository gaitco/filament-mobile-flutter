import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../schema/card_layout.dart';
import 'card_fields.dart';

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
    this.trailing,
    super.key,
  });

  final CardLayout layout;
  final ResourceRecord record;
  final VoidCallback? onTap;

  /// Pinned to the row's trailing edge — today only `RelationListScreen`'s
  /// per-row edit/delete affordances (P9). Null everywhere else, and the
  /// card's layout is untouched in that case.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = cardFieldText(record, context, layout.titleField);
    final subtitle = cardFieldText(record, context, layout.subtitleField);

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
                CardLeadingAvatar(
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
                            if (cardBadgeWidget(badge, record, context)
                                case final widget?)
                              widget,
                        ],
                      ),
                    ],
                    if (layout.meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      for (final meta in layout.meta)
                        if (cardFieldText(
                              record,
                              context,
                              meta.field,
                              formatDates: true,
                            )
                            case final value?)
                          Text(value, style: theme.textTheme.labelSmall),
                    ],
                  ],
                ),
              ),
              // Inside the InkWell, so the row's own onTap still owns the
              // card body — a trailing control (an IconButton) hit-tests
              // itself above the ink response.
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../data/resource_record.dart';
import '../schema/card_layout.dart';
import 'card_fields.dart';

/// Which shape [PaginatedCardList] renders records as — a stack of cards
/// (phones) or table-like rows with a header (wide screens, P23 adaptive
/// layout).
enum ListRowStyle {
  /// The default: a [ResourceCard] per record, unchanged from before P23.
  card,

  /// A [ResourceRow] per record — a Filament-style data table.
  row,
}

/// Column layout shared by [ResourceRow] and [ResourceRowHeader] so a
/// header cell always lines up with the value beneath it. Fixed widths for
/// the leading slot, flex ratios for everything else.
const double _leadingWidth = 40;

/// One flex unit per column, shared by both widgets for the same reason.
///
/// Badges and dates are the columns that break first: a chip and a formatted
/// date have a hard floor and clip below it, while a title and a subtitle
/// merely ellipsize. Hence two units each rather than the one they started
/// with; below the widths named under [_metaMinWidth] they are dropped
/// instead.
const int _titleFlex = 4;
const int _subtitleFlex = 3;
const int _badgeFlex = 2;
const int _metaFlex = 2;

/// Row widths under which a column is dropped instead of squeezed.
///
/// A chip and a formatted short date have hard floors — roughly 75 and 85
/// logical pixels — and neither degrades gracefully: the chip clips its
/// label mid-word and the date ellipsises to "Aug 6, 20…". Shedding the
/// lowest-priority column is what a responsive data table does, and it is
/// the only option here that keeps a row and its header in step, since both
/// widgets decide from the same width.
///
/// Sized from the shell's own geometry: a 1440pt window gives the master
/// pane ~480pt, which fits a title, a subtitle and a badge but not a date.
const double _metaMinWidth = 560;
const double _badgeMinWidth = 300;

/// Which optional columns fit in [width] — the one rule both the row and its
/// header call, so a header cell can never outlive the values under it.
({bool badges, bool meta}) _columnsFor(double width) =>
    (badges: width >= _badgeMinWidth, meta: width >= _metaMinWidth);

/// One record as a table row — the wide-screen answer to [ResourceCard],
/// same data, laid out horizontally instead of stacked (P23 Task 2).
///
/// Every slot [ResourceCard] reads from [CardLayout] is read here too, via
/// the same [cardFieldText]/[cardBadgeWidget]/[CardLeadingAvatar] helpers —
/// a badge or a formatted date must not drift between the two shapes just
/// because the viewport got wider.
class ResourceRow extends StatelessWidget {
  const ResourceRow({
    required this.layout,
    required this.record,
    this.onTap,
    this.trailing,
    this.selected = false,
    super.key,
  });

  final CardLayout layout;
  final ResourceRecord record;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Paints [ColorScheme.secondaryContainer] behind the row — a wide list's
  /// answer to a selected list tile, since a card's own selection has no
  /// equivalent to react to yet.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = cardFieldText(record, context, layout.titleField);
    final subtitle = cardFieldText(record, context, layout.subtitleField);

    return Material(
      color: selected ? theme.colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = _columnsFor(constraints.maxWidth);

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (layout.leading != null) ...[
                    SizedBox(
                      width: _leadingWidth,
                      child: CardLeadingAvatar(
                        leading: layout.leading!,
                        record: record,
                        title: title,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: _titleFlex,
                    child: Text(
                      title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: _subtitleFlex,
                    child: Text(
                      subtitle ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (columns.badges)
                    for (final badge in layout.badges) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        flex: _badgeFlex,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child:
                              cardBadgeWidget(badge, record, context) ??
                              const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  if (columns.meta)
                    for (final meta in layout.meta) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        flex: _metaFlex,
                        child: Text(
                          cardFieldText(
                                record,
                                context,
                                meta.field,
                                formatDates: true,
                              ) ??
                              '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  if (trailing != null) trailing!,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The column labels above a [ResourceRow] table — same flex ratios as the
/// row so a value always sits under its header, whatever the field name
/// (P23 Task 2).
class ResourceRowHeader extends StatelessWidget {
  const ResourceRowHeader({required this.layout, super.key});

  final CardLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _columnsFor(constraints.maxWidth);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (layout.leading != null) ...[
                const SizedBox(width: _leadingWidth),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: _titleFlex,
                child: Text(_label(layout.titleField), style: style),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: _subtitleFlex,
                child: Text(_label(layout.subtitleField), style: style),
              ),
              if (columns.badges)
                for (final badge in layout.badges) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: _badgeFlex,
                    child: Text(_label(badge.field), style: style),
                  ),
                ],
              if (columns.meta)
                for (final meta in layout.meta) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: _metaFlex,
                    child: Text(_label(meta.field), style: style),
                  ),
                ],
            ],
          );
        },
      ),
    );
  }

  String _label(String? field) => field == null ? '' : humanizeField(field);
}

/// `created_at` → "Created at", `category.name` → "Category name": split on
/// `_`/`.`, capitalise only the first word. Deliberately not full title case
/// — a table header reads as a phrase, not a heading.
String humanizeField(String field) {
  final words = field
      .split(RegExp('[._]'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return field;

  final first = words.first;
  final capitalised = first[0].toUpperCase() + first.substring(1);
  return [capitalised, ...words.skip(1)].join(' ');
}

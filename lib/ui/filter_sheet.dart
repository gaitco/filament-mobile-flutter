import 'package:flutter/material.dart';

import '../data/options_page.dart';
import '../form/field_state.dart';
import '../form/fields/field_widgets.dart';
import '../ports/filament_strings.dart';
import '../schema/schema_component.dart';
import '../state/resource_list_provider.dart';

/// The value written into a filter node's synthetic "Any" option, and read
/// back out of [SelectFieldWidget]'s `onChanged` to translate a user's
/// explicit "Any" pick into [ResourceListProvider.setFilter]'s `null` — an
/// explicit clear, never an omitted parameter (see that method's doc for why
/// the distinction matters). Reuses [ResourceListProvider]'s own
/// "explicitly cleared" sentinel rather than inventing a second one.
const _anyValue = '';

/// The filter sheet's content (P24): every filter node the resource
/// publishes (`provider.resource.filters`), each rendered through the
/// package's own [SelectFieldWidget] against the provider's live filter
/// state, plus a "Clear all" action.
///
/// A plain content widget, not itself a route — `ResourceListScreen`
/// decides whether to host it in a `showModalBottomSheet` (compact) or a
/// `showDialog` (medium/expanded), and wraps it in the `Directionality` a
/// sheet/dialog route does not inherit on its own; see that screen's
/// `_openFilterSheet`.
///
/// **Reuse, don't re-render:** a filter node is a `select`-shaped
/// [SchemaComponent] in the existing vocabulary (`ResourceListProvider`'s
/// own seeding doc), so this renders it with [SelectFieldWidget] rather than
/// writing a second select control.
class FilterSheet extends StatelessWidget {
  const FilterSheet({
    required this.provider,
    this.strings = const FilamentStrings(),
    super.key,
  });

  final ResourceListProvider provider;
  final FilamentStrings strings;

  @override
  Widget build(BuildContext context) {
    // Listens on its own, independent of whatever opened it (a
    // `showModalBottomSheet`/`showDialog` route is a sibling in the
    // Navigator's overlay, not a descendant of the screen that pushed it) —
    // so picking one filter's value is reflected immediately in this same
    // sheet, not just after it closes and the screen behind it rebuilds.
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    strings.filters,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: () => _clearAndClose(context),
                    child: Text(strings.clearFilters),
                  ),
                ],
              ),
              for (final node in provider.resource.filters)
                if (node is SelectComponent && node.name != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _field(node),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearAndClose(BuildContext context) async {
    await provider.clearFilters();
    if (context.mounted) Navigator.of(context).pop();
  }

  Widget _field(SelectComponent node) {
    final name = node.name!;
    final remote = node.optionsUrl != null;
    final rendered = remote || node.multiple ? node : _withAnyOption(node);

    // A key absent from `provider.filters` (never touched, no seeded
    // default) and one holding the explicit `''` (touched, then cleared)
    // both mean "no filter" — normalised to the same `''` here so a
    // never-touched filter's picker shows "Any" selected exactly like a
    // cleared one does, rather than blank (no option matching `null`).
    //
    // A multiselect filter's cleared state is that same `''` — but
    // `SelectFieldWidget._multi` casts its value straight to a
    // `List<Object?>?`, which would throw on a bare String. Translated to
    // `null` (no selection) here so a multiselect filter someone just
    // cleared, or never touched, can still be reopened without crashing.
    final raw = provider.filters[name] ?? '';
    final value = node.multiple && raw == '' ? null : raw;

    return SelectFieldWidget(
      component: rendered,
      state: FieldState(
        value: value,
        onChanged: (v) => provider.setFilter(name, v == _anyValue ? null : v),
        searchOptions: remote
            ? (query) async {
                final page = await provider.searchFilterOptions(name, query);
                if (node.multiple) return page;

                return OptionsPage(
                  options: [
                    SelectOption(
                      value: _anyValue,
                      label: node.placeholder ?? strings.anyOption,
                    ),
                    for (final option in page.options)
                      if (option.value != _anyValue) option,
                  ],
                  hasMore: page.hasMore,
                );
              }
            : null,
        strings: strings,
      ),
    );
  }

  /// Rebuilds [node] through the public `SchemaComponent.fromJson` front
  /// door with a synthetic "Any" option prepended — [SelectComponent]'s own
  /// constructor is private to its schema library, so JSON is the only way
  /// this UI-layer widget can hand [SelectFieldWidget] a node with one extra
  /// choice. Mirrors Filament's own web filter, which renders the same
  /// blank placeholder row ahead of a ternary's two real choices.
  ///
  /// The blank row is labelled with the node's own
  /// [SelectComponent.placeholder] when it has one, falling back to
  /// [FilamentStrings.anyOption] when it does not. A `TrashedFilter`'s blank
  /// branch is `withoutTrashed()`, not "no filter", so calling it "Any"
  /// would claim the filter had been removed when it had not.
  ///
  /// An option the panel keyed `''` is dropped rather than rendered: it
  /// would be a SECOND entry sharing the "Any" value, which trips
  /// `DropdownButton`'s "exactly one item" assertion and takes the sheet
  /// down. Dropping loses nothing — the server reads a blank select value as
  /// "any" (`FilterApplier::dataFor()`), so such an option can never narrow
  /// anything even if it were selectable.
  ///
  /// Called only for inline single-value filters. Remote filters keep their
  /// original node and receive the synthetic "Any" result in [_field]'s
  /// search closure, so rebuilding this node can never discard optionsUrl.
  SelectComponent _withAnyOption(SelectComponent node) {
    return SchemaComponent.fromJson({
          'type': node.type,
          'name': node.name,
          'label': node.label,
          if (node.direction != null) 'direction': node.direction!.name,
          'config': {
            'options': [
              {
                'value': _anyValue,
                'label': node.placeholder ?? strings.anyOption,
              },
              for (final option in node.options)
                if (option.value != _anyValue)
                  {'value': option.value, 'label': option.label},
            ],
          },
        }, 'filters.${node.name}')
        as SelectComponent;
  }
}

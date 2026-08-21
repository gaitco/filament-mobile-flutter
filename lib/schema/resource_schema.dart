import 'package:equatable/equatable.dart';

import 'card_layout.dart';
import 'json_reader.dart';
import 'relation_descriptor.dart';
import 'resource_labels.dart';
import 'schema_component.dart';

/// The panel's layout direction, published on the wire as a closed set.
///
/// Deliberately not `dart:ui`'s `TextDirection` — the schema layer imports
/// only `equatable` and its own siblings, no Flutter. The UI layer maps this
/// to `TextDirection` where it renders.
enum PanelDirection {
  ltr,
  rtl;

  /// Absent or unrecognised reads as [ltr] — a server predating this field,
  /// or one whose override didn't survive normalisation, gets today's
  /// behaviour rather than a thrown error. The server already normalises
  /// `direction` to `ltr`/`rtl`; the client does not trust that it did.
  static PanelDirection fromJson(Object? value) =>
      value == 'rtl' ? PanelDirection.rtl : PanelDirection.ltr;
}

class ResourceSearch extends Equatable {
  const ResourceSearch({this.enabled = false, this.placeholder});

  factory ResourceSearch.fromJson(Map<String, dynamic> json) {
    return ResourceSearch(
      enabled: opt<bool>(json, 'enabled') ?? false,
      placeholder: opt<String>(json, 'placeholder'),
    );
  }

  final bool enabled;
  final String? placeholder;

  @override
  List<Object?> get props => [enabled, placeholder];
}

class ResourceSort extends Equatable {
  const ResourceSort({
    required this.key,
    required this.label,
    this.direction = 'asc',
    this.isDefault = false,
  });

  factory ResourceSort.fromJson(Map<String, dynamic> json, String path) {
    return ResourceSort(
      key: req<String>(json, 'key', path),
      label: req<String>(json, 'label', path),
      direction: closedEnum(
        json['direction'],
        const {'asc', 'desc'},
        '$path.direction',
        ifAbsent: 'asc',
      ),
      isDefault: opt<bool>(json, 'default') ?? false,
    );
  }

  final String key;
  final String label;

  /// `asc` or `desc`. A closed set — anything else throws rather than sorting
  /// the list the wrong way round.
  final String direction;
  final bool isDefault;

  /// Identity only: two sorts on the same key and direction compare equal even
  /// when their [label] or [isDefault] differ. Enough to dedupe a sort menu,
  /// not enough to detect that the server changed one. Do not use it to decide
  /// whether a refreshed schema is unchanged.
  @override
  List<Object?> get props => [key, direction];
}

/// A resource's drag-to-reorder capability (P18) — present on
/// [ResourceSchema.reorder] if and only if the web panel's table declared a
/// non-pivot reorder column and authorized this user for it. See
/// `contract/README.md`'s "Reordering" section for the full server contract.
class ReorderConfig extends Equatable {
  const ReorderConfig({required this.column, required this.direction});

  /// Parses `json['reorder']` leniently, unlike [object]/[req]: a malformed
  /// value (wrong type entirely, or a map missing a string `column`) reads as
  /// "this resource cannot be reordered" rather than throwing a
  /// [SchemaFormatException] that would blank the whole resource. Dropping a
  /// mobile-only affordance is a safe degrade; refusing to parse the rest of
  /// the schema over it is not.
  static ReorderConfig? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;

    final column = value['column'];
    if (column is! String || column.isEmpty) return null;

    // Same leniency as [ResourceSort.direction]'s `closedEnum(ifAbsent:
    // 'asc')` — an unrecognised or missing direction defaults rather than
    // throwing, since the server always sends both together in practice.
    return ReorderConfig(
      column: column,
      direction: value['direction'] == 'desc' ? 'desc' : 'asc',
    );
  }

  final String column;

  /// `asc` or `desc` — see [ResourceSort.direction]'s doc for why this is a
  /// closed set rather than an arbitrary string.
  final String direction;

  @override
  List<Object?> get props => [column, direction];
}

/// One Filament resource, rendered as a list of cards plus create/edit/view
/// pages. Construct it directly for a Dart-defined override, or via
/// [ResourceSchema.fromJson] for the server-served schema — same class, same
/// renderer, one code path.
class ResourceSchema extends Equatable {
  const ResourceSchema({
    required this.key,
    required this.labels,
    this.permissions = const ResourcePermissions(),
    this.recordKey = 'id',
    this.card = const CardLayout.empty(),
    this.search = const ResourceSearch(),
    this.sorts = const [],
    this.filters = const [],
    this.form = const [],
    this.infolist = const [],
    this.relations = const [],
    this.group,
    this.badge,
    this.direction = PanelDirection.ltr,
    this.locales = const [],
    this.reorder,
  });

  /// [direction] is not read off [json] — a resource's direction always
  /// comes from its panel. It defaults to [PanelDirection.ltr] so a directly
  /// constructed resource (tests, the contract test, [ResourceSchema.fake])
  /// keeps working unchanged; [PanelSchema.fromJson] passes the panel's
  /// parsed direction into every resource it builds. [locales] follows the
  /// same rule, for the same reason: `panel.locales` is a panel-level fact,
  /// not a per-resource one, so it is propagated here rather than read off
  /// each resource's own JSON (which carries none).
  factory ResourceSchema.fromJson(
    Map<String, dynamic> json,
    String path, {
    PanelDirection direction = PanelDirection.ltr,
    List<String> locales = const [],
  }) {
    final sortNodes = objects(json, 'sorts', path);
    final rawGroup = opt<String>(json, 'group');

    return ResourceSchema(
      key: req<String>(json, 'key', path),
      labels: ResourceLabels.fromJson(
        req<Map<String, dynamic>>(json, 'labels', path),
        '$path.labels',
      ),
      // object(), not opt(): an absent sub-object takes the documented default,
      // but one that is present and not an object is a contract violation.
      // Reading it as absent would silently deny every permission, blank the
      // card, or switch search off.
      permissions: ResourcePermissions.fromJson(
        object(json, 'permissions', path) ?? const {},
      ),
      recordKey: opt<String>(json, 'recordKey') ?? 'id',
      card: CardLayout.fromJson(
        object(json, 'card', path) ?? const {},
        '$path.card',
      ),
      search: ResourceSearch.fromJson(object(json, 'search', path) ?? const {}),
      sorts: List.generate(
        sortNodes.length,
        (index) =>
            ResourceSort.fromJson(sortNodes[index], '$path.sorts[$index]'),
      ),
      filters: SchemaComponent.listFromJson(json, 'filters', path),
      form: SchemaComponent.listFromJson(json, 'form', path),
      infolist: SchemaComponent.listFromJson(json, 'infolist', path),
      // Same rule as [direction] on this resource itself: propagated at parse
      // time, not read off each relation's own JSON (which carries none).
      relations: RelationDescriptor.listFromJson(
        json,
        path,
        direction: direction,
      ),
      group: rawGroup?.isEmpty ?? false ? null : rawGroup,
      badge: switch (object(json, 'badge', path)) {
        final badge? => ResourceBadge.fromJson(badge),
        null => null,
      },
      direction: direction,
      locales: locales,
      reorder: ReorderConfig.fromJson(json['reorder']),
    );
  }

  /// Shape-only resource for skeleton loading: the UI renders this while
  /// `LoadStatus.loading`, so the skeleton matches the real card's geometry.
  factory ResourceSchema.fake() {
    return ResourceSchema(
      key: 'fake',
      labels: const ResourceLabels(singular: '—', plural: '—'),
      card: const CardLayout(
        titleField: 'title',
        subtitleField: 'subtitle',
        meta: [CardMeta(field: 'meta')],
      ),
      form: [
        SchemaComponent.fromJson(const {
          'type': 'text',
          'name': 'title',
          'label': '—',
        }, 'fake.form[0]'),
        SchemaComponent.fromJson(const {
          'type': 'text',
          'name': 'subtitle',
          'label': '—',
        }, 'fake.form[1]'),
      ],
    );
  }

  final String key;
  final ResourceLabels labels;
  final ResourcePermissions permissions;

  /// Attribute holding the record identifier — usually `id`, sometimes `uuid`.
  final String recordKey;
  final CardLayout card;
  final ResourceSearch search;
  final List<ResourceSort> sorts;
  final List<SchemaComponent> filters;
  final List<SchemaComponent> form;
  final List<SchemaComponent> infolist;
  final List<RelationDescriptor> relations;
  final String? group;

  /// The web sidebar's count badge, or null when the resource declares none
  /// — the server omits the key entirely in that case, same as [group].
  final ResourceBadge? badge;

  /// The owning panel's layout direction, propagated at parse time by
  /// [PanelSchema.fromJson]. Defaults to [PanelDirection.ltr] for a
  /// directly-constructed resource — see [ResourceSchema.fromJson].
  final PanelDirection direction;

  /// `panel.locales`, propagated at parse time by [PanelSchema.fromJson] —
  /// see [PanelSchema.locales] for the contract. Defaults to `const []` for
  /// a directly-constructed resource, same as [direction]. Used only to
  /// order a translatable group's chips; the chips themselves come from
  /// this resource's own `translatable` form fields.
  final List<String> locales;

  /// Drag-to-reorder capability (P18) — absent (`null`) on almost every
  /// resource, present only when the server's `/schema` response carried the
  /// `reorder` key for this session. `ResourceListScreen` gates its reorder
  /// toggle on this alone — see that screen's class doc for why no host hook
  /// is needed the way `onCreateTap` needs one.
  final ReorderConfig? reorder;

  ResourceSort? get defaultSort {
    for (final sort in sorts) {
      if (sort.isDefault) return sort;
    }
    return null;
  }

  /// Identity only: two resources with the same [key] and [group] compare equal
  /// even when their labels, permissions, card or form have diverged. Use it to
  /// look a resource up, never to decide whether a refreshed schema differs from
  /// a cached one — it always will not.
  @override
  List<Object?> get props => [key, group];
}

/// The web sidebar's count badge for one resource — the value is whatever
/// string the panel renders (usually a count), the colour the same semantic
/// vocabulary card badges use (`success`, `warning`, …).
class ResourceBadge extends Equatable {
  const ResourceBadge({required this.value, this.color});

  factory ResourceBadge.fromJson(Map<String, dynamic> json) {
    return ResourceBadge(
      value: json['value'] is String ? json['value'] as String : '',
      color: json['color'] is String ? json['color'] as String : null,
    );
  }

  final String value;
  final String? color;

  @override
  List<Object?> get props => [value, color];
}

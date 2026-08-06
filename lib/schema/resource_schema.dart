import 'package:equatable/equatable.dart';

import 'card_layout.dart';
import 'json_reader.dart';
import 'resource_action.dart';
import 'resource_labels.dart';
import 'schema_component.dart';

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
    this.actions = const [],
    this.group,
  });

  factory ResourceSchema.fromJson(Map<String, dynamic> json, String path) {
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
      actions: ResourceAction.listFromJson(json, 'actions', path),
      group: rawGroup?.isEmpty ?? false ? null : rawGroup,
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
  final List<ResourceAction> actions;
  final String? group;

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

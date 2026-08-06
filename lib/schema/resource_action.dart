import 'package:equatable/equatable.dart';

import 'json_reader.dart';
import 'schema_component.dart';

enum ActionScope { row, bulk, header }

/// A button the panel can offer: on one record (`row`), on a selection
/// (`bulk`), or on the list page itself (`header`).
///
/// [visible] is only meaningful for `bulk` and `header`. For `row` actions the
/// server decides per record: the detail response carries a `permissions` block
/// beside its `data` (`view`/`update`/`delete`), which is what
/// `recordCan(record, ...)` reads, so the client never renders a button the
/// server would reject.
class ResourceAction extends Equatable {
  const ResourceAction({
    required this.name,
    required this.label,
    this.icon,
    this.color,
    this.scope = ActionScope.row,
    this.destructive = false,
    this.requiresConfirmation = false,
    this.confirmation,
    this.form = const [],
    this.visible = true,
  });

  factory ResourceAction.fromJson(Map<String, dynamic> json, String path) {
    final confirmation = object(json, 'confirmation', path);

    return ResourceAction(
      name: req<String>(json, 'name', path),
      label: req<String>(json, 'label', path),
      icon: opt<String>(json, 'icon'),
      color: opt<String>(json, 'color'),
      // Closed set (§5.5), so an unrecognised value throws rather than falling
      // back: reading an unplaceable scope as `row` puts the button on every
      // single record. Absent still means `row`.
      scope: ActionScope.values.byName(
        closedEnum(
          json['scope'],
          const {'row', 'bulk', 'header'},
          '$path.scope',
          ifAbsent: 'row',
        ),
      ),
      destructive: opt<bool>(json, 'destructive') ?? false,
      requiresConfirmation: opt<bool>(json, 'requiresConfirmation') ?? false,
      confirmation: confirmation == null
          ? null
          : ActionConfirmation.fromJson(confirmation, '$path.confirmation'),
      form: SchemaComponent.listFromJson(json, 'form', path),
      visible: opt<bool>(json, 'visible') ?? true,
    );
  }

  static List<ResourceAction> listFromJson(
    Map<String, dynamic> json,
    String key,
    String path,
  ) {
    final nodes = objects(json, key, path);
    return List.generate(
      nodes.length,
      (index) => ResourceAction.fromJson(nodes[index], '$path.$key[$index]'),
    );
  }

  final String name;
  final String label;
  final String? icon;
  final String? color;
  final ActionScope scope;
  final bool destructive;
  final bool requiresConfirmation;
  final ActionConfirmation? confirmation;

  /// Rendered in a bottom sheet before the action runs.
  final List<SchemaComponent> form;
  final bool visible;

  /// Identity only: `(name, scope)` is unique within one resource's action
  /// list and nowhere else. Two actions can compare equal while differing in
  /// label, form and confirmation, and the same action name on two resources
  /// compares equal too. Enough to look one up, not enough to diff a
  /// refreshed schema against a cached one.
  @override
  List<Object?> get props => [name, scope];
}

class ActionConfirmation extends Equatable {
  const ActionConfirmation({
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  factory ActionConfirmation.fromJson(Map<String, dynamic> json, String path) {
    return ActionConfirmation(
      title: req<String>(json, 'title', path),
      body: req<String>(json, 'body', path),
      confirmLabel: req<String>(json, 'confirmLabel', path),
    );
  }

  final String title;
  final String body;
  final String confirmLabel;

  @override
  List<Object?> get props => [title, body, confirmLabel];
}

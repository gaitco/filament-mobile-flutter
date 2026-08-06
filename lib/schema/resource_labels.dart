import 'package:equatable/equatable.dart';

import 'json_reader.dart';

/// Display strings for a resource. Already localised by Laravel — the client
/// uses them verbatim.
class ResourceLabels extends Equatable {
  const ResourceLabels({
    required this.singular,
    required this.plural,
    this.icon,
  });

  factory ResourceLabels.fromJson(Map<String, dynamic> json, String path) {
    return ResourceLabels(
      singular: req<String>(json, 'singular', path),
      plural: req<String>(json, 'plural', path),
      icon: opt<String>(json, 'icon'),
    );
  }

  final String singular;
  final String plural;
  final String? icon;

  @override
  List<Object?> get props => [singular, plural, icon];
}

/// What the authenticated user may do with a resource, as decided by the
/// Laravel policies. Every flag denies by default: a missing key must never
/// read as permission.
class ResourcePermissions extends Equatable {
  const ResourcePermissions({
    this.viewAny = false,
    this.view = false,
    this.create = false,
    this.update = false,
    this.delete = false,
  });

  const ResourcePermissions.all()
    : viewAny = true,
      view = true,
      create = true,
      update = true,
      delete = true;

  factory ResourcePermissions.fromJson(Map<String, dynamic> json) {
    return ResourcePermissions(
      viewAny: opt<bool>(json, 'viewAny') ?? false,
      view: opt<bool>(json, 'view') ?? false,
      create: opt<bool>(json, 'create') ?? false,
      update: opt<bool>(json, 'update') ?? false,
      delete: opt<bool>(json, 'delete') ?? false,
    );
  }

  final bool viewAny;
  final bool view;
  final bool create;
  final bool update;
  final bool delete;

  @override
  List<Object?> get props => [viewAny, view, create, update, delete];
}

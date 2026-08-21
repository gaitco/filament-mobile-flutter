import 'package:equatable/equatable.dart';

import 'json_reader.dart';
import 'resource_schema.dart';

export 'json_reader.dart' show SchemaFormatException;
export 'resource_schema.dart' show PanelDirection;

/// Thrown when the server speaks a newer contract than this build understands.
///
/// Refusing is deliberate: a half-parsed panel is worse than an honest "update
/// the app" screen, because the missing parts are invisible.
class UnsupportedSchemaVersionException implements Exception {
  const UnsupportedSchemaVersionException({
    required this.found,
    required this.supported,
  });

  final int found;
  final int supported;

  @override
  String toString() =>
      'UnsupportedSchemaVersionException: server sent schema version $found, '
      'this build supports $supported';
}

class NavigationGroup extends Equatable {
  const NavigationGroup({required this.group, this.resources = const []});

  factory NavigationGroup.fromJson(Map<String, dynamic> json, String path) {
    final keys = opt<List<dynamic>>(json, 'resources') ?? const [];
    return NavigationGroup(
      group: req<String>(json, 'group', path),
      // Not whereType<String>(): dropping a malformed entry makes a navigation
      // item vanish with no diagnostic, which is the same silent hole as an
      // unparsed resource.
      resources: List.generate(keys.length, (index) {
        final key = keys[index];
        if (key is! String) {
          throw SchemaFormatException(
            '$path.resources[$index]',
            'expected String, got ${key.runtimeType}',
          );
        }
        return key;
      }, growable: false),
    );
  }

  final String group;

  /// Resource keys, in display order.
  final List<String> resources;

  @override
  List<Object?> get props => [group, resources];
}

/// The whole panel document. Contains only the resources the authenticated
/// user may view — the server filters, the client never decides.
class PanelSchema extends Equatable {
  const PanelSchema({
    required this.version,
    required this.id,
    required this.title,
    this.locale = '',
    this.locales = const [],
    this.direction = PanelDirection.ltr,
    this.navigation = const [],
    this.resources = const [],
  });

  factory PanelSchema.fromJson(Map<String, dynamic> json) {
    // Root-level keys have no parent, so they report `version` and `panel`
    // rather than a `panel.` prefix that does not exist in the document.
    final version = req<int>(json, 'version', '');
    if (version != supportedVersion) {
      throw UnsupportedSchemaVersionException(
        found: version,
        supported: supportedVersion,
      );
    }

    final panel = req<Map<String, dynamic>>(json, 'panel', '');
    final navigationNodes = objects(panel, 'navigation', 'panel');
    // Absent reads as ltr (a server predating this field), and so does an
    // unrecognised value — the server normalises `direction` to ltr/rtl, but
    // the client re-checks rather than trusting that it did.
    final direction = PanelDirection.fromJson(panel['direction']);
    final locales = stringList(panel, 'locales');

    // Read directly rather than through objects(): the resources array is at
    // the document root, so its children must report `resources[0]`, not
    // `.resources[0]`. Still reproduces both of objects()'s guards: the
    // list-type check below, plus an eager per-element check — .cast<T>() is
    // lazy, so a malformed element would otherwise surface later as a raw
    // TypeError with no JSON path.
    final rawResources = json['resources'];
    if (rawResources != null && rawResources is! List) {
      throw SchemaFormatException(
        'resources',
        'expected List, got ${rawResources.runtimeType}',
      );
    }
    final rawList = rawResources as List? ?? const [];
    final resourceNodes = List.generate(rawList.length, (index) {
      final element = rawList[index];
      if (element is! Map<String, dynamic>) {
        throw SchemaFormatException(
          'resources[$index]',
          'expected object, got ${element.runtimeType}',
        );
      }
      return element;
    });

    return PanelSchema(
      version: version,
      id: req<String>(panel, 'id', 'panel'),
      title: req<String>(panel, 'title', 'panel'),
      locale: opt<String>(panel, 'locale') ?? '',
      locales: locales,
      direction: direction,
      navigation: List.generate(
        navigationNodes.length,
        (index) => NavigationGroup.fromJson(
          navigationNodes[index],
          'panel.navigation[$index]',
        ),
      ),
      // One value, one source: the panel's direction (and locales) are
      // propagated into every resource here, at parse time, rather than
      // threaded through the host at render time. See PanelDirection's doc
      // comment and [ResourceSchema.locales].
      resources: List.generate(
        resourceNodes.length,
        (index) => ResourceSchema.fromJson(
          resourceNodes[index],
          'resources[$index]',
          direction: direction,
          locales: locales,
        ),
      ),
    );
  }

  /// The contract version this build understands.
  static const int supportedVersion = 1;

  final int version;
  final String id;
  final String title;

  /// `app()->getLocale()` at request time, published for a client that wants
  /// it for its own formatting. Not used by this package to decide
  /// [direction] — that is read from its own key, independently.
  final String locale;

  /// The panel's declared locales, flat and in display order — absent (or
  /// unanswerable server-side) reads as `[]`, never guessed at from a
  /// dotted field name. The client uses it only to ORDER a translatable
  /// group's chips; the chips themselves come from the form's own fields,
  /// which stay the source of truth for which locales actually exist.
  final List<String> locales;

  /// The panel's layout direction. Absent or unrecognised reads as
  /// [PanelDirection.ltr] — see [PanelDirection.fromJson].
  final PanelDirection direction;
  final List<NavigationGroup> navigation;
  final List<ResourceSchema> resources;

  ResourceSchema? resource(String key) {
    for (final resource in resources) {
      if (resource.key == key) return resource;
    }
    return null;
  }

  /// Identity only: `id` and `version` are exactly the two things that do not
  /// change when a panel's contents do, so two documents whose resources
  /// differ entirely still compare equal. Never write
  /// `if (fresh == cached) return;` after refetching `/schema` — that discards
  /// every real update.
  @override
  List<Object?> get props => [id, version];
}

import 'package:equatable/equatable.dart';

/// One record from the panel.
///
/// Records are runtime-shaped — the schema is only known at runtime — so there
/// is no generated model per resource. This is the model: a typed wrapper over
/// the decoded map, so no screen ever touches a raw `Map<String, dynamic>`.
class ResourceRecord extends Equatable {
  const ResourceRecord({
    required this.id,
    this.attributes = const {},
    this.permissions = const {},
  });

  factory ResourceRecord.fromJson(
    Map<String, dynamic> json,
    String recordKey, {
    Map<String, dynamic>? permissions,
  }) {
    final id = json[recordKey];

    if (id == null) {
      throw ArgumentError(
        'Record is missing its key `$recordKey`. The server always sends it; '
        'check the resource\'s recordKey in the panel schema.',
      );
    }

    return ResourceRecord(
      id: id as Object,
      attributes: json,
      permissions: {
        for (final entry in (permissions ?? const {}).entries)
          if (entry.value is bool) entry.key: entry.value as bool,
      },
    );
  }

  /// Shape-only record for skeleton loading, pairing with
  /// `ResourceSchema.fake()`'s card so the skeleton matches the real geometry.
  factory ResourceRecord.fake(int seed) {
    return ResourceRecord(
      id: seed,
      attributes: const {'title': '——————', 'subtitle': '————', 'meta': '———'},
    );
  }

  final Object id;
  final Map<String, dynamic> attributes;

  /// Per-record authorization, populated **only** by the record endpoint.
  ///
  /// Empty for records from the list endpoint, which does not compute it. This
  /// is NOT the same as the resource-level `permissions` on `ResourceSchema`:
  /// that one means capability ("this resource supports deletion and you are
  /// not categorically barred"), this one means authorization ("you may delete
  /// THIS record"). Under an ownership policy they disagree for most records.
  final Map<String, bool> permissions;

  /// Whether the user may perform [ability] on this specific record.
  /// Absent means denied — an unlisted ability is never assumed allowed.
  bool can(String ability) => permissions[ability] ?? false;

  /// Reads an attribute, resolving a dotted path into the nested objects the
  /// server builds from a card's relation field. A null anywhere along the
  /// path, or a type mismatch, yields null rather than throwing.
  T? get<T>(String path) {
    // A literal key first, before treating the dots as a traversal.
    //
    // The record endpoint writes FORM paths flat: a translatable field is
    // published as `caption.en` and Laravel validates it as a path, but an
    // infolist entry named `caption` is Spatie's accessor — the current
    // locale's string. They are different things sharing one base key, so the
    // server keeps them apart and the client must read them apart. Traversing
    // first would find the infolist's nested value and answer the wrong
    // question, or find nothing and blank a prefilled edit form.
    //
    // `FormValues._readPath` has had this rule since the form path was built;
    // this gives the record the same one.
    if (attributes.containsKey(path)) {
      final literal = attributes[path];

      return literal is T ? literal : null;
    }

    dynamic value = attributes;

    for (final segment in path.split('.')) {
      if (value is! Map<String, dynamic>) return null;
      value = value[segment];
      if (value == null) return null;
    }

    return value is T ? value : null;
  }

  @override
  List<Object?> get props => [id];
}

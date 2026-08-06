/// Thrown when the panel JSON does not match the contract.
///
/// [path] is a dotted JSON path (`resources[0].form[2].name`) so a contract
/// mismatch points at the exact node rather than "type error".
class SchemaFormatException implements Exception {
  const SchemaFormatException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'SchemaFormatException at $path: $message';
}

/// Reads a required [key] of type [T], throwing with the JSON path if absent
/// or of the wrong type.
///
/// `dart:convert` decodes a JSON whole number (e.g. `2`) as `int`, never
/// `double`. Read numeric fields as `num` or `int` — `T = double` will throw
/// on a valid whole-number value.
T req<T>(Map<String, dynamic> json, String key, String path) {
  final value = json[key];
  if (value is T) return value;
  throw SchemaFormatException(
    _join(path, key),
    'expected $T, got ${value.runtimeType}',
  );
}

/// Joins a parent [path] to a [key]. The document root has no parent, so it
/// passes `''` and its keys report `version`, not `.version`.
String _join(String path, String key) => path.isEmpty ? key : '$path.$key';

/// Reads an optional [key] of type [T]. A wrong type reads as absent — the
/// server is allowed to widen a field without breaking older clients.
///
/// `dart:convert` decodes a JSON whole number (e.g. `2`) as `int`, never
/// `double`. Read numeric fields as `num` or `int` — `T = double` will
/// silently read a valid whole-number value as absent.
T? opt<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is T ? value : null;
}

/// Reads an optional sub-object. Absent reads as `null`; present but not an
/// object throws.
///
/// This is deliberately stricter than [opt]. `opt`'s licence covers a *scalar*
/// widening — an older client reading a field the server changed the shape of.
/// A whole container arriving as a scalar is a server bug, and reading it as
/// absent turns it into a silently empty card or a deny-all permission set.
Map<String, dynamic>? object(
  Map<String, dynamic> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value == null) return null;
  if (value is! Map<String, dynamic>) {
    throw SchemaFormatException(
      _join(path, key),
      'expected object, got ${value.runtimeType}',
    );
  }
  return value;
}

/// Reads a closed-set string, where [path] already names the key.
///
/// An unrecognised value throws: a closed enum is not an extension point, so
/// falling back would place a control the client cannot honour (a `sidebar`
/// action read as `row` lands on every record). Absent yields [ifAbsent], or
/// throws when the contract gives no default.
String closedEnum(
  Object? value,
  Set<String> allowed,
  String path, {
  String? ifAbsent,
}) {
  if (value == null && ifAbsent != null) return ifAbsent;
  if (value is String && allowed.contains(value)) return value;
  throw SchemaFormatException(
    path,
    'expected one of ${allowed.join(', ')}; got '
    '${value is String ? '"$value"' : value.runtimeType}',
  );
}

/// Reads a list of JSON objects at [key]. Missing reads as empty; a
/// non-object element is a contract violation and throws.
List<Map<String, dynamic>> objects(
  Map<String, dynamic> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List) {
    throw SchemaFormatException(
      _join(path, key),
      'expected List, got ${value.runtimeType}',
    );
  }
  return List.generate(value.length, (index) {
    final element = value[index];
    if (element is! Map<String, dynamic>) {
      throw SchemaFormatException(
        '${_join(path, key)}[$index]',
        'expected object, got ${element.runtimeType}',
      );
    }
    return element;
  });
}

/// Reads a `{"key": "value"}` map, dropping any non-string value.
Map<String, String> stringMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  };
}

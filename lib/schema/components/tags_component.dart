part of '../schema_component.dart';

/// A `tags` field: a free-form list of strings.
///
/// The value is a `List<String>` on the wire **in every case**. [separator]
/// is published because a panel configured one — Filament stores such a
/// field as a delimited string — but the join happens server-side at write
/// time, so the client never sees or constructs the delimited form. This
/// field is carried so a renderer can say what the panel does; it is not an
/// instruction to build one.
///
/// `splitKeys`, `tagPrefix` and `tagSuffix` are deliberately not on the wire
/// (the design spec's stated known weaknesses): a tag commits on submit
/// only, and prefixes/suffixes are presentation this build does not
/// reproduce.
final class TagsComponent extends SchemaComponent {
  TagsComponent._({
    required _CommonProperties common,
    required this.separator,
    required this.suggestions,
  }) : super._common(common);

  factory TagsComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};
    return TagsComponent._(
      common: common,
      separator: opt<String>(config, 'separator'),
      // A convenience, never a rule — the server accepts any tag it
      // validates — so a malformed entry is dropped rather than failing the
      // whole field's parse, exactly as [FileComponent.accept] treats its
      // own hint list.
      suggestions:
          opt<List<dynamic>>(
            config,
            'suggestions',
          )?.whereType<String>().toList() ??
          const [],
    );
  }

  /// What the panel joins this field's tags with when it persists them.
  /// Null means the column stores a plain array. Either way the wire value
  /// is a list — see the class doc.
  final String? separator;

  /// Tags the panel offers as shortcuts. Empty means none; a client must
  /// still accept any tag the user types.
  final List<String> suggestions;
}

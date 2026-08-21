part of '../schema_component.dart';

/// A file upload field. `readOnly` defaults to `true` so an older server
/// that never publishes the key — meaning it predates upload support
/// entirely — reads as inert rather than a renderer guessing it can accept
/// one. A current server publishes `false` for a writable field, single or
/// multiple.
///
/// `multiple` defaults to `false` for the same reason in the other
/// direction: an absent key means a server predating multi-file support,
/// and a client must never invent a capability the server did not declare.
/// A current server publishes the key on every `file` node, `false` for
/// single. When true, the field's value is a `List<String>` everywhere — on
/// a record, in form state, in a write body — of stored path or media
/// uuid: an opaque string token the server round-trips.
final class FileComponent extends SchemaComponent {
  FileComponent._({
    required _CommonProperties common,
    required this.readOnly,
    required this.multiple,
    required this.accept,
    required this.maxSizeKb,
    required this.maxFiles,
    required this.minFiles,
  }) : super._common(common);

  factory FileComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};
    return FileComponent._(
      common: common,
      readOnly: opt<bool>(config, 'readOnly') ?? true,
      multiple: opt<bool>(config, 'multiple') ?? false,
      // A hint for pre-filtering/pre-warning, not a rule: the server
      // enforces regardless, so a malformed entry is dropped rather than
      // failing the whole field's parse.
      accept: opt<List<dynamic>>(
        config,
        'accept',
      )?.whereType<String>().toList(),
      maxSizeKb: opt<int>(config, 'maxSize'),
      maxFiles: opt<int>(config, 'maxFiles'),
      minFiles: opt<int>(config, 'minFiles'),
    );
  }

  final bool readOnly;

  /// Whether the field holds a list of stored paths rather than one. See
  /// the class doc for why an absent key reads as `false`.
  final bool multiple;

  /// Accepted MIME types/extensions, when the server configured one. Null
  /// means unconstrained, not "nothing accepted".
  final List<String>? accept;

  /// The field's own size limit in KB — Filament's own unit — when
  /// configured. Per file, multiple or not.
  final int? maxSizeKb;

  /// The declared count bounds, present only when the field declared them.
  /// Hints for the add affordance, never rules: the server's write-time
  /// array `max`/`min` is the enforcement.
  final int? maxFiles;
  final int? minFiles;
}

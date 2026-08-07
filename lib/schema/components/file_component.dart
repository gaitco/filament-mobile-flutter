part of '../schema_component.dart';

/// A file upload field. `readOnly` defaults to `true` so an older server
/// that never publishes the key — meaning it predates upload support
/// entirely — reads as inert rather than a renderer guessing it can accept
/// one. A current server publishes `false` for a single-file field and
/// `true` for multiple, which this build still cannot upload.
final class FileComponent extends SchemaComponent {
  FileComponent._({
    required _CommonProperties common,
    required this.readOnly,
    required this.accept,
    required this.maxSizeKb,
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
      // A hint for pre-filtering/pre-warning, not a rule: the server
      // enforces regardless, so a malformed entry is dropped rather than
      // failing the whole field's parse.
      accept: opt<List<dynamic>>(
        config,
        'accept',
      )?.whereType<String>().toList(),
      maxSizeKb: opt<int>(config, 'maxSize'),
    );
  }

  final bool readOnly;

  /// Accepted MIME types/extensions, when the server configured one. Null
  /// means unconstrained, not "nothing accepted".
  final List<String>? accept;

  /// The field's own size limit in KB — Filament's own unit — when
  /// configured.
  final int? maxSizeKb;
}

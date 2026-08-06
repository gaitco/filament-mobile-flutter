part of '../schema_component.dart';

/// A file upload field. Upload itself is deferred to a later phase, so this
/// build never has anywhere to send bytes — `readOnly` defaults to `true` so
/// a renderer shows the field disabled instead of pretending it can accept
/// one.
final class FileComponent extends SchemaComponent {
  FileComponent._({required _CommonProperties common, required this.readOnly})
    : super._common(common);

  factory FileComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};
    return FileComponent._(
      common: common,
      readOnly: opt<bool>(config, 'readOnly') ?? true,
    );
  }

  final bool readOnly;
}

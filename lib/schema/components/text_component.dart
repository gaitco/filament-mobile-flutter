part of '../schema_component.dart';

enum TextKind { text, textarea, email, password }

/// `text`, `textarea`, `email` and `password` in one class: they differ only
/// by keyboard, obscurity and line count, all of which the renderer derives
/// from [kind].
final class TextComponent extends SchemaComponent {
  TextComponent._({
    required _CommonProperties common,
    required this.kind,
    required this.placeholder,
    required this.defaultValue,
  }) : super._common(common);

  factory TextComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
  ) {
    return TextComponent._(
      common: common,
      kind: switch (common.type) {
        'textarea' => TextKind.textarea,
        'email' => TextKind.email,
        'password' => TextKind.password,
        _ => TextKind.text,
      },
      placeholder: opt<String>(json, 'placeholder'),
      defaultValue: opt<String>(json, 'default'),
    );
  }

  final TextKind kind;
  final String? placeholder;
  final String? defaultValue;
}

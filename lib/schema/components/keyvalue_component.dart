part of '../schema_component.dart';

/// A `keyvalue` field: a free-form set of string key/value pairs.
///
/// The value is a `Map<String, String>` on the wire. [addable]/[deletable]
/// gate the Add/Remove affordances; [editableKeys]/[editableValues] gate
/// whether the key and value inputs themselves accept edits — four
/// independent gates, all defaulting to `true` to match
/// `Filament\Forms\Components\KeyValue`'s own vendor defaults (measured
/// there, not guessed).
///
/// Reordering is deliberately not on the wire (design spec): the repeater
/// publishes `reorderable` and this package's widget has never offered one,
/// and two array-valued fields must not disagree about that for no stated
/// reason.
final class KeyValueComponent extends SchemaComponent {
  KeyValueComponent._({
    required _CommonProperties common,
    required this.addable,
    required this.deletable,
    required this.editableKeys,
    required this.editableValues,
    required this.keyLabel,
    required this.valueLabel,
    required this.keyPlaceholder,
    required this.valuePlaceholder,
  }) : super._common(common);

  factory KeyValueComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = object(json, 'config', path) ?? const {};
    return KeyValueComponent._(
      common: common,
      addable: opt<bool>(config, 'addable') ?? true,
      deletable: opt<bool>(config, 'deletable') ?? true,
      editableKeys: opt<bool>(config, 'editableKeys') ?? true,
      editableValues: opt<bool>(config, 'editableValues') ?? true,
      keyLabel: opt<String>(config, 'keyLabel'),
      valueLabel: opt<String>(config, 'valueLabel'),
      keyPlaceholder: opt<String>(config, 'keyPlaceholder'),
      valuePlaceholder: opt<String>(config, 'valuePlaceholder'),
    );
  }

  /// Whether the Add-a-pair affordance is offered at all. `false` means
  /// absent, not disabled — see [KeyValueFieldWidget].
  final bool addable;

  /// Whether each row's Remove affordance is offered at all.
  final bool deletable;

  /// Whether a row's key input accepts edits. `false` means the cell renders
  /// as plain text — the input affordance is absent, not disabled — see
  /// [KeyValueFieldWidget]. The value itself always shows; only the control
  /// that would let a user change it goes away.
  final bool editableKeys;

  /// Whether a row's value input accepts edits. Same "absent input
  /// affordance" treatment as [editableKeys].
  final bool editableValues;

  final String? keyLabel;
  final String? valueLabel;
  final String? keyPlaceholder;
  final String? valuePlaceholder;
}

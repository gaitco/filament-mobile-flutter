import 'package:flutter/material.dart';

import '../schema/schema_component.dart';
import 'field_state.dart';
import 'fields/field_widgets.dart';

typedef FieldBuilder =
    Widget Function(
      BuildContext context,
      SchemaComponent component,
      FieldState state,
    );

/// The form half of rendering: one widget per writable field, given the
/// current value, a change callback, an error slot and an enabled flag as one
/// [FieldState].
///
/// [EntryRegistry] is the infolist half — it hands a builder `(context,
/// component, record)`, which has no value, no `onChanged` and no error slot
/// because an infolist entry never round-trips. A form field does, so it gets
/// its own registry rather than bolting those onto `EntryBuilder`.
class FieldRegistry {
  FieldRegistry._(this._builders);

  factory FieldRegistry.defaults() => FieldRegistry._({});

  final Map<String, FieldBuilder> _builders;

  void register(String type, FieldBuilder builder) {
    _builders[type] = builder;
  }

  Widget build(
    BuildContext context,
    SchemaComponent component,
    FieldState state,
  ) {
    final custom = _builders[component.type];
    if (custom != null) return custom(context, component, state);

    return switch (component) {
      TextComponent() => TextFieldWidget(component: component, state: state),
      NumberComponent() => NumberFieldWidget(
        component: component,
        state: state,
      ),
      SelectComponent() => SelectFieldWidget(
        component: component,
        state: state,
      ),
      BooleanComponent() => BooleanFieldWidget(
        component: component,
        state: state,
      ),
      DateComponent() => DateFieldWidget(component: component, state: state),
      FileComponent() => FileFieldWidget(component: component, state: state),
      // `registry: this`, so a host's custom field types — and its overrides
      // of built-in ones — reach inside a repeater's rows too. A row used to
      // build through a fresh `FieldRegistry.defaults()`, which meant a host
      // got its widget everywhere on the form except inside a row.
      RepeaterComponent() => RepeaterFieldWidget(
        component: component,
        state: state,
        registry: this,
      ),
      // A layout container holds no value, so no single FieldState applies to
      // it — the caller walks the tree and calls build() once per leaf field.
      // An infolist entry reaching a form screen renders nothing: P1 owns
      // infolists, and this registry owns forms.
      _ => const SizedBox.shrink(),
    };
  }

  /// The built-in leaf types this switch dispatches on, unioned with whatever
  /// a host has registered. Derived, not restated by hand: a registered
  /// custom type is picked up automatically, and there is no separate list
  /// for a contract test to drift against.
  Set<String> get renderableTypes => {..._builtInTypes, ..._builders.keys};

  static const Set<String> _builtInTypes = {
    'text',
    'textarea',
    'email',
    'password',
    'number',
    'select',
    'multiselect',
    'toggle',
    'checkbox',
    'date',
    'datetime',
    'file',
    'repeater',
  };
}

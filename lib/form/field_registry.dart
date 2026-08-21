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
      // `radio` parses onto the same SelectComponent as `select` (identical
      // config shape, see SchemaComponent.fromJson), so it is discriminated
      // by its `type` field here rather than by a class of its own — the
      // widget differs even though the model does not. Matched before the
      // bare SelectComponent() case below, which would otherwise catch it
      // too.
      SelectComponent(type: 'radio') => RadioFieldWidget(
        component: component,
        state: state,
      ),
      SelectComponent() => SelectFieldWidget(
        component: component,
        state: state,
      ),
      ToggleButtonsComponent() => ToggleButtonsFieldWidget(
        component: component,
        state: state,
      ),
      SliderComponent() => SliderFieldWidget(
        component: component,
        state: state,
      ),
      BooleanComponent() => BooleanFieldWidget(
        component: component,
        state: state,
      ),
      // `time` parses onto the same DateComponent as `date`/`datetime`, so it
      // is discriminated by its kind here — matched before the bare
      // DateComponent() case below, which would otherwise catch it and put a
      // calendar in front of a field that has no date.
      DateComponent(kind: DateKind.time) => TimeFieldWidget(
        component: component,
        state: state,
      ),
      DateComponent() => DateFieldWidget(component: component, state: state),
      ColorComponent() => ColorFieldWidget(component: component, state: state),
      FileComponent() => FileFieldWidget(
        component: component,
        state: state,
        media: state.media,
      ),
      TagsComponent() => TagsFieldWidget(component: component, state: state),
      KeyValueComponent() => KeyValueFieldWidget(
        component: component,
        state: state,
      ),
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
  /// a host has registered. The host half *is* derived — a registered custom
  /// type is picked up automatically.
  ///
  /// [_builtInTypes] is not: it is a hand-maintained mirror of the `switch`
  /// above, and it drifts. `time` fell out of it between P8 Tasks 2 and 3 and
  /// was only noticed in review. A golden-fed test now counts the types the
  /// contract emits against this set, so the next drift reds instead of
  /// shipping — but the list still has to be edited by hand when the switch
  /// gains an arm.
  Set<String> get renderableTypes => {..._builtInTypes, ..._builders.keys};

  static const Set<String> _builtInTypes = {
    'text',
    'textarea',
    'email',
    'password',
    'number',
    'select',
    'multiselect',
    'radio',
    'toggle_buttons',
    'slider',
    'toggle',
    'checkbox',
    'date',
    'datetime',
    'time',
    'color',
    'file',
    'tags',
    'keyvalue',
    'repeater',
  };
}

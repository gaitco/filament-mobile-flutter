import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/options_page.dart';
import '../../ports/filament_file_picker.dart';
import '../../ports/filament_strings.dart';

import '../../schema/schema_component.dart';
import '../field_registry.dart';
import '../field_state.dart';
import '../form_values.dart';

/// The widgets a form field is built from — one per writable contract type.
///
/// Every one of them treats `state.enabled == false` as a hard gate: the
/// underlying Material control's own `enabled`/`onChanged` is set, not just
/// its colours. A control that merely *looks* disabled while its `onChanged`
/// stays wired is how a value the server refuses reaches the payload.

/// `text`, `textarea`, `email` and `password` — one widget, keyboard and
/// obscurity driven by [TextComponent.kind].
class TextFieldWidget extends StatelessWidget {
  const TextFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final TextComponent component;
  final FieldState state;

  @override
  Widget build(BuildContext context) {
    return _TextControl(
      value: state.value as String?,
      enabled: state.enabled,
      obscureText: component.kind == TextKind.password,
      maxLines: component.kind == TextKind.textarea ? 4 : 1,
      keyboardType: component.kind == TextKind.email
          ? TextInputType.emailAddress
          : TextInputType.text,
      onChanged: state.onChanged,
      decoration: InputDecoration(
        labelText: component.label,
        hintText: component.placeholder,
        helperText: component.helperText,
        errorText: state.error,
      ),
    );
  }
}

/// `number`. Reports a parsed `num`, never the raw string — the contract's
/// numeric fields expect a number back, not text that happens to look like one.
class NumberFieldWidget extends StatelessWidget {
  const NumberFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final NumberComponent component;
  final FieldState state;

  @override
  Widget build(BuildContext context) {
    return _TextControl(
      value: state.value?.toString(),
      enabled: state.enabled,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      onChanged: (text) => state.onChanged(num.tryParse(text)),
      decoration: InputDecoration(
        labelText: component.label,
        prefixText: component.prefix,
        suffixText: component.suffix,
        helperText: component.helperText,
        errorText: state.error,
      ),
    );
  }
}

/// `select` and `multiselect`. Reports the chosen [SelectOption.value] — the
/// contract allows int values (foreign keys) with string labels, so the
/// label is display-only and must never be what's sent back.
class SelectFieldWidget extends StatelessWidget {
  const SelectFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final SelectComponent component;
  final FieldState state;

  @override
  Widget build(BuildContext context) {
    // `/schema` withheld the options, so they cannot be rendered as a dropdown
    // at all — there is nothing to put in it until the user searches. The
    // remote picker is that search.
    if (component.optionsUrl != null && state.searchOptions != null) {
      return RemoteSelectField(component: component, state: state);
    }

    if (component.multiple) return _multi(context);

    // A value the option list no longer offers is shown as no selection, never
    // handed to the dropdown: `DropdownButtonFormField` *asserts* when its
    // value matches no item, which takes down the whole form with a red
    // screen. That is not a corner case — a dependent picker (`company_id`
    // narrowed by the chosen `user_id`) shrinks its options on every `/state`
    // response, and a record being edited can hold a foreign key the query
    // modifier filters out.
    final offered = component.options.any(
      (option) => option.value == state.value,
    );

    // The open menu is a route pushed onto the Navigator, mounted ABOVE this
    // field, so it does not inherit the screen's `Directionality` on its own
    // — the same overlay class as the dialogs, sheets and pickers elsewhere
    // in this file (whole-branch review finding 1: an RTL panel inside an LTR
    // host rendered the closed field RTL and every open option list LTR).
    // `DropdownButtonFormField` has no `builder:` to override, so each item
    // carries the direction itself: `Directionality` for the label's own text
    // and an already-resolved `Alignment` for which edge it hugs, since
    // `DropdownMenuItem`'s default `AlignmentDirectional` would resolve
    // against the route's direction too.
    //
    // `Directionality.of(context)` is correct HERE — this is a
    // `StatelessWidget`'s own `build` context, genuinely below the screen's
    // wrap, not the `State`-method ancestor trap `textDirectionOf` exists for.
    final direction = Directionality.of(context);

    return DropdownButtonFormField<Object?>(
      initialValue: offered ? state.value : null,
      onChanged: state.enabled ? state.onChanged : null,
      decoration: InputDecoration(
        labelText: component.label,
        helperText: component.helperText,
        errorText: state.error,
      ),
      items: [
        for (final option in component.options)
          DropdownMenuItem(
            value: option.value,
            alignment: direction == TextDirection.rtl
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Directionality(
              textDirection: direction,
              child: Text(option.label),
            ),
          ),
      ],
    );
  }

  Widget _multi(BuildContext context) {
    final selected =
        (state.value as List<Object?>?)?.whereType<Object>().toSet() ??
        const <Object>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (component.label != null)
          Text(
            component.label!,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        for (final option in component.options)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(option.label),
            value: selected.contains(option.value),
            onChanged: state.enabled
                ? (checked) {
                    final next = Set<Object>.of(selected);
                    if (checked ?? false) {
                      next.add(option.value);
                    } else {
                      next.remove(option.value);
                    }
                    state.onChanged(next.toList());
                  }
                : null,
          ),
        if (state.error != null) _ErrorText(state.error!),
      ],
    );
  }
}

/// `toggle` and `checkbox`. Same boolean value, different control.
class BooleanFieldWidget extends StatelessWidget {
  const BooleanFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final BooleanComponent component;
  final FieldState state;

  @override
  Widget build(BuildContext context) {
    final value = state.value as bool? ?? false;
    final label = component.label == null ? null : Text(component.label!);
    // Typed `bool?` (not `bool`) so this one closure satisfies both
    // CheckboxListTile's tristate `ValueChanged<bool?>` and SwitchListTile's
    // `ValueChanged<bool>` — a function accepting the wider type is a valid
    // substitute for a caller expecting the narrower one.
    final onChanged = state.enabled
        ? (bool? v) => state.onChanged(v ?? false)
        : null;

    final control = component.kind == BooleanKind.checkbox
        ? CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: label,
            value: value,
            onChanged: onChanged,
          )
        : SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: label,
            value: value,
            onChanged: onChanged,
          );

    if (state.error == null) return control;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [control, _ErrorText(state.error!)],
    );
  }
}

/// `date` and `datetime`. Picking goes through the built-in
/// `showDatePicker`/`showTimePicker`; display goes through
/// `MaterialLocalizations`, which is locale-aware without needing `intl`.
/// The reported value is always `DateTime.toIso8601String()`.
class DateFieldWidget extends StatelessWidget {
  const DateFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final DateComponent component;
  final FieldState state;

  @override
  Widget build(BuildContext context) {
    final current = _parse(state.value);

    return _TextControl(
      value: current == null ? null : _format(context, current),
      enabled: state.enabled,
      readOnly: true,
      onTap: () => _pick(context, current),
      decoration: InputDecoration(
        labelText: component.label,
        helperText: component.helperText,
        errorText: state.error,
        suffixIcon: const Icon(Icons.calendar_today),
      ),
    );
  }

  DateTime? _parse(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  String _format(BuildContext context, DateTime value) {
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatFullDate(value);
    if (component.kind == DateKind.date) return date;
    return '$date ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
  }

  Future<void> _pick(BuildContext context, DateTime? current) async {
    // Both pickers render through the Navigator's own overlay — a route,
    // not a descendant of this field's context — so they do not inherit
    // this screen's `Directionality` on their own (review finding 2). Each
    // picker's `builder:` param exists for exactly this kind of override.
    final direction = Directionality.of(context);
    Widget wrapDirection(BuildContext _, Widget? child) =>
        Directionality(textDirection: direction, child: child!);

    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: component.minDate ?? DateTime(1900),
      lastDate: component.maxDate ?? DateTime(2100),
      builder: wrapDirection,
    );
    if (date == null || !context.mounted) return;

    if (component.kind == DateKind.date) {
      state.onChanged(date.toIso8601String());
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: current == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(current),
      builder: wrapDirection,
    );
    if (time == null) return;

    state.onChanged(
      DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).toIso8601String(),
    );
  }
}

/// `file`. Never directly typed into — [state.value] is always a stored
/// path, never free text — so the display control is permanently read-only.
/// The *choose* control is separate: a choose/replace button, shown only
/// when every one of these holds, same "hard gate" rule the file atop this
/// list documents for every other field — `state.enabled == false` disables
/// the real control, not just its colours:
///
///  - the server left this field writable (`!component.readOnly`);
///  - `state.enabled` — a `disabled()` closure or a disabled ancestor
///    container is not a file-specific concern, but it gates this control
///    the same as every other one;
///  - the host supplied a picker (`state.filePicker`).
///
/// A `readOnly: true` component shows [FilamentStrings.fileFieldReadOnly]
/// and stays inert even with a picker supplied — the server's word always
/// wins. Otherwise missing a picker shows [FilamentStrings.filePickerUnavailable]
/// instead — never a control that cannot work, the same principle
/// [FilamentStrings.chartUnavailable] follows for a missing chart renderer.
/// A merely-disabled-but-otherwise-workable field shows neither note, same
/// as every other disabled field type: it looks inert, it does not claim a
/// reason that isn't true.
class FileFieldWidget extends StatefulWidget {
  const FileFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final FileComponent component;
  final FieldState state;

  @override
  State<FileFieldWidget> createState() => _FileFieldWidgetState();
}

class _FileFieldWidgetState extends State<FileFieldWidget> {
  bool _uploading = false;

  /// Set when [widget.state.filePicker] itself throws — a permission denial
  /// is the common case for a real picker plugin, not an exotic one. Cleared
  /// at the start of every attempt, so a retry that succeeds replaces it.
  String? _pickerError;

  bool get _canChoose =>
      widget.state.enabled &&
      !widget.component.readOnly &&
      widget.state.filePicker != null &&
      widget.state.uploadFile != null;

  @override
  Widget build(BuildContext context) {
    final strings = widget.state.strings;
    final value = widget.state.value?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TextControl(
          value: value == null ? null : _basename(value),
          enabled: false,
          readOnly: true,
          decoration: InputDecoration(
            labelText: widget.component.label,
            helperText: _helperText(strings),
            errorText: widget.state.error ?? _pickerError,
            suffixIcon: const Icon(Icons.attach_file),
          ),
        ),
        if (_canChoose)
          TextButton(
            // Disabled, not merely re-guarded: `_choose` already refuses a
            // re-entrant call, but a control that still *looks* tappable
            // while an upload is in flight invites exactly the double-tap
            // this guards against.
            onPressed: _uploading ? null : _choose,
            child: Text(_uploading ? strings.uploading : strings.chooseFile),
          ),
      ],
    );
  }

  /// The server's rule always wins, then the host's capability gap; a
  /// field that is merely disabled falls through to its own `helperText`
  /// (possibly none) rather than a note claiming a reason that isn't true.
  String? _helperText(FilamentStrings strings) {
    if (widget.component.readOnly) return strings.fileFieldReadOnly;
    if (widget.state.filePicker == null) return strings.filePickerUnavailable;
    return widget.component.helperText;
  }

  Future<void> _choose() async {
    if (_uploading) return;

    // Set before the picker even runs, synchronously, so a second tap
    // landing before this frame rebuilds still sees it and bails out above —
    // the button's own `onPressed: null` is the second, framework-level
    // guard, not the only one.
    setState(() {
      _uploading = true;
      _pickerError = null;
    });
    try {
      final PickedFile? picked;
      try {
        picked = await widget.state.filePicker!(widget.component);
      } catch (e) {
        // Degrade, never crash — the same rule
        // `ResourceFormProvider.searchOptions()` follows for a host-driven
        // async failure, adapted to actually tell the user something: unlike
        // a search there is no cached result to fall back to showing.
        if (mounted) {
          setState(() => _pickerError = widget.state.strings.uploadFailed);
        }
        return;
      }
      if (picked == null) return;

      await widget.state.uploadFile!(
        bytes: picked.bytes,
        filename: picked.filename,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _basename(String path) {
    final index = path.lastIndexOf('/');
    return index == -1 ? path : path.substring(index + 1);
  }
}

/// `repeater`. One card per row, built by walking [RepeaterComponent.children]
/// — the item **template**, published once and walked once per row in the
/// value, never re-parsed per row.
///
/// Row values live in the form state as a genuine `List<Map>` under this
/// field's own name. Editing a child field in one row replaces only that
/// row's map inside a freshly-built list — every other row's map is the same
/// object it was before — so a flat-state bug that lets two rows share one
/// value cannot hide here: row 1 changing would mean row 1's map itself
/// changed, and it never does from an edit inside row 2.
///
/// `component.readOnly` (the server's own rule) or `state.enabled == false`
/// (a host or closure-driven gate) renders every row inert with no Add or
/// Remove control — the same "server's word wins" rule [FileFieldWidget]
/// follows for a picker the host did supply.
///
/// Per-row errors reuse the form's existing flat error map rather than a new
/// channel: `client_validator.dart` keys a required child empty in row 2 as
/// `'<name>.1.<child>'`, the same shape a server `422` uses for
/// `items.0.name`, and this widget reads it out of [FieldState.errors] —
/// never a generic message for the whole field.
///
/// Nested repeaters are out of scope: a repeater inside a repeater's
/// template renders through this same widget recursively, and the walker
/// publishes a nested one `readOnly: true` — so there is no special case
/// here beyond honouring that flag like any other. (Until P6c's close-out
/// nothing published it: a nested repeater arrived editable, and its 422
/// came back keyed `outer.0.inner.1.x`, which this widget has no field to
/// render against — a form that could not be submitted and could not say
/// why. The server publishes the flag now; this docblock describes what
/// ships.)
///
/// [registry] is the host's own — the same registry that built this widget —
/// so a host-registered field type, or a host override of a built-in one,
/// renders inside a row exactly as it does everywhere else on the form.
/// Null falls back to the defaults, for a caller constructing this widget
/// directly rather than through [FieldRegistry.build].
class RepeaterFieldWidget extends StatelessWidget {
  const RepeaterFieldWidget({
    required this.component,
    required this.state,
    this.registry,
    super.key,
  });

  final RepeaterComponent component;
  final FieldState state;
  final FieldRegistry? registry;

  bool get _inert => component.readOnly || !state.enabled;

  @override
  Widget build(BuildContext context) {
    final strings = state.strings;
    final raw = state.value;
    final rows = raw is List
        ? raw.whereType<Map>().map(Map<String, Object?>.from).toList()
        : <Map<String, Object?>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (component.label != null)
          Text(
            component.label!,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        if (component.readOnly)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              strings.repeaterReadOnly,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (var index = 0; index < rows.length; index++)
          _row(context, rows, index),
        if (component.addable && !_inert && !_atCap(rows.length))
          TextButton.icon(
            key: const ValueKey('repeater.add'),
            onPressed: () =>
                state.onChanged([...rows, _defaultRow(component.children)]),
            icon: const Icon(Icons.add),
            label: Text(strings.addItem),
          ),
        if (state.error != null) _ErrorText(state.error!),
      ],
    );
  }

  bool _atCap(int count) =>
      component.maxItems != null && count >= component.maxItems!;

  bool _atFloor(int count) =>
      component.minItems != null && count <= component.minItems!;

  Widget _row(
    BuildContext context,
    List<Map<String, Object?>> rows,
    int index,
  ) {
    final row = rows[index];

    return Card(
      key: ValueKey('repeater.${component.name}.row.$index'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final child in _rowFields(component.children))
              _childField(context, rows, index, row, child),
            if (component.deletable && !_inert && !_atFloor(rows.length))
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: ValueKey('repeater.remove.$index'),
                  onPressed: () {
                    final next = List<Map<String, Object?>>.of(rows)
                      ..removeAt(index);
                    state.onChanged(next);
                  },
                  icon: const Icon(Icons.remove_circle_outline),
                  label: Text(state.strings.removeItem),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _childField(
    BuildContext context,
    List<Map<String, Object?>> rows,
    int index,
    Map<String, Object?> row,
    SchemaComponent child,
  ) {
    final name = child.name!;
    final childState = FieldState(
      value: row[name],
      onChanged: (value) {
        final nextRow = Map<String, Object?>.of(row)..[name] = value;
        final next = List<Map<String, Object?>>.of(rows)..[index] = nextRow;
        state.onChanged(next);
      },
      // This child's OWN key only. The whole [FieldState.errors] map is
      // deliberately not forwarded: the only widget that reads it is this
      // one, for a nested repeater, and a nested repeater is inert — its
      // keys are `outer.0.inner.1.x` and this widget would look them up as
      // `inner.1.x`, so forwarding would hand a child a map it cannot key
      // into. Every editable child shape gets its error through `error`.
      error: state.errors['${component.name}.$index.$name'],
      enabled: !_inert && !child.disabled && child.writable,
      strings: state.strings,
    );

    return Padding(
      key: ValueKey('repeater.${component.name}.$index.$name'),
      padding: const EdgeInsets.only(bottom: 8),
      child: (registry ?? FieldRegistry.defaults()).build(
        context,
        child,
        childState,
      ),
    );
  }
}

/// The named leaf fields reachable from one row of a repeater's item
/// template — the same "container gates its whole subtree, only `hidden`
/// removes a control outright" recursion [ResourceFormScreen] uses for the
/// top-level form, so a template can nest a `Section`/`Grid` exactly as the
/// top level can, per the wire shape's own doc: "the same shape layout
/// components already use". Unlike `writableFields()` this does not gate on
/// `disabled`/`writable` — a disabled child still renders, inert, same as
/// any other field; only [FieldState.enabled] (via `_childField`) decides
/// that, not what reaches the screen at all.
/// A new row's starting values — the item template's own `default`s, seeded
/// through the exact same [FormValues.initial] every other field's initial
/// value goes through, not a second, hand-rolled notion of "default".
/// Without this an added row rendered empty while `_validateRows`
/// (`client_validator.dart`) judged it against these same defaults through
/// that same call — so a required child with a `default` showed no error on
/// an empty-looking row, and the empty row, not the default, is what shipped.
/// Seeding here makes what renders, what validates and what submits the one
/// same row.
Map<String, Object?> _defaultRow(List<SchemaComponent> children) {
  final seeded = FormValues.initial(children);
  return {
    for (final field in _rowFields(children)) field.name!: seeded[field.name!],
  };
}

Iterable<SchemaComponent> _rowFields(List<SchemaComponent> children) sync* {
  for (final child in children) {
    if (child.hidden) continue;
    switch (child) {
      case LayoutComponent(:final children):
        yield* _rowFields(children);
      case UnknownComponent(:final children):
        yield* _rowFields(children);
      default:
        if (child.name != null) yield child;
    }
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// The one text-entry control every text-like field shares: a plain
/// [TextField] (never [TextFormField] — nothing here needs a [Form]
/// ancestor) with a controller kept in sync with an externally-owned value.
///
/// [enabled] gates `onChanged` and `onTap` to `null` outright, not merely to
/// no-op closures — so a disabled field is inert even if some future caller
/// forgets to check `enabled` before wiring a callback in.
class _TextControl extends StatefulWidget {
  const _TextControl({
    required this.value,
    required this.enabled,
    this.onChanged,
    this.onTap,
    this.decoration,
    this.obscureText = false,
    this.maxLines = 1,
    this.keyboardType,
    this.readOnly = false,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final InputDecoration? decoration;
  final bool obscureText;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool readOnly;

  @override
  State<_TextControl> createState() => _TextControlState();
}

class _TextControlState extends State<_TextControl> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value ?? '',
  );

  @override
  void didUpdateWidget(covariant _TextControl old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != _controller.text) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      onTap: widget.enabled ? widget.onTap : null,
      onChanged: widget.enabled ? widget.onChanged : null,
      decoration: widget.decoration,
    );
  }
}

/// A select whose options `/schema` refused to inline.
///
/// Renders the stored value as text until a search returns something — blanking
/// it would discard what the record actually holds behind a working-looking
/// screen, which is the failure shape this project has closed repeatedly. The
/// user taps to open a search sheet and the results come from the server.
class RemoteSelectField extends StatelessWidget {
  const RemoteSelectField({
    required this.component,
    required this.state,
    super.key,
  });

  final SelectComponent component;
  final FieldState state;

  @override
  Widget build(BuildContext context) {
    // The value is shown even when no fetched option matches it: on an edit
    // form the stored foreign key arrives before any search has run, and the
    // user must see what the record holds.
    final shown = state.value == null ? null : '${state.value}';

    return InkWell(
      onTap: state.enabled ? () => _open(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: component.label,
          helperText: component.helperText,
          errorText: state.error,
          enabled: state.enabled,
          suffixIcon: const Icon(Icons.search),
        ),
        child: Text(shown ?? ''),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    // Same overlay issue as the date/time pickers above — captured before
    // the sheet opens since its own `builder` context does not inherit this
    // field's `Directionality` (review finding 2).
    final direction = Directionality.of(context);

    final picked = await showModalBottomSheet<SelectOption>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Directionality(
        textDirection: direction,
        child: _RemoteSearchSheet(
          label: component.label,
          search: state.searchOptions!,
        ),
      ),
    );

    if (picked != null) state.onChanged(picked.value);
  }
}

class _RemoteSearchSheet extends StatefulWidget {
  const _RemoteSearchSheet({required this.label, required this.search});

  final String? label;
  final Future<OptionsPage> Function(String query) search;

  @override
  State<_RemoteSearchSheet> createState() => _RemoteSearchSheetState();
}

class _RemoteSearchSheetState extends State<_RemoteSearchSheet> {
  OptionsPage _page = const OptionsPage.empty();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // An empty query on open, so the sheet is not blank before the user types.
    _run('');
  }

  @override
  void dispose() {
    // A timer firing after disposal calls setState on a dead element.
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(query));
  }

  Future<void> _run(String query) async {
    final page = await widget.search(query);

    if (!mounted) return;

    setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const ValueKey('options.search'),
                autofocus: true,
                decoration: InputDecoration(labelText: widget.label),
                onChanged: _onChanged,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in _page.options)
                    ListTile(
                      key: ValueKey('options.item.${option.value}'),
                      title: Text(option.label),
                      onTap: () => Navigator.of(context).pop(option),
                    ),
                  // Says the list was cut short rather than implying it ended —
                  // a user who cannot find their record otherwise concludes it
                  // does not exist.
                  if (_page.hasMore)
                    const ListTile(
                      key: ValueKey('options.hasMore'),
                      dense: true,
                      title: Text('Keep typing to narrow the list'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

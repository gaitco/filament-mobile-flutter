import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/options_page.dart';

import '../../schema/schema_component.dart';
import '../field_state.dart';

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
          DropdownMenuItem(value: option.value, child: Text(option.label)),
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
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: component.minDate ?? DateTime(1900),
      lastDate: component.maxDate ?? DateTime(2100),
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

/// `file`. Upload itself is deferred to a later phase (see
/// [FileComponent]'s doc), so this control is always inert regardless of
/// `state.enabled` — there is nowhere for a picked file to go yet.
class FileFieldWidget extends StatelessWidget {
  const FileFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final FileComponent component;
  final FieldState state;

  @override
  Widget build(BuildContext context) {
    return _TextControl(
      value: state.value?.toString(),
      // Forced regardless of state.enabled — upload has nowhere to go yet.
      // `_TextControl` is the single place that turns `enabled: false` into a
      // genuinely null `onChanged`, so this widget hands it the real
      // callback rather than pre-nulling it itself.
      enabled: false,
      onChanged: state.onChanged,
      decoration: InputDecoration(
        labelText: component.label,
        helperText: component.helperText,
        errorText: state.error,
        suffixIcon: const Icon(Icons.attach_file),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
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
    final picked = await showModalBottomSheet<SelectOption>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RemoteSearchSheet(
        label: component.label,
        search: state.searchOptions!,
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

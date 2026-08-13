import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// `radio`. Same [SelectComponent] `select` parses onto — Radio shares
/// Select's config shape server-side — but rendered as every option stacked
/// and visible at once, never behind a dropdown tap: the design spec's
/// stated reason a phone renders a Radio as itself rather than folding it
/// into `SelectFieldWidget`.
///
/// `RadioGroup` is the non-deprecated way to drive a group of radios since
/// Flutter 3.32 — `RadioListTile.groupValue`/`.onChanged` are the deprecated
/// per-tile pair `SelectFieldWidget._multi` has no equivalent of, because a
/// `CheckboxListTile` has no group at all.
class RadioFieldWidget extends StatelessWidget {
  const RadioFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final SelectComponent component;
  final FieldState state;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<Object?>(
      groupValue: state.value,
      onChanged: state.onChanged,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (component.label != null)
            Text(
              component.label!,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          for (final option in component.options)
            RadioListTile<Object?>(
              contentPadding: EdgeInsets.zero,
              value: option.value,
              title: Text(option.label),
              // The hard gate, same rule this whole file states up top: a
              // control that merely looks disabled while its selection stays
              // live is how a value the server refused reaches the payload.
              // `enabled: false` — not just a null onChanged — is what makes
              // this tile itself refuse the tap, independent of the group's
              // own onChanged above.
              enabled: state.enabled,
            ),
          if (state.error != null) _ErrorText(state.error!),
        ],
      ),
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
    // `alwaysUse24HourFormat` is not read from MediaQuery by
    // `formatTimeOfDay` itself — omitting it shows a 24-hour user "2:05 PM".
    // Same call, same fix, as TimeFieldWidget's.
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$date $time';
  }

  Future<void> _pick(BuildContext context, DateTime? current) async {
    // Both pickers render through the Navigator's own overlay — a route,
    // not a descendant of this field's context — so they do not inherit
    // this screen's `Directionality` on their own (review finding 2). Each
    // picker's `builder:` param exists for exactly this kind of override.
    final direction = Directionality.of(context);
    Widget wrapDirection(BuildContext _, Widget? child) =>
        Directionality(textDirection: direction, child: child!);

    // `showDatePicker` asserts that `initialDate` lies inside
    // `[firstDate, lastDate]`, and it compares the three **date-only** — so
    // the clamp happens in that same frame, or a timezone straddling midnight
    // could still trip an assert this code had apparently handled.
    //
    // Latent until P8 Task 1: with no bounds published, firstDate/lastDate
    // fell back to 1900/2100 and `now()` was always inside them. Publishing
    // real bounds made every ordinary exclude-today idiom — a booking field's
    // `->minDate(now()->addDay())`, an age check's `->maxDate(now()->subYears(18))`
    // — crash on the first tap. Same hazard, same fix, as TimeFieldWidget's.
    var first = DateUtils.dateOnly(component.minDate ?? DateTime(1900));
    var last = DateUtils.dateOnly(component.maxDate ?? DateTime(2100));
    if (last.isBefore(first)) {
      // `showDatePicker` asserts on this pair too, so contradictory bounds
      // would crash whatever the initial date is. Reading them as no bounds
      // at all is the rule the parser already applies to a bound it cannot
      // read: a wrong limit is a nuisance, a crashed form is an outage — and
      // a client must not be crashable by what a server sends.
      first = DateTime(1900);
      last = DateTime(2100);
    }

    final initial = DateUtils.dateOnly(current ?? DateTime.now());

    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
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

/// `time`. Flutter's own `showTimePicker`, so no dependency — but it offers
/// neither bounds nor seconds, so both are handled here:
///
///  - **Bounds clamp the pick.** The dial cannot be restricted, so a time
///    outside `[minDate, maxDate]` is pulled to the nearest bound the moment
///    it is chosen, and the field shows the clamped value immediately. The
///    alternative is storing a value the server refuses, and bounds are
///    published as hints, not as validation rules — nothing else would catch
///    it.
///  - **Seconds decide the wire format**, not the picker: `showTimePicker`
///    cannot pick seconds at all, so a `seconds: true` field reports
///    `HH:mm:ss`. That matches TimePicker's own `H:i:s` format, which is what
///    the server parses. Stored seconds are **kept** when the user leaves the
///    hour and minute alone — opening the picker and pressing OK must not
///    quietly rewrite `14:05:30` to `14:05:00`.
///
/// The reported value is `HH:mm` (or `HH:mm:ss`) — never
/// `DateTime.toIso8601String()`, which would invent a date the panel never
/// chose.
class TimeFieldWidget extends StatelessWidget {
  const TimeFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final DateComponent component;
  final FieldState state;

  @override
  Widget build(BuildContext context) {
    final current = _parse(state.value);

    final field = _TextControl(
      value: current == null ? null : _format(context, _timeOf(current)),
      enabled: state.enabled,
      readOnly: true,
      onTap: () => _pick(context, current),
      decoration: InputDecoration(
        labelText: component.label,
        helperText: _helperText(context),
        errorText: state.error,
        suffixIcon: const Icon(Icons.access_time),
      ),
    );

    // The server declared a bound this build could not read, so the picker
    // will offer times the server rejects. Debug-only, like the unrenderable
    // entry placeholder: a developer meets it on the first run, a user never
    // does. Silence here would make a deleted bound indistinguishable from a
    // bound that was never set.
    if (!kDebugMode || component.unreadableBounds.isEmpty) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        Text('⚠︎ unreadable ${component.unreadableBounds.join(', ')}'),
      ],
    );
  }

  /// Through the parser that read the bounds, so a stored `"14:05:00"` and a
  /// declared `"09:00"` cannot be read two different ways. Kept as a
  /// [DateTime] rather than narrowed to a [TimeOfDay] straight away, because
  /// `TimeOfDay` has no seconds and the stored ones must survive a no-op edit.
  DateTime? _parse(Object? value) =>
      value is String ? DateComponent.parseTime(value) : null;

  static TimeOfDay _timeOf(DateTime value) =>
      TimeOfDay(hour: value.hour, minute: value.minute);

  /// `formatTimeOfDay` does not consult MediaQuery on its own — it defaults to
  /// 12-hour and leaves the caller to pass the device setting, which is easy
  /// to miss and shows a 24-hour user "2:05 PM".
  String _format(BuildContext context, TimeOfDay value) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        value,
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  /// The panel's own helper text wins; a bounded field with none gets the
  /// range instead, so the clamp below is an explained correction rather than
  /// a silent one. Same fall-through shape as `FileFieldWidget._helperText`.
  String? _helperText(BuildContext context) {
    if (component.helperText != null) return component.helperText;
    if (component.minDate == null && component.maxDate == null) return null;

    String? bound(DateTime? value) =>
        value == null ? null : _format(context, _timeOf(value));

    return state.strings.timeFieldRange(
      bound(component.minDate),
      bound(component.maxDate),
    );
  }

  Future<void> _pick(BuildContext context, DateTime? current) async {
    // Same reason DateFieldWidget wraps its pickers: the dialog is a route
    // above this field, not a descendant, so it does not inherit the panel's
    // Directionality on its own.
    final direction = Directionality.of(context);

    final time = await showTimePicker(
      context: context,
      // Clamped too — opening on a time the field would immediately move is a
      // worse first impression than opening on the nearest allowed one.
      initialTime: _clamp(current == null ? TimeOfDay.now() : _timeOf(current)),
      builder: (_, child) =>
          Directionality(textDirection: direction, child: child!),
    );
    if (time == null) return;

    final picked = _clamp(time);

    // `showTimePicker` has no seconds concept, so emitting a flat `:00` would
    // rewrite a stored `14:05:30` to `14:05:00` on nothing more than opening
    // the picker and pressing OK — data loss on a no-op interaction, with
    // nothing to signal it. The seconds already there are kept when the user
    // left the hour and minute alone; a genuinely new time starts at zero,
    // because there is nothing else it could honestly be.
    final unchanged =
        current != null &&
        picked.hour == current.hour &&
        picked.minute == current.minute;

    state.onChanged(
      [
        picked.hour,
        picked.minute,
        if (component.seconds) unchanged ? current.second : 0,
      ].map((part) => part.toString().padLeft(2, '0')).join(':'),
    );
  }

  TimeOfDay _clamp(TimeOfDay time) {
    final minutes = time.hour * 60 + time.minute;
    final min = _boundMinutes(component.minDate);
    final max = _boundMinutes(component.maxDate);

    if (min != null && minutes < min) return _fromMinutes(min);
    if (max != null && minutes > max) return _fromMinutes(max);
    return time;
  }

  int? _boundMinutes(DateTime? bound) =>
      bound == null ? null : bound.hour * 60 + bound.minute;

  TimeOfDay _fromMinutes(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

/// `color`. A text field holding the value in the format the panel declared
/// ([ColorComponent.format]), with a live swatch beside it — chosen over a
/// graphical picker, deliberately: a hand-rolled HSV widget's colour maths is
/// easy to get subtly wrong and hard to test (P8 design doc).
///
/// **Never converts between formats.** The text field's [onChanged] reports
/// exactly what the user typed, unmodified — an `rgb` field's stored value
/// stays `rgb`, byte for byte, where the user did not edit it. The swatch is
/// display-only: it is built FROM the text to show a colour, never fed back
/// INTO it.
///
/// **A malformed value never blanks the swatch.** [ColorComponent.match]
/// (through [_swatchColor]) is re-run on every keystroke; a match updates
/// [_swatch], a non-match leaves it exactly as it was — so the swatch always
/// shows the last colour the field genuinely held, which is more useful than
/// blanking on every char of an in-progress edit. The raw text still reaches
/// [FieldState.onChanged] either way: submission is blocked by
/// `client_validator.dart` reading the same [ColorComponent.isValid] this
/// widget's swatch decision is built on, not by this widget withholding the
/// value.
class ColorFieldWidget extends StatefulWidget {
  const ColorFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final ColorComponent component;
  final FieldState state;

  @override
  State<ColorFieldWidget> createState() => _ColorFieldWidgetState();
}

class _ColorFieldWidgetState extends State<ColorFieldWidget> {
  late final TextEditingController _controller = TextEditingController(
    text: _text(widget.state.value),
  );
  Color? _swatch;

  static String _text(Object? value) => value is String ? value : '';

  @override
  void initState() {
    super.initState();
    _swatch = _swatchColor(_controller.text);
  }

  @override
  void didUpdateWidget(covariant ColorFieldWidget old) {
    super.didUpdateWidget(old);
    final text = _text(widget.state.value);
    if (widget.state.value != old.state.value && text != _controller.text) {
      _controller.text = text;
      _swatch = _swatchColor(text) ?? _swatch;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Builds a display [Color] from [raw] read as [ColorComponent.format], or
  /// null when [ColorComponent.match] finds no match. Component values are
  /// clamped into a renderable range (`rgb(999, 0, 0)` matches Filament's own
  /// validation pattern, see [ColorComponent._patterns]) — display-only
  /// forgiveness that never changes what "malformed" means for validation,
  /// since that question is answered by the match alone.
  Color? _swatchColor(String raw) {
    final match = ColorComponent.match(raw, widget.component.format);
    if (match == null) return null;

    switch (widget.component.format) {
      case ColorFormat.hex:
        var hex = match[1]!;
        if (hex.length == 3) {
          hex = hex.split('').map((c) => '$c$c').join();
        }
        return Color(int.parse('FF$hex', radix: 16));
      case ColorFormat.rgb:
        return _rgba(match, 1);
      case ColorFormat.rgba:
        return _rgba(match, double.parse(match[4]!).clamp(0, 1));
      case ColorFormat.hsl:
        // Flutter's own HSL→RGB conversion, not a hand-rolled one — the
        // exact "reach for an existing implementation" the design doc's
        // reasoning against a hand-rolled HSV *picker* argues for.
        return HSLColor.fromAHSL(
          1,
          double.parse(match[1]!).clamp(0, 360),
          double.parse(match[2]!).clamp(0, 100) / 100,
          double.parse(match[3]!).clamp(0, 100) / 100,
        ).toColor();
    }
  }

  Color _rgba(RegExpMatch match, double alpha) => Color.fromRGBO(
    int.parse(match[1]!).clamp(0, 255),
    int.parse(match[2]!).clamp(0, 255),
    int.parse(match[3]!).clamp(0, 255),
    alpha,
  );

  void _onChanged(String text) {
    final parsed = _swatchColor(text);
    setState(() => _swatch = parsed ?? _swatch);
    widget.state.onChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.state.enabled;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('color.input'),
            controller: _controller,
            enabled: enabled,
            onChanged: enabled ? _onChanged : null,
            decoration: InputDecoration(
              labelText: widget.component.label,
              helperText: widget.component.helperText,
              errorText: widget.state.error,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            key: const ValueKey('color.swatch'),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _swatch,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
          ),
        ),
      ],
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

/// `tags`. Chips for the tags already chosen, each with its own remove
/// affordance, plus one text field that commits a tag on submit.
///
/// The value in form state is a genuine `List<String>` under this field's
/// own name — never the delimited string a separator-configured panel
/// persists. [TagsComponent.separator] is published so a renderer can say
/// what the panel does; the join happens server-side at write time, so this
/// widget neither builds nor parses one.
///
/// Removal is by INDEX into a freshly-built list, not by value: removing tag
/// 2 rebuilds the list without position 1 and leaves the other two entries
/// the same objects they were. A flat-state bug shows up here as the wrong
/// tag vanishing, which is exactly what the three-tag test asserts against.
///
/// [TagsComponent.suggestions] are offered as tap-to-add chips, and only the
/// ones not already chosen: a suggestion that re-adds a tag the field
/// already carries is a control that does nothing. A field with no
/// suggestions offers none rather than an empty row.
///
/// `state.enabled == false` is the same hard gate every field in this file
/// applies: no remove affordance, no suggestion chips, and the text field's
/// own `enabled` is false — a control that merely looks inert while its
/// `onSubmitted` stays wired is how a value the server refuses reaches the
/// payload.
///
/// ponytail: a per-TAG `422` (`labels.1`, from a
/// `->nestedRecursiveRules(['max:20'])`) is two segments, and
/// `ResourceFormProvider._applyServerErrors` maps only exact names and the
/// repeater's three-segment shape — so it lands on the form banner, carrying
/// the field's own label, rather than on the offending chip. Visible and
/// attributable, never silent. Upgrade path when a chip needs to carry it:
/// a two-segment branch there gated on the tags fields on screen, plus a
/// `state.errors['$name.$index']` lookup here.
class TagsFieldWidget extends StatefulWidget {
  const TagsFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final TagsComponent component;
  final FieldState state;

  @override
  State<TagsFieldWidget> createState() => _TagsFieldWidgetState();
}

class _TagsFieldWidgetState extends State<TagsFieldWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Whatever the server or a previous edit left in state, read defensively:
  /// a `null` (never edited, no default) and a non-string element both read
  /// as "no tag there" rather than throwing on a form the user can see.
  List<String> get _tags {
    final raw = widget.state.value;
    return raw is List ? raw.whereType<String>().toList() : const <String>[];
  }

  void _add(String raw) {
    final tag = raw.trim();
    _controller.clear();
    // Blank and duplicate both add nothing: a duplicate would render two
    // identical chips whose remove affordances a user cannot tell apart,
    // and the panel's own tags input dedupes the same way.
    if (tag.isEmpty || _tags.contains(tag)) return;
    widget.state.onChanged([..._tags, tag]);
  }

  void _removeAt(int index) {
    widget.state.onChanged(List<String>.of(_tags)..removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final tags = _tags;
    final enabled = widget.state.enabled;
    final name = widget.component.name;
    final unchosen = widget.component.suggestions.where(
      (suggestion) => !tags.contains(suggestion),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.component.label != null)
          Text(
            widget.component.label!,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        if (tags.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (var index = 0; index < tags.length; index++)
                Chip(
                  key: ValueKey('tags.$name.chip.$index'),
                  label: Text(tags[index]),
                  // Null, not a disabled-looking callback: `Chip` renders no
                  // delete affordance at all without one, which is what
                  // "absent, not disabled" means for this control.
                  onDeleted: enabled ? () => _removeAt(index) : null,
                  deleteButtonTooltipMessage: widget.state.strings.removeItem,
                  deleteIcon: Icon(
                    Icons.close,
                    key: ValueKey('tags.$name.remove.$index'),
                    size: 18,
                  ),
                ),
            ],
          ),
        TextField(
          controller: _controller,
          enabled: enabled,
          onSubmitted: enabled ? _add : null,
          decoration: InputDecoration(
            hintText: widget.state.strings.tagHint,
            helperText: widget.component.helperText,
          ),
        ),
        if (enabled && unchosen.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final suggestion in unchosen)
                ActionChip(
                  key: ValueKey('tags.$name.suggest.$suggestion'),
                  label: Text(suggestion),
                  onPressed: () => _add(suggestion),
                ),
            ],
          ),
        if (widget.state.error != null) _ErrorText(widget.state.error!),
      ],
    );
  }
}

/// `keyvalue`. One row per pair, each a key cell and a value cell side by
/// side.
///
/// **Row identity is independent of the key string** (fix round 1, Finding
/// 2). The wire value is a `Map<String, String>`, which cannot itself hold
/// two rows sharing a key — but a user typing a new key routes through every
/// intermediate value on the way to a final one, and two rows sharing a key
/// (or the blank key a second Add produces) is a completely ordinary,
/// recoverable mid-edit state, not data loss. So [_pairs] is **State**, seeded
/// once from [FieldState.value] and mutated in place by [_commit] — not
/// re-derived from the map on every build, the way the old Stateless version
/// did. [_isOwnEcho] is what makes this safe: after a commit, [FieldState]
/// round-trips the same (possibly collapsed) map back down through
/// `didUpdateWidget`, and that echo must not stomp `_pairs` back to the
/// collapsed shape — only a *genuinely external* change (a fresh record
/// loaded, a `/state` refresh) does. Without this a second tap of Add did
/// nothing (the second blank key collided with the first on the very next
/// build) and renaming one row's key to another's silently deleted a row
/// while the user was still typing.
///
/// **Absent, not disabled** (design spec, and fix round 1 Finding 1): the Add
/// control renders only when [KeyValueComponent.addable], a row's Remove
/// control only when [KeyValueComponent.deletable], and — now — a row's key
/// or value cell renders as plain, unfocusable [Text] rather than a
/// [_TextControl] when [KeyValueComponent.editableKeys] /
/// [KeyValueComponent.editableValues] is false. The value itself is never
/// absent (the row still has to show what it holds, which is why vendor's
/// own view disables rather than removes its `<input>`) — it is the INPUT
/// AFFORDANCE that goes away, the same distinction Add and Remove already
/// draw.
///
/// `reorderable` is deliberately not read at all — it is not on the wire
/// (design spec): the repeater publishes it and this widget has never
/// offered one.
class KeyValueFieldWidget extends StatefulWidget {
  const KeyValueFieldWidget({
    required this.component,
    required this.state,
    super.key,
  });

  final KeyValueComponent component;
  final FieldState state;

  @override
  State<KeyValueFieldWidget> createState() => _KeyValueFieldWidgetState();
}

class _KeyValueFieldWidgetState extends State<KeyValueFieldWidget> {
  late List<MapEntry<String, String>> _pairs = _fromValue(widget.state.value);

  /// Whatever the server or a previous edit left in state, read
  /// defensively: a `null` (never edited, no default) and a non-string
  /// value both read as an empty pair rather than throwing on a form the
  /// user can see — the same defensive posture [TagsFieldWidget] takes for
  /// its own list.
  static List<MapEntry<String, String>> _fromValue(Object? raw) {
    if (raw is! Map) return const [];
    return raw.entries
        .map((e) => MapEntry(e.key.toString(), e.value?.toString() ?? ''))
        .toList();
  }

  static Map<String, String> _asMap(List<MapEntry<String, String>> pairs) => {
    for (final pair in pairs) pair.key: pair.value,
  };

  @override
  void didUpdateWidget(covariant KeyValueFieldWidget old) {
    super.didUpdateWidget(old);
    if (widget.state.value != old.state.value &&
        !_isOwnEcho(widget.state.value)) {
      _pairs = _fromValue(widget.state.value);
    }
  }

  /// True when [value] is exactly what [_commit] most recently reported
  /// outward for the CURRENT `_pairs` — i.e. this update is our own edit
  /// echoed back through [FieldState], not a change from anywhere else. A
  /// duplicate or blank key collapses `_asMap(_pairs)` to fewer entries than
  /// `_pairs` has rows, so this compares map content, not row count: two
  /// rows sharing a key legitimately produce a shorter map than the row
  /// list, and that must still read as "our own echo", not as an external
  /// change to resync from.
  bool _isOwnEcho(Object? value) {
    if (value is! Map) return false;
    final committed = _asMap(_pairs);
    if (value.length != committed.length) return false;
    for (final entry in committed.entries) {
      if (value[entry.key]?.toString() != entry.value) return false;
    }
    return true;
  }

  void _commit(List<MapEntry<String, String>> next) {
    setState(() => _pairs = next);
    widget.state.onChanged(_asMap(next));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.state.enabled;
    final name = widget.component.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.component.label != null)
          Text(
            widget.component.label!,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        for (var index = 0; index < _pairs.length; index++)
          _row(context, index),
        if (widget.component.addable && enabled)
          TextButton.icon(
            key: ValueKey('keyvalue.$name.add'),
            onPressed: () => _commit([..._pairs, const MapEntry('', '')]),
            icon: const Icon(Icons.add),
            label: Text(widget.state.strings.addItem),
          ),
        if (widget.state.error != null) _ErrorText(widget.state.error!),
      ],
    );
  }

  Widget _row(BuildContext context, int index) {
    final name = widget.component.name;
    final enabled = widget.state.enabled;
    final pair = _pairs[index];

    return Padding(
      key: ValueKey('keyvalue.$name.row.$index'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('keyvalue.$name.key.$index'),
              child: widget.component.editableKeys
                  ? _TextControl(
                      value: pair.key,
                      enabled: enabled,
                      decoration: InputDecoration(
                        labelText: widget.component.keyLabel,
                        hintText: widget.component.keyPlaceholder,
                      ),
                      onChanged: (value) {
                        final next = List<MapEntry<String, String>>.of(_pairs);
                        next[index] = MapEntry(value, pair.value);
                        _commit(next);
                      },
                    )
                  : Text(pair.key),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('keyvalue.$name.value.$index'),
              child: widget.component.editableValues
                  ? _TextControl(
                      value: pair.value,
                      enabled: enabled,
                      decoration: InputDecoration(
                        labelText: widget.component.valueLabel,
                        hintText: widget.component.valuePlaceholder,
                      ),
                      onChanged: (value) {
                        final next = List<MapEntry<String, String>>.of(_pairs);
                        next[index] = MapEntry(pair.key, value);
                        _commit(next);
                      },
                    )
                  : Text(pair.value),
            ),
          ),
          if (widget.component.deletable && enabled)
            IconButton(
              key: ValueKey('keyvalue.$name.remove.$index'),
              tooltip: widget.state.strings.removeItem,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () {
                final next = List<MapEntry<String, String>>.of(_pairs)
                  ..removeAt(index);
                _commit(next);
              },
            ),
        ],
      ),
    );
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
      // A remote select inside a row gets the same lookup a top-level one
      // does, bound to the CHILD's own name — `state.searchOptions` is a
      // closure already bound to the repeater's name, so the unbound
      // per-field variant is the only one a row can use. Without this the
      // row's select rendered an empty dropdown that never said why (ledger
      // L18). The server resolves the field by bare name; whether its own
      // lookup descends into a repeater is the server's half of the story.
      searchOptions: state.searchOptionsFor == null
          ? null
          : (query) => state.searchOptionsFor!(name, query),
      // Forwarded for the same reason it exists: a deeper container (a
      // host-built one, or a nested repeater) must not lose the path again.
      searchOptionsFor: state.searchOptionsFor,
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

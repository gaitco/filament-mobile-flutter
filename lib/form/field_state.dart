import 'package:flutter/foundation.dart';

import '../data/options_page.dart';
import '../ports/filament_file_picker.dart';
import '../ports/filament_strings.dart';

/// Everything one form field widget needs to render itself, handed down by a
/// form provider so the widget never reaches into [FormValues] or the schema
/// directly.
class FieldState {
  const FieldState({
    required this.value,
    required this.onChanged,
    this.error,
    this.errors = const {},
    this.enabled = true,
    this.searchOptions,
    this.searchOptionsFor,
    this.filePicker,
    this.uploadFile,
    this.strings = const FilamentStrings(),
  });

  final Object? value;
  final ValueChanged<Object?> onChanged;
  final String? error;

  /// The form's whole error map, keyed the way `client_validator.dart` and a
  /// server `422` both key it: `'<name>'` for a flat field, and
  /// `'<name>.<row>.<child>'` for a row nested inside a repeater. [error]
  /// above is this field's own entry, already looked up for convenience —
  /// every non-repeater widget ignores [errors] entirely, the same as
  /// [filePicker] and [uploadFile] are file-only. Only `RepeaterFieldWidget`
  /// reads it, to put a row's own error on that row instead of folding it
  /// into one message for the whole field.
  final Map<String, String> errors;

  final bool enabled;

  /// Fetches this field's options for a query, when `/schema` published an
  /// `optionsUrl` instead of inlining them.
  ///
  /// Optional so a host that registers its own field builder is unaffected,
  /// and so every non-select field ignores it. Null means the options are
  /// already on the component.
  final Future<OptionsPage> Function(String query)? searchOptions;

  /// The per-field variant of [searchOptions], for the one caller that
  /// cannot use it: a **container** field whose children each need a lookup
  /// bound to the CHILD's own name. [searchOptions] is a closure already
  /// bound to the field it was built for, and a closure cannot be rebound —
  /// handing a repeater's [searchOptions] to a row's select would query the
  /// repeater's own name, which the options endpoint rightly refuses. A
  /// container (today only `RepeaterFieldWidget`) calls this with the child's
  /// name instead; leaf fields keep reading [searchOptions], and a form that
  /// never nests a remote select inside a repeater can ignore this entirely.
  final Future<OptionsPage> Function(String field, String query)?
  searchOptionsFor;

  /// Picks a file for a `FileComponent`; null when the host gave
  /// `ResourceFormScreen` no picker, which is `FileFieldWidget`'s signal to
  /// stay inert rather than render a control it cannot drive. Every other
  /// field type ignores it, the same as [searchOptions].
  final FilamentFilePicker? filePicker;

  /// Uploads bytes for the field this state belongs to and applies the
  /// outcome — value on success, error on failure — through the owning
  /// provider. `FileFieldWidget` only ever calls this after [filePicker]
  /// itself returned non-null, so a caller that never sets [filePicker] has
  /// no reason to set this either; see `ResourceFormScreen._field()`.
  final Future<void> Function({
    required List<int> bytes,
    required String filename,
  })?
  uploadFile;

  /// Labels for `FileFieldWidget`'s choose control, in-flight state and
  /// unavailable note. Defaulted, not optional, like every other host-facing
  /// string in this package — every non-file field ignores it.
  final FilamentStrings strings;
}

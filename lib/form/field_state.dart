import 'package:flutter/foundation.dart';

import '../data/options_page.dart';

/// Everything one form field widget needs to render itself, handed down by a
/// form provider so the widget never reaches into [FormValues] or the schema
/// directly.
class FieldState {
  const FieldState({
    required this.value,
    required this.onChanged,
    this.error,
    this.enabled = true,
    this.searchOptions,
  });

  final Object? value;
  final ValueChanged<Object?> onChanged;
  final String? error;
  final bool enabled;

  /// Fetches this field's options for a query, when `/schema` published an
  /// `optionsUrl` instead of inlining them.
  ///
  /// Optional so a host that registers its own field builder is unaffected,
  /// and so every non-select field ignores it. Null means the options are
  /// already on the component.
  final Future<OptionsPage> Function(String query)? searchOptions;
}

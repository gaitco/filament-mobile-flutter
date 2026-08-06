import 'package:equatable/equatable.dart';

/// One action the server published for a record — a button the user may
/// press, already filtered to what this record may run.
///
/// Absence is the contract: an action the user may not run for this record
/// is not in the list. There is no `enabled` flag to render greyed out,
/// deliberately — the same rule `permissions` follows.
class RecordAction extends Equatable {
  const RecordAction({
    required this.name,
    required this.label,
    this.color,
    this.icon,
    this.confirmation,
  });

  /// Null when the payload names no action — the one field the client
  /// cannot do without, since it is what the run endpoint is keyed on.
  ///
  /// A throwing label/color/icon on the server degrades to the action's
  /// name and nulls, not a dropped action — see the wire-contract note on
  /// [RecordAction]. Parsing mirrors that: [label] falls back to [name]
  /// rather than the entry being skipped.
  static RecordAction? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;

    final confirmation = json['confirmation'];

    return RecordAction(
      name: name,
      label: json['label'] is String ? json['label'] as String : name,
      color: json['color'] is String ? json['color'] as String : null,
      icon: json['icon'] is String ? json['icon'] as String : null,
      confirmation: confirmation is Map<String, dynamic>
          ? RecordActionConfirmation.fromJson(confirmation)
          : null,
    );
  }

  final String name;
  final String label;

  /// A semantic colour name (`success`, `danger`, …) — the same vocabulary
  /// card badges use. Null means "no opinion, use the theme's default".
  final String? color;

  /// The panel's own icon name, unnormalised. A client that recognises it
  /// may render it; one that does not renders a label-only button.
  final String? icon;

  /// Non-null means the user must confirm before the action runs, in the
  /// action's own words.
  final RecordActionConfirmation? confirmation;

  @override
  List<Object?> get props => [name];
}

/// The action's own confirmation copy — translated by the server, so the
/// client never composes this sentence itself.
///
/// The server fails closed: a confirmation whose evaluation throws is still
/// emitted non-null, with a generic heading and empty `submit`/`cancel`. A
/// client must therefore never read an empty `submit`/`cancel` as "no
/// confirmation" — this type being non-null IS the confirmation; empty
/// strings are the caller's cue to substitute its own button text, not to
/// skip the prompt.
class RecordActionConfirmation extends Equatable {
  const RecordActionConfirmation({
    required this.heading,
    required this.submit,
    required this.cancel,
    this.description,
  });

  factory RecordActionConfirmation.fromJson(Map<String, dynamic> json) {
    return RecordActionConfirmation(
      heading: json['heading'] is String ? json['heading'] as String : '',
      description: json['description'] is String
          ? json['description'] as String
          : null,
      submit: json['submit'] is String ? json['submit'] as String : '',
      cancel: json['cancel'] is String ? json['cancel'] as String : '',
    );
  }

  final String heading;
  final String? description;
  final String submit;
  final String cancel;

  @override
  List<Object?> get props => [heading, description, submit, cancel];
}

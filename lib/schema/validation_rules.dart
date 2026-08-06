import 'package:equatable/equatable.dart';

import 'json_reader.dart';

/// Client-side hints for immediate feedback only. The server revalidates
/// every submission, so anything not expressible here is simply omitted
/// rather than approximated.
class ValidationRules extends Equatable {
  const ValidationRules({
    this.required = false,
    this.min,
    this.max,
    this.email = false,
    this.url = false,
    this.regex,
    this.confirmed = false,
    this.numeric = false,
    this.messages = const {},
  });

  const ValidationRules.none()
    : required = false,
      min = null,
      max = null,
      email = false,
      url = false,
      regex = null,
      confirmed = false,
      numeric = false,
      messages = const {};

  factory ValidationRules.fromJson(Map<String, dynamic> json) {
    return ValidationRules(
      required: opt<bool>(json, 'required') ?? false,
      min: opt<num>(json, 'min'),
      max: opt<num>(json, 'max'),
      email: opt<bool>(json, 'email') ?? false,
      url: opt<bool>(json, 'url') ?? false,
      regex: opt<String>(json, 'regex'),
      confirmed: opt<bool>(json, 'confirmed') ?? false,
      numeric: opt<bool>(json, 'numeric') ?? false,
      messages: stringMap(json, 'messages'),
    );
  }

  final bool required;

  /// Numeric bound for `number`, character length for text kinds.
  final num? min;
  final num? max;
  final bool email;
  final bool url;
  final String? regex;
  final bool confirmed;

  /// Whether Laravel will treat this field's bounds as VALUES rather than
  /// lengths. Published as a rule, not inferred from the node's `type`:
  /// `->email()->numeric()` renders as an email input and validates
  /// numerically, and the two answers are independent.
  final bool numeric;

  /// Per-rule messages in the panel's locale, produced by the same translator
  /// the server's 422 uses. Empty when the server sends none, in which case
  /// the client falls back to its own [FilamentStrings].
  final Map<String, String> messages;

  @override
  List<Object?> get props => [
    required,
    min,
    max,
    email,
    url,
    regex,
    confirmed,
    numeric,
    messages,
  ];
}

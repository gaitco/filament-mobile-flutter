part of '../schema_component.dart';

enum PhoneFormat { e164, international, national, rfc3966 }

/// A phone value remains a string end to end. Formatting and validation stay
/// server-side so the client never rewrites a number the panel stored.
final class PhoneComponent extends SchemaComponent {
  PhoneComponent._({
    required _CommonProperties common,
    required this.placeholder,
    required this.defaultValue,
    required this.format,
    required this.countryPath,
    required this.defaultCountry,
    required this.onlyCountries,
    required this.excludeCountries,
  }) : super._common(common);

  factory PhoneComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
  ) {
    final config = opt<Map<String, dynamic>>(json, 'config') ?? const {};

    return PhoneComponent._(
      common: common,
      placeholder: opt<String>(json, 'placeholder'),
      defaultValue: opt<String>(json, 'default'),
      format: switch (config['format']) {
        'international' => PhoneFormat.international,
        'national' => PhoneFormat.national,
        'rfc3966' => PhoneFormat.rfc3966,
        _ => PhoneFormat.e164,
      },
      countryPath: config['countryPath'] is String
          ? config['countryPath'] as String
          : null,
      defaultCountry: config['defaultCountry'] is String
          ? config['defaultCountry'] as String
          : null,
      onlyCountries: _phoneCountries(config['onlyCountries']),
      excludeCountries: _phoneCountries(config['excludeCountries']),
    );
  }

  final String? placeholder;
  final String? defaultValue;
  final PhoneFormat format;
  final String? countryPath;
  final String? defaultCountry;
  final List<String> onlyCountries;
  final List<String> excludeCountries;
}

List<String> _phoneCountries(Object? value) =>
    value is List ? List.unmodifiable(value.whereType<String>()) : const [];

import 'package:equatable/equatable.dart';

import 'json_reader.dart';

/// How one record renders as a list card — the mobile answer to Filament's
/// data table. Laravel derives a default from the table columns; a resource
/// may override any slot. Every slot is optional: a card with only a title is
/// a valid list tile.
class CardLayout extends Equatable {
  const CardLayout({
    this.titleField,
    this.subtitleField,
    this.leading,
    this.badges = const [],
    this.meta = const [],
  });

  const CardLayout.empty()
    : titleField = null,
      subtitleField = null,
      leading = null,
      badges = const [],
      meta = const [];

  factory CardLayout.fromJson(Map<String, dynamic> json, String path) {
    final badgeNodes = objects(json, 'badges', path);
    final metaNodes = objects(json, 'meta', path);
    final leading = object(json, 'leading', path);

    return CardLayout(
      titleField: _slotField(json, 'title', path),
      subtitleField: _slotField(json, 'subtitle', path),
      leading: leading == null
          ? null
          : CardLeading.fromJson(leading, '$path.leading'),
      badges: List.generate(
        badgeNodes.length,
        (index) =>
            CardBadge.fromJson(badgeNodes[index], '$path.badges[$index]'),
      ),
      meta: List.generate(
        metaNodes.length,
        (index) => CardMeta.fromJson(metaNodes[index], '$path.meta[$index]'),
      ),
    );
  }

  /// `title` and `subtitle` are objects in the contract so they can grow
  /// later; today only `field` is read.
  ///
  /// An absent slot is fine — every slot is optional. A slot that is *present*
  /// but carries no `field` is a contract violation and throws, exactly like a
  /// badge without a field: the server declared the slot and then failed to
  /// fill it, and a card that silently renders no title is a bug that survives
  /// to production. Contract evolution is handled by the version gate, not by
  /// reading malformed slots as null.
  static String? _slotField(
    Map<String, dynamic> json,
    String key,
    String path,
  ) {
    final slot = object(json, key, path);
    return slot == null ? null : req<String>(slot, 'field', '$path.$key');
  }

  final String? titleField;
  final String? subtitleField;
  final CardLeading? leading;
  final List<CardBadge> badges;
  final List<CardMeta> meta;

  @override
  List<Object?> get props => [titleField, subtitleField, leading, badges, meta];
}

class CardLeading extends Equatable {
  const CardLeading({required this.type, required this.field, this.fallback});

  factory CardLeading.fromJson(Map<String, dynamic> json, String path) {
    return CardLeading(
      // Closed set: an unrecognised leading kind has no sensible rendering, so
      // it throws rather than guessing at one.
      type: closedEnum(json['type'], const {'image', 'icon'}, '$path.type'),
      field: req<String>(json, 'field', path),
      fallback: opt<String>(json, 'fallback'),
    );
  }

  /// `image` or `icon`.
  final String type;
  final String field;

  /// What to show when the field is empty, e.g. `initials`.
  final String? fallback;

  @override
  List<Object?> get props => [type, field, fallback];
}

class CardBadge extends Equatable {
  const CardBadge({required this.field, this.colors = const {}});

  factory CardBadge.fromJson(Map<String, dynamic> json, String path) {
    return CardBadge(
      field: req<String>(json, 'field', path),
      colors: stringMap(json, 'colors'),
    );
  }

  final String field;

  /// Value → semantic colour name (`success`, `danger`, …).
  final Map<String, String> colors;

  @override
  List<Object?> get props => [field, colors];
}

class CardMeta extends Equatable {
  const CardMeta({required this.field, this.format});

  factory CardMeta.fromJson(Map<String, dynamic> json, String path) {
    return CardMeta(
      field: req<String>(json, 'field', path),
      format: opt<String>(json, 'format'),
    );
  }

  final String field;
  final String? format;

  @override
  List<Object?> get props => [field, format];
}

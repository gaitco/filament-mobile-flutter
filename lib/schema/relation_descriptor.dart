import 'package:equatable/equatable.dart';

import 'card_layout.dart';
import 'json_reader.dart';
import 'resource_schema.dart' show PanelDirection;

/// One relation manager published for a resource: a related list of records
/// rendered as cards, e.g. a banner's tags. Absent from the contract entirely
/// on a server predating P6d — that reads as no relations, not an error.
class RelationDescriptor extends Equatable {
  const RelationDescriptor({
    required this.key,
    required this.label,
    required this.card,
    this.recordKey = 'id',
    this.direction = PanelDirection.ltr,
  });

  /// [direction] is not read off [json] — same rule as [ResourceSchema.direction]:
  /// a relation always inherits its owning resource's direction, propagated by
  /// [ResourceSchema.fromJson] through [listFromJson] below, one level deeper
  /// than [PanelSchema.fromJson] propagates it into the resource itself.
  factory RelationDescriptor.fromJson(
    Map<String, dynamic> json,
    String path, {
    PanelDirection direction = PanelDirection.ltr,
  }) {
    // Required fields first, so a relation missing both its key and its card
    // is still reported as the missing key it is.
    final key = req<String>(json, 'key', path);
    final label = req<String>(json, 'label', path);

    final card = CardLayout.fromJson(
      object(json, 'card', path) ?? const {},
      '$path.card',
    );

    // A card with no slot at all renders zero widgets, so the section would
    // be a heading over nothing — the "disabled corpse" this contract does
    // not publish. Every other missing required field already drops the
    // relation; an absent, null or `{}` card used to be the one that did
    // not, and [listFromJson]'s own doc has always claimed otherwise. The
    // server refuses to publish one (`RelationDiscovery` names it in
    // `doctor`), and this is the client half of the same rule: a wire shape
    // nothing can render is a malformed relation, not a blank one.
    if (card == const CardLayout.empty()) {
      throw SchemaFormatException(
        '$path.card',
        'declares no slot, so the relation would render nothing',
      );
    }

    return RelationDescriptor(
      key: key,
      label: label,
      card: card,
      // Absent on an older server that predates this field — 'id' is the
      // same default `ResourceSchema.recordKey` takes, and the common case.
      recordKey: opt<String>(json, 'recordKey') ?? 'id',
      direction: direction,
    );
  }

  /// Parses `relations` one entry at a time, matching
  /// `RepeaterComponent._templateFrom`: a single malformed relation — missing
  /// `key`/`label`, a card that is bad or fills no slot, or not even an
  /// object — is dropped rather than failing the whole resource. `relations`
  /// itself absent reads as no relations (an older server predating P6d);
  /// present but not a list is a genuine contract violation and throws.
  static List<RelationDescriptor> listFromJson(
    Map<String, dynamic> json,
    String path, {
    PanelDirection direction = PanelDirection.ltr,
  }) {
    final raw = json['relations'];
    if (raw == null) return const [];
    if (raw is! List) {
      throw SchemaFormatException(
        '$path.relations',
        'expected List, got ${raw.runtimeType}',
      );
    }

    final relations = <RelationDescriptor>[];
    for (var index = 0; index < raw.length; index++) {
      final node = raw[index];
      if (node is! Map<String, dynamic>) continue;
      try {
        relations.add(
          RelationDescriptor.fromJson(
            node,
            '$path.relations[$index]',
            direction: direction,
          ),
        );
      } on SchemaFormatException {
        continue;
      }
    }
    return relations;
  }

  final String key;
  final String label;
  final CardLayout card;

  /// The CHILD record's own identifier attribute — usually `id`, sometimes a
  /// slug or a uuid. Mirrors `ResourceSchema.recordKey`, but for the related
  /// model on the far end of this relation, which is routinely a different
  /// class with a different key.
  final String recordKey;

  /// The owning resource's layout direction, propagated at parse time by
  /// [ResourceSchema.fromJson] — see [RelationDescriptor.fromJson]. Defaults
  /// to [PanelDirection.ltr] for a directly-constructed relation (tests, and
  /// callers building one by hand).
  final PanelDirection direction;

  @override
  List<Object?> get props => [key];
}

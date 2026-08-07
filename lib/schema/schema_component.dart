import 'package:equatable/equatable.dart';

import 'json_reader.dart';
import 'validation_rules.dart';

export 'json_reader.dart' show SchemaFormatException;

part 'components/text_component.dart';
part 'components/number_component.dart';
part 'components/select_component.dart';
part 'components/boolean_component.dart';
part 'components/date_component.dart';
part 'components/file_component.dart';
part 'components/repeater_component.dart';
part 'components/layout_component.dart';
part 'components/entry_component.dart';

/// One node of a Filament schema tree.
///
/// Form fields, infolist entries, filters and layout containers are all the
/// same node type — this mirrors Filament 5, where they all descend from
/// `Schema\Component`. One tree, one parser, one renderer dispatch.
///
/// The hierarchy deliberately has far fewer classes than the contract has
/// `type` values: near-identical types collapse onto one class carrying a
/// `kind` enum. See the type map in the P0 plan.
sealed class SchemaComponent extends Equatable {
  const SchemaComponent({
    required this.type,
    this.name,
    this.label,
    this.helperText,
    this.columnSpan = 12,
    this.hidden = false,
    this.disabled = false,
    this.writable = true,
    this.live = false,
    this.rules = const ValidationRules.none(),
  });

  /// Builds directly from an already-parsed [_CommonProperties], so each
  /// subclass's JSON constructor doesn't have to re-list all 9 fields.
  SchemaComponent._common(_CommonProperties common)
    : type = common.type,
      name = common.name,
      label = common.label,
      helperText = common.helperText,
      columnSpan = common.columnSpan,
      hidden = common.hidden,
      disabled = common.disabled,
      writable = common.writable,
      live = common.live,
      rules = common.rules;

  /// The raw contract discriminator, kept so an [UnknownComponent] can name
  /// itself and so debug output matches the JSON.
  final String type;

  /// Field key. Null for layout containers, which hold no value.
  final String? name;
  final String? label;
  final String? helperText;

  /// Out of 12, matching Filament. A phone renderer treats anything >= 6 as
  /// full width; the value is carried so a tablet renderer can use it later.
  final int columnSpan;

  final bool hidden;
  final bool disabled;

  /// False only when the server marks a field it cannot persist — distinct
  /// from [disabled], which is a UI decision the user may be able to change
  /// elsewhere. Absent in the contract means `true`: most fields are
  /// writable, and the key exists to name the exception, not the rule.
  final bool writable;

  /// When true, a change to this field triggers a `/state` round-trip so the
  /// server can re-evaluate the schema.
  final bool live;

  /// Client-side validation hints. A base-node property in the contract (§5.3),
  /// so every consumer can ask "is this required?" without switching over the
  /// sealed hierarchy. Containers and entries simply carry
  /// [ValidationRules.none].
  final ValidationRules rules;

  /// Deepest nesting this parser will follow. Recursion past it dies with a
  /// `StackOverflowError` — an `Error`, not an `Exception`, so no
  /// repository-level `catch (Exception)` would ever see it. Real Filament
  /// forms nest a handful of levels.
  static const int maxDepth = 32;

  static SchemaComponent fromJson(
    Map<String, dynamic> json,
    String path, [
    int depth = 0,
  ]) {
    if (depth > maxDepth) {
      throw SchemaFormatException(
        path,
        'schema is nested too deeply — more than $maxDepth levels',
      );
    }

    final type = req<String>(json, 'type', path);
    final common = _CommonProperties.fromJson(json, type);

    return switch (type) {
      'text' ||
      'textarea' ||
      'email' ||
      'password' => TextComponent._fromJson(json, common),
      'number' => NumberComponent._fromJson(json, common, path),
      'select' ||
      'multiselect' => SelectComponent._fromJson(json, common, path),
      'toggle' || 'checkbox' => BooleanComponent._fromJson(json, common),
      'date' || 'datetime' => DateComponent._fromJson(json, common, path),
      'file' => FileComponent._fromJson(json, common, path),
      'repeater' => RepeaterComponent._fromJson(json, common, path, depth),
      'section' ||
      'grid' ||
      'tabs' ||
      'fieldset' => LayoutComponent._fromJson(json, common, path, depth),
      'text_entry' ||
      'badge_entry' ||
      'image_entry' ||
      'boolean_entry' ||
      'date_entry' ||
      'rich_entry' => EntryComponent._fromJson(json, common, path),
      _ => UnknownComponent._fromJson(json, common, path, depth),
    };
  }

  static List<SchemaComponent> listFromJson(
    Map<String, dynamic> json,
    String key,
    String path, [
    int depth = 0,
  ]) {
    final nodes = objects(json, key, path);
    return List.generate(
      nodes.length,
      (index) =>
          SchemaComponent.fromJson(nodes[index], '$path.$key[$index]', depth),
    );
  }

  /// Equality is `(type, name, writable)` — meaningful only within a single
  /// container. `name` is a field key that's unique within one form or
  /// infolist, not globally, so two components from different resources, or
  /// from a form vs its infolist, can compare equal here while differing in
  /// every other property. Do not put components from different containers
  /// into the same `Set` or diff them against each other on this equality.
  /// `writable` is included: a `/state` round-trip can flip it on a field
  /// whose type and name are otherwise unchanged, and a rebuild that depends
  /// on that difference needs the equality to see it.
  @override
  List<Object?> get props => [type, name, writable];
}

/// The properties every node shares, parsed once so each subclass constructor
/// stays a one-liner.
class _CommonProperties {
  const _CommonProperties({
    required this.type,
    required this.name,
    required this.label,
    required this.helperText,
    required this.columnSpan,
    required this.hidden,
    required this.disabled,
    required this.writable,
    required this.live,
    required this.rules,
  });

  factory _CommonProperties.fromJson(Map<String, dynamic> json, String type) {
    return _CommonProperties(
      type: type,
      name: opt<String>(json, 'name'),
      label: opt<String>(json, 'label'),
      helperText: opt<String>(json, 'helperText'),
      // Clamped, not rejected: a bad span misplaces one field, and P2 maps it
      // onto a Flutter grid where 0 or a negative is an assertion failure far
      // from the JSON that caused it. Killing the screen would be worse.
      columnSpan: (opt<int>(json, 'columnSpan') ?? 12).clamp(1, 12),
      hidden: opt<bool>(json, 'hidden') ?? false,
      disabled: opt<bool>(json, 'disabled') ?? false,
      writable: opt<bool>(json, 'writable') ?? true,
      live: opt<bool>(json, 'live') ?? false,
      rules: ValidationRules.fromJson(
        opt<Map<String, dynamic>>(json, 'rules') ?? const {},
      ),
    );
  }

  final String type;
  final String? name;
  final String? label;
  final String? helperText;
  final int columnSpan;
  final bool hidden;
  final bool disabled;
  final bool writable;
  final bool live;
  final ValidationRules rules;
}

/// A component type this build does not know how to render.
///
/// Degrading is deliberate: a server that adds one new field type must not be
/// able to blank an entire screen on an older client. The UI layer renders a
/// visible placeholder in debug and skips it in release.
final class UnknownComponent extends SchemaComponent {
  UnknownComponent._(super.common, {required this.children}) : super._common();

  factory UnknownComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
    int depth,
  ) {
    return UnknownComponent._(
      common,
      children: SchemaComponent.listFromJson(json, 'children', path, depth + 1),
    );
  }

  /// Filament 5 ships container types this build does not know (`wizard`,
  /// `split`, `actions`, `flex`). Parsing their children anyway keeps every
  /// nested field reachable — an unknown *container* that dropped its children
  /// would silently delete a whole branch of the form, which is the blanked
  /// screen this class exists to prevent. Empty for an unknown leaf field.
  final List<SchemaComponent> children;
}

import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden_transport.dart';

final fixture = GoldenTransport.panelJson;

/// Walks every node reachable from a resource's form — descending into a
/// `LayoutComponent`'s or `UnknownComponent`'s children so a field nested
/// under a section is visited too, not only its top-level siblings.
void visitForm(ResourceSchema resource, void Function(SchemaComponent) visit) {
  void walk(List<SchemaComponent> components) {
    for (final component in components) {
      visit(component);
      if (component is LayoutComponent) walk(component.children);
      if (component is UnknownComponent) walk(component.children);
    }
  }

  walk(resource.form);
}

void main() {
  test('the client data source parses real Laravel output', () async {
    final panel = await RestResourceDataSource(
      transport: GoldenTransport(),
    ).panel();

    expect(panel.version, 1);
    expect(panel.resources, isNotEmpty);
  });

  test('every resource in the real output has a usable card', () async {
    final panel = await RestResourceDataSource(
      transport: GoldenTransport(),
    ).panel();

    for (final resource in panel.resources) {
      expect(
        resource.recordKey,
        isNotEmpty,
        reason: '${resource.key} has no record key',
      );
      expect(
        resource.labels.plural,
        isNotEmpty,
        reason: '${resource.key} has no plural label',
      );
    }
  });

  test('no component in the real output is unknown to this build', () async {
    // This is the assertion that would have caught `icon_entry`: the Laravel
    // side emitted a type this parser had no case for, so every IconEntry
    // silently degraded. Snapshot tests on the server could not see it.
    //
    // `rich_entry` used to be excluded here by exact name: P6e Task 2 added
    // it to the Laravel walker ahead of the Dart parser and renderer, so it
    // genuinely degraded through UnknownComponent until Task 5 shipped both.
    // Now that they exist, the exclusion is gone — this test catches every
    // OTHER unhandled type again, with `rich_entry` counted like any other.
    final panel = await RestResourceDataSource(
      transport: GoldenTransport(),
    ).panel();

    final unknown = <String>[];

    void walk(List<SchemaComponent> components) {
      for (final component in components) {
        if (component is UnknownComponent) {
          unknown.add(component.type);
        }
        if (component is LayoutComponent) walk(component.children);
      }
    }

    for (final resource in panel.resources) {
      walk(resource.form);
      walk(resource.infolist);
      walk(resource.filters);
    }

    expect(unknown, isEmpty, reason: 'unrenderable types: ${unknown.toSet()}');
  });

  test('every form type in the fixture has a field widget', () async {
    // Derived from the registry, not restated as a list. P2-Laravel found its
    // own coverage assertion was a hand-maintained `toContain` subset that no
    // new type could ever fail; this must not repeat that.
    final panel = await RestResourceDataSource(
      transport: GoldenTransport(),
    ).panel();

    final renderable = FieldRegistry.defaults().renderableTypes;
    final missing = <String>{};

    for (final resource in panel.resources) {
      visitForm(resource, (component) {
        if (component is! LayoutComponent &&
            component is! UnknownComponent &&
            !renderable.contains(component.type)) {
          missing.add(component.type);
        }
      });
    }

    expect(missing, isEmpty, reason: 'unrenderable form types: $missing');
  });

  test('an ordinary repeater in the real output renders editable', () async {
    // The cross-package assertion the repeater slice was missing: both sides
    // were internally consistent and jointly wrong. The walker published
    // `config.readOnly` only for a RELATIONSHIP repeater, and this parser
    // reads an absent key as read-only (deliberately — an absent key means a
    // server predating repeater support, which must not be guessed editable).
    // So every ordinary repeater from this package's own server rendered
    // permanently inert, with every Laravel test and every Dart test green:
    // the Laravel ones asserted config shape, the Dart ones built
    // RepeaterComponent with an explicit `readOnly`. Only parsing the real
    // server output can see it.
    final panel = await RestResourceDataSource(
      transport: GoldenTransport(),
    ).panel();

    final repeaters = <String?, RepeaterComponent>{};

    for (final resource in panel.resources) {
      visitForm(resource, (component) {
        if (component is RepeaterComponent) {
          repeaters[component.name] = component;
        }
      });
    }

    expect(repeaters.keys, contains('line_items'));
    expect(
      repeaters['line_items']!.readOnly,
      isFalse,
      reason: 'an ordinary JSON-column repeater must arrive editable',
    );
    expect(
      repeaters['tag_rows']!.readOnly,
      isTrue,
      reason: 'a relationship repeater is refused this slice',
    );
    // P6c close-out, Finding 1. `guarded_rows` holds a `Hidden` in its item
    // template, so no rule ever names that child and a whole-array write
    // would delete its key from every row. The server refuses the field
    // rather than offering a control that eats data; the same cross-package
    // loop that caught the readOnly default has to see the refusal arrive.
    expect(
      repeaters['guarded_rows']!.readOnly,
      isTrue,
      reason:
          'a repeater whose item template holds a child that would not '
          'round-trip is refused, not offered',
    );
  });

  // Two guarantees, kept as two tests. `relations` is always present, even
  // when empty (mirrors Laravel's own `it publishes an empty relations array
  // for a resource with none`, exercised against `posts`) — that's a
  // contract shape, not fixture content, and holds regardless of what any
  // one resource declares.
  test('every resource in the real output publishes a relations key', () {
    for (final resource in fixture['resources'] as List) {
      expect(
        (resource as Map)['relations'],
        isA<List>(),
        reason: '${resource['key']} has no relations key',
      );
    }
  });

  // P6f Task 1 taught the walker to publish `locale` and `direction` on the
  // panel block, driven off Filament's own locale/direction, not a fixture
  // hand-edited toward Arabic. Pin both: `direction` must be exactly `ltr`
  // or `rtl` (not merely present), and `locale` must be a non-empty string —
  // a check that the `panel` block is a Map would pass against a fixture
  // that never carried these keys at all.
  test('the panel block carries a real locale and direction', () {
    final panel = fixture['panel'] as Map;

    expect(
      panel['direction'],
      anyOf('ltr', 'rtl'),
      reason: 'panel.direction must be exactly ltr or rtl',
    );
    expect(
      panel['locale'],
      isA<String>().having((l) => l.isNotEmpty, 'non-empty', isTrue),
      reason: 'panel.locale must be a non-empty string',
    );
  });

  // P6e Task 4: `rich_entry` joined `ComponentTypeMap::REFINED` (Task 2).
  // Task 5 taught this build to parse it as an `EntryComponent` with
  // `EntryKind.rich` rather than degrade to `UnknownComponent`. Not merely
  // "the list is non-empty" — `BannerResource`'s `body_html` is the real
  // Banner column `Banner::setUpRichContent()` registers (Task 1), refined by
  // `SchemaWalker::refineType()` from `text_entry` because the MODEL, not a
  // `->prose()` call, declares it rich. Pin both the type string and which
  // field carries it, so a fixture that emitted an empty or misnamed node
  // could not pass this by accident.
  test('a rich entry genuinely reaches the client as rich_entry', () async {
    final panel = await RestResourceDataSource(
      transport: GoldenTransport(),
    ).panel();

    SchemaComponent? richNode;

    void walk(List<SchemaComponent> components) {
      for (final component in components) {
        if (component.type == 'rich_entry') richNode = component;
        if (component is LayoutComponent) walk(component.children);
        if (component is UnknownComponent) walk(component.children);
      }
    }

    for (final resource in panel.resources) {
      walk(resource.infolist);
    }

    expect(
      richNode,
      isNotNull,
      reason: 'no rich_entry node reached the client',
    );
    expect(richNode!.name, 'body_html');
    expect(
      (richNode! as EntryComponent).kind,
      EntryKind.rich,
      reason:
          'a rich_entry must parse as EntryKind.rich, not fall back to '
          'EntryKind.text or degrade to UnknownComponent',
    );
  });

  // `BannerResource` now declares a real `TagsRelationManager` (a
  // BelongsToMany — every other relation fixture in the Laravel suite is a
  // HasMany), so the golden panel carries at least one populated relation
  // and this parses real server output rather than only `[]`.
  test('every published relation carries a card the client can render', () {
    final relations = <Map<String, dynamic>>[];
    for (final resource in fixture['resources'] as List) {
      for (final relation
          in (resource as Map)['relations'] as List? ?? const []) {
        relations.add(relation as Map<String, dynamic>);
      }
    }

    expect(
      relations,
      isNotEmpty,
      reason: 'the fixture panel publishes no relation at all',
    );

    for (final relation in relations) {
      expect(relation['key'], isA<String>());
      expect(
        (relation['card'] as Map)['title'],
        isNotNull,
        reason: 'relation ${relation['key']} has a card with no title',
      );
    }
  });
}

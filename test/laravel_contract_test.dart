import 'package:filament_mobile/data/rest_resource_data_source.dart';
import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden_transport.dart';

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
    final panel = await RestResourceDataSource(
      transport: GoldenTransport(),
    ).panel();

    final unknown = <String>[];

    void walk(List<SchemaComponent> components) {
      for (final component in components) {
        if (component is UnknownComponent) unknown.add(component.type);
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
}

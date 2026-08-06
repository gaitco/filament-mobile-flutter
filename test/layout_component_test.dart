import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LayoutComponent', () {
    test('maps each layout type onto a kind', () {
      LayoutKind kindOf(String type) =>
          (SchemaComponent.fromJson({'type': type}, 'form[0]')
                  as LayoutComponent)
              .kind;

      expect(kindOf('section'), LayoutKind.section);
      expect(kindOf('grid'), LayoutKind.grid);
      expect(kindOf('tabs'), LayoutKind.tabs);
      expect(kindOf('fieldset'), LayoutKind.fieldset);
    });

    test('parses children recursively', () {
      final layout =
          SchemaComponent.fromJson(const {
                'type': 'section',
                'label': 'البيانات الأساسية',
                'collapsible': true,
                'collapsed': true,
                'columns': 2,
                'children': [
                  {'type': 'text', 'name': 'name'},
                  {
                    'type': 'grid',
                    'children': [
                      {'type': 'toggle', 'name': 'is_active'},
                    ],
                  },
                ],
              }, 'form[0]')
              as LayoutComponent;

      expect(layout.label, 'البيانات الأساسية');
      expect(layout.collapsible, isTrue);
      expect(layout.collapsed, isTrue);
      expect(layout.columns, 2);
      expect(layout.children, hasLength(2));
      expect(layout.children.first, isA<TextComponent>());

      final nested = layout.children.last as LayoutComponent;
      expect(nested.children.single, isA<BooleanComponent>());
    });

    test('has no name and defaults to one column, not collapsible', () {
      final layout =
          SchemaComponent.fromJson(const {'type': 'section'}, 'form[0]')
              as LayoutComponent;

      expect(layout.name, isNull);
      expect(layout.columns, 1);
      expect(layout.collapsible, isFalse);
      expect(layout.collapsed, isFalse);
      expect(layout.children, isEmpty);
    });

    test('clamps a nonsensical column count to 1 rather than throwing', () {
      int columnsOf(int raw) =>
          (SchemaComponent.fromJson({'type': 'grid', 'columns': raw}, 'form[0]')
                  as LayoutComponent)
              .columns;

      expect(columnsOf(0), 1);
      expect(columnsOf(-5), 1);
      expect(columnsOf(3), 3);
    });

    test('reports the path of a malformed child', () {
      expect(
        () => SchemaComponent.fromJson(const {
          'type': 'section',
          'children': [
            {'name': 'no_type'},
          ],
        }, 'form[2]'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'form[2].children[0].type',
          ),
        ),
      );
    });
  });
}

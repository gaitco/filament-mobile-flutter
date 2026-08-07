import 'package:filament_mobile/form/form_values.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

T parse<T extends SchemaComponent>(Map<String, dynamic> json) =>
    SchemaComponent.fromJson(json, 'form[0]') as T;

const _template = {'type': 'text', 'name': 'sku', 'label': 'SKU'};

SchemaComponent repeaterField({bool readOnly = false}) {
  return SchemaComponent.fromJson({
    'type': 'repeater',
    'name': 'line_items',
    'children': [_template],
    'config': {'readOnly': readOnly},
  }, 'test');
}

void main() {
  group('RepeaterComponent parsing', () {
    test('parses the template and every config key', () {
      final component = parse<RepeaterComponent>({
        'type': 'repeater',
        'name': 'line_items',
        'label': 'Line items',
        'children': [_template],
        'config': {
          'addable': true,
          'deletable': true,
          'minItems': 1,
          'maxItems': 5,
          'itemLabel': 'Item',
          'readOnly': false,
        },
      });

      expect(component.name, 'line_items');
      expect(component.children, hasLength(1));
      expect(component.children.single, isA<TextComponent>());
      expect(component.children.single.name, 'sku');
      expect(component.addable, isTrue);
      expect(component.deletable, isTrue);
      expect(component.minItems, 1);
      expect(component.maxItems, 5);
      expect(component.itemLabel, 'Item');
      expect(component.readOnly, isFalse);
    });

    test('absent config keys take safe defaults — inert, the FileComponent '
        'direction', () {
      // An older server that predates repeater support entirely publishes
      // none of this: readOnly true, addable/deletable false, so the
      // renderer offers no control it cannot honour.
      final component = parse<RepeaterComponent>({
        'type': 'repeater',
        'name': 'line_items',
        'children': [_template],
      });

      expect(component.readOnly, isTrue);
      expect(component.addable, isFalse);
      expect(component.deletable, isFalse);
      expect(component.minItems, isNull);
      expect(component.maxItems, isNull);
      expect(component.itemLabel, isNull);
    });

    test('a malformed child is skipped, its siblings survive', () {
      final component = parse<RepeaterComponent>({
        'type': 'repeater',
        'name': 'line_items',
        'children': [
          _template,
          {'name': 'missing_type'}, // no 'type' — throws mid-parse
          'not even an object',
          {'type': 'select', 'name': 'category'},
        ],
      });

      expect(component.children, hasLength(2));
      expect(component.children.first.name, 'sku');
      expect(component.children.last.name, 'category');
    });

    test('a children value that is not a list throws — a contract '
        'violation, not a widening', () {
      expect(
        () => parse<RepeaterComponent>({
          'type': 'repeater',
          'name': 'line_items',
          'children': 'nope',
        }),
        throwsA(isA<SchemaFormatException>()),
      );
    });

    test('an absent children key yields an empty template', () {
      final component = parse<RepeaterComponent>({
        'type': 'repeater',
        'name': 'line_items',
      });

      expect(component.children, isEmpty);
    });
  });

  group('writableFields treats a repeater as one field', () {
    test('yields the repeater itself, not its item template fields', () {
      final fields = writableFields([repeaterField()]).toList();

      expect(fields, hasLength(1));
      expect(fields.single.name, 'line_items');
    });

    test('a readOnly repeater is excluded from the payload', () {
      final components = [repeaterField(readOnly: true)];
      final values = FormValues.initial(components).set('line_items', [
        {'sku': 'a'},
      ]);

      expect(values.payloadFor(components).containsKey('line_items'), isFalse);
    });

    test('a writable repeater carries its rows through, unflattened', () {
      final components = [repeaterField(readOnly: false)];
      final rows = [
        {'sku': 'a'},
        {'sku': 'b'},
      ];
      final values = FormValues.initial(components).set('line_items', rows);

      expect(values.payloadFor(components)['line_items'], rows);
    });
  });
}

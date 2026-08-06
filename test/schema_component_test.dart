import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/schema/validation_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('common properties', () {
    test('parses every shared property', () {
      final component = SchemaComponent.fromJson(const {
        'type': 'text',
        'name': 'email',
        'label': 'البريد الإلكتروني',
        'helperText': 'مطلوب',
        'columnSpan': 6,
        'hidden': true,
        'disabled': true,
        'live': true,
      }, 'form[0]');

      expect(component.name, 'email');
      expect(component.label, 'البريد الإلكتروني');
      expect(component.helperText, 'مطلوب');
      expect(component.columnSpan, 6);
      expect(component.hidden, isTrue);
      expect(component.disabled, isTrue);
      expect(component.live, isTrue);
    });

    test('defaults columnSpan to 12 and the flags to false', () {
      final component = SchemaComponent.fromJson(const {
        'type': 'text',
        'name': 'x',
      }, 'form[0]');

      expect(component.columnSpan, 12);
      expect(component.hidden, isFalse);
      expect(component.disabled, isFalse);
      expect(component.live, isFalse);
    });

    test('clamps columnSpan into 1..12 instead of trusting the server', () {
      int spanOf(int raw) => SchemaComponent.fromJson({
        'type': 'text',
        'name': 'x',
        'columnSpan': raw,
      }, 'form[0]').columnSpan;

      expect(spanOf(-5), 1);
      expect(spanOf(0), 1);
      expect(spanOf(6), 6);
      expect(spanOf(99), 12);
    });

    test('rules live on the base node, so a checkbox keeps them', () {
      final component = SchemaComponent.fromJson(const {
        'type': 'checkbox',
        'name': 'terms',
        'rules': {'required': true},
      }, 'form[0]');

      expect(component, isA<BooleanComponent>());
      expect(component.rules.required, isTrue);
    });

    test('rules default to none for a node that declares none', () {
      final component = SchemaComponent.fromJson(const {
        'type': 'text_entry',
        'name': 'name',
      }, 'infolist[0]');

      expect(component.rules, const ValidationRules.none());
    });

    test('parses writable, defaulting to true when absent', () {
      final absent = SchemaComponent.fromJson(const {
        'type': 'text',
        'name': 'a',
      }, 'f[0]');
      final present = SchemaComponent.fromJson(const {
        'type': 'text',
        'name': 'a',
        'writable': false,
      }, 'f[0]');

      expect(absent.writable, isTrue);
      expect(present.writable, isFalse);
    });

    test('writable participates in equality', () {
      // Omitting it from props makes two differing components compare
      // equal, which silently defeats any rebuild that depends on the
      // difference.
      expect(
        SchemaComponent.fromJson(const {'type': 'text', 'name': 'a'}, 'f'),
        isNot(
          SchemaComponent.fromJson(const {
            'type': 'text',
            'name': 'a',
            'writable': false,
          }, 'f'),
        ),
      );
    });

    test('throws with the path when type is missing', () {
      expect(
        () => SchemaComponent.fromJson(const {'name': 'x'}, 'form[3]'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'form[3].type',
          ),
        ),
      );
    });
  });

  group('unknown types', () {
    test('degrade to UnknownComponent instead of throwing', () {
      final component = SchemaComponent.fromJson(const {
        'type': 'signature_pad',
        'name': 'sig',
      }, 'form[0]');

      expect(component, isA<UnknownComponent>());
      expect(component.type, 'signature_pad');
      expect(component.name, 'sig');
      expect((component as UnknownComponent).children, isEmpty);
    });

    test('an unknown container keeps its children reachable', () {
      final component =
          SchemaComponent.fromJson(const {
                'type': 'wizard',
                'children': [
                  {'type': 'text', 'name': 'name'},
                  {
                    'type': 'section',
                    'children': [
                      {'type': 'toggle', 'name': 'is_active'},
                    ],
                  },
                ],
              }, 'form[0]')
              as UnknownComponent;

      expect(component.children, hasLength(2));
      expect(component.children.first, isA<TextComponent>());

      final nested = component.children.last as LayoutComponent;
      expect(nested.children.single, isA<BooleanComponent>());
    });

    test('a malformed grandchild under an unknown container reports its '
        'full path', () {
      expect(
        () => SchemaComponent.fromJson(const {
          'type': 'wizard',
          'children': [
            {
              'type': 'section',
              'children': [
                {'name': 'no_type'},
              ],
            },
          ],
        }, 'form[1]'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'form[1].children[0].children[0].type',
          ),
        ),
      );
    });
  });

  group('recursion depth', () {
    Map<String, dynamic> nest(int levels) {
      var node = <String, dynamic>{'type': 'text', 'name': 'leaf'};
      for (var i = 0; i < levels; i++) {
        node = <String, dynamic>{
          'type': 'section',
          'children': [node],
        };
      }
      return node;
    }

    test('parses a tree at the cap', () {
      expect(
        SchemaComponent.fromJson(nest(SchemaComponent.maxDepth), 'form[0]'),
        isA<LayoutComponent>(),
      );
    });

    test(
      'throws SchemaFormatException past the cap, not StackOverflowError',
      () {
        expect(
          () =>
              SchemaComponent.fromJson(nest(SchemaComponent.maxDepth + 1), 'f'),
          throwsA(
            isA<SchemaFormatException>().having(
              (e) => e.message,
              'message',
              contains('nested too deeply'),
            ),
          ),
        );
      },
    );
  });

  group('TextComponent', () {
    test('maps each text-ish type onto a kind', () {
      TextKind kindOf(String type) {
        final component = SchemaComponent.fromJson({
          'type': type,
          'name': 'f',
        }, 'form[0]');
        return (component as TextComponent).kind;
      }

      expect(kindOf('text'), TextKind.text);
      expect(kindOf('textarea'), TextKind.textarea);
      expect(kindOf('email'), TextKind.email);
      expect(kindOf('password'), TextKind.password);
    });

    test('parses placeholder, default and rules', () {
      final component =
          SchemaComponent.fromJson(const {
                'type': 'text',
                'name': 'name',
                'placeholder': 'اكتب الاسم',
                'default': 'أحمد',
                'rules': {'required': true, 'max': 255},
              }, 'form[0]')
              as TextComponent;

      expect(component.placeholder, 'اكتب الاسم');
      expect(component.defaultValue, 'أحمد');
      expect(component.rules.required, isTrue);
      expect(component.rules.max, 255);
    });
  });

  group('listFromJson', () {
    test('returns an empty list for a missing key', () {
      expect(
        SchemaComponent.listFromJson(const {}, 'form', 'resource'),
        isEmpty,
      );
    });

    test('parses each element with an indexed path', () {
      final components = SchemaComponent.listFromJson(
        const {
          'form': [
            {'type': 'text', 'name': 'a'},
            {'type': 'text', 'name': 'b'},
          ],
        },
        'form',
        'resource',
      );

      expect(components.map((c) => c.name), ['a', 'b']);
    });
  });
}

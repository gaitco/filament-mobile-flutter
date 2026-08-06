import 'package:filament_mobile/schema/resource_action.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResourceAction', () {
    test('parses a confirmed row action with a form', () {
      final action = ResourceAction.fromJson(const {
        'name': 'approve',
        'label': 'موافقة',
        'icon': 'check',
        'color': 'success',
        'scope': 'row',
        'destructive': false,
        'requiresConfirmation': true,
        'confirmation': {
          'title': 'تأكيد',
          'body': 'هل أنت متأكد؟',
          'confirmLabel': 'موافقة',
        },
        'form': [
          {'type': 'textarea', 'name': 'note'},
        ],
        'visible': true,
      }, 'resources[0].actions[0]');

      expect(action.name, 'approve');
      expect(action.label, 'موافقة');
      expect(action.icon, 'check');
      expect(action.color, 'success');
      expect(action.scope, ActionScope.row);
      expect(action.destructive, isFalse);
      expect(action.requiresConfirmation, isTrue);
      expect(action.confirmation!.body, 'هل أنت متأكد؟');
      expect(action.form.single, isA<TextComponent>());
      expect(action.visible, isTrue);
    });

    test('parses each scope', () {
      ActionScope scopeOf(String scope) => ResourceAction.fromJson({
        'name': 'a',
        'label': 'l',
        'scope': scope,
      }, 'actions[0]').scope;

      expect(scopeOf('row'), ActionScope.row);
      expect(scopeOf('bulk'), ActionScope.bulk);
      expect(scopeOf('header'), ActionScope.header);
    });

    test('an unrecognised scope is a contract violation, not a row action', () {
      // Falling back to `row` would place a button the client cannot place on
      // every single record — worse than refusing the document.
      expect(
        () => ResourceAction.fromJson(const {
          'name': 'a',
          'label': 'l',
          'scope': 'sidebar',
        }, 'resources[0].actions[0]'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.path,
            'path',
            'resources[0].actions[0].scope',
          ),
        ),
      );
    });

    test('defaults: row scope, visible, no confirmation, no form', () {
      final action = ResourceAction.fromJson(const {
        'name': 'edit',
        'label': 'تعديل',
      }, 'actions[0]');

      expect(action.scope, ActionScope.row);
      expect(action.visible, isTrue);
      expect(action.destructive, isFalse);
      expect(action.requiresConfirmation, isFalse);
      expect(action.confirmation, isNull);
      expect(action.form, isEmpty);
    });

    test('requiresConfirmation without a confirmation object still parses', () {
      final action = ResourceAction.fromJson(const {
        'name': 'delete',
        'label': 'حذف',
        'requiresConfirmation': true,
      }, 'actions[0]');

      expect(action.requiresConfirmation, isTrue);
      expect(action.confirmation, isNull);
    });

    test('listFromJson returns empty for a missing key', () {
      expect(
        ResourceAction.listFromJson(const {}, 'actions', 'resource'),
        isEmpty,
      );
    });
  });
}

import 'package:filament_mobile/schema/resource_labels.dart';
import 'package:filament_mobile/schema/validation_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ValidationRules', () {
    test('parses the supported keys', () {
      final rules = ValidationRules.fromJson(const {
        'required': true,
        'max': 255,
        'email': true,
      });

      expect(rules.required, isTrue);
      expect(rules.max, 255);
      expect(rules.email, isTrue);
      expect(rules.min, isNull);
      expect(rules.url, isFalse);
    });

    test('ignores unsupported keys instead of guessing', () {
      final rules = ValidationRules.fromJson(const {'dimensions': '16:9'});
      expect(rules, const ValidationRules.none());
    });

    test('none() is empty', () {
      const rules = ValidationRules.none();
      expect(rules.required, isFalse);
      expect(rules.min, isNull);
      expect(rules.regex, isNull);
    });

    test('parses numeric and messages', () {
      final rules = ValidationRules.fromJson(const {
        'required': true,
        'numeric': true,
        'messages': {'required': 'مطلوب'},
      });

      expect(rules.numeric, isTrue);
      expect(rules.messages['required'], 'مطلوب');
    });

    test('an absent numeric reads as false and absent messages as empty', () {
      final rules = ValidationRules.fromJson(const {'required': true});

      expect(rules.numeric, isFalse);
      expect(rules.messages, isEmpty);
    });

    test('a malformed messages block reads as empty rather than throwing', () {
      // Rules are documented as hints and the server revalidates, so a
      // malformed block costs a fallback message, never a crash.
      final rules = ValidationRules.fromJson(const {'messages': 'nope'});

      expect(rules.messages, isEmpty);
    });
  });

  group('ResourceLabels', () {
    test('parses singular, plural and icon', () {
      final labels = ResourceLabels.fromJson(const {
        'singular': 'مستخدم',
        'plural': 'المستخدمون',
        'icon': 'users',
      }, 'resource');

      expect(labels.singular, 'مستخدم');
      expect(labels.plural, 'المستخدمون');
      expect(labels.icon, 'users');
    });

    test('throws with a path when singular is missing', () {
      expect(
        () => ResourceLabels.fromJson(const {
          'plural': 'x',
        }, 'resources[0].labels'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ResourcePermissions', () {
    test('parses every flag', () {
      final permissions = ResourcePermissions.fromJson(const {
        'viewAny': true,
        'view': true,
        'create': true,
        'update': false,
        'delete': false,
      });

      expect(permissions.create, isTrue);
      expect(permissions.update, isFalse);
      expect(permissions.delete, isFalse);
    });

    test('defaults every missing flag to false — deny by default', () {
      final permissions = ResourcePermissions.fromJson(const {});
      expect(permissions.viewAny, isFalse);
      expect(permissions.view, isFalse);
      expect(permissions.create, isFalse);
      expect(permissions.update, isFalse);
      expect(permissions.delete, isFalse);
    });
  });
}

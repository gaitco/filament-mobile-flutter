import 'dart:convert';
import 'dart:io';

import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('../../contract/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('contract/panel.json', () {
    late PanelSchema panel;

    setUp(() => panel = PanelSchema.fromJson(fixture('panel.json')));

    test('parses the panel and navigation', () {
      expect(panel.version, PanelSchema.supportedVersion);
      expect(panel.id, 'admin');
      expect(panel.navigation, hasLength(2));
      expect(panel.resources, hasLength(3));
    });

    test('a resource may belong to no navigation group', () {
      final grouped = {
        for (final group in panel.navigation) ...group.resources,
      };

      expect(panel.resource('activity_logs'), isNotNull);
      expect(grouped, isNot(contains('activity_logs')));
      expect(grouped, contains('users'));
    });

    test('parses the users resource end to end', () {
      final users = panel.resource('users')!;

      expect(users.labels.plural, 'المستخدمون');
      expect(users.permissions.update, isTrue);
      expect(users.permissions.delete, isFalse);
      expect(users.card.titleField, 'name');
      expect(users.card.leading!.fallback, 'initials');
      expect(users.card.badges.single.colors['banned'], 'danger');
      expect(users.search.enabled, isTrue);
      expect(users.defaultSort!.key, 'created_at');
      expect(users.filters.single, isA<SelectComponent>());
    });

    test('the form section holds every v1 field type', () {
      final users = panel.resource('users')!;
      final section = users.form.first as LayoutComponent;

      expect(section.kind, LayoutKind.section);
      expect(section.collapsible, isTrue);
      expect(section.columns, 2);

      final byName = {for (final child in section.children) child.name: child};

      expect(byName['name'], isA<TextComponent>());
      expect((byName['email']! as TextComponent).kind, TextKind.email);
      expect((byName['password']! as TextComponent).kind, TextKind.password);
      expect((byName['bio']! as TextComponent).kind, TextKind.textarea);
      expect(byName['credit'], isA<NumberComponent>());
      expect((byName['credit']! as NumberComponent).prefix, 'ج.م');
      expect((byName['roles']! as SelectComponent).multiple, isTrue);
      expect((byName['country_id']! as SelectComponent).optionsUrl, isNotNull);
      expect(byName['country_id']!.live, isTrue);
      expect(byName['city_id']!.hidden, isTrue);
      expect(
        (byName['is_active']! as BooleanComponent).kind,
        BooleanKind.toggle,
      );
      expect(
        (byName['newsletter']! as BooleanComponent).kind,
        BooleanKind.checkbox,
      );
      expect((byName['born_at']! as DateComponent).kind, DateKind.date);
      expect((byName['born_at']! as DateComponent).maxDate, isNotNull);
      expect((byName['verified_at']! as DateComponent).kind, DateKind.datetime);
      expect(section.children, hasLength(12));
      expect(byName.keys.whereType<String>(), hasLength(12));
    });

    test('the second form node covers tabs, fieldset and the rest of §5.3', () {
      final tabs = panel.resource('users')!.form.last as LayoutComponent;

      expect(tabs.kind, LayoutKind.tabs);
      expect(tabs.children, hasLength(2));

      final links = tabs.children.first as LayoutComponent;
      expect(links.kind, LayoutKind.fieldset);
      expect(links.columns, 2);

      final byName = {for (final child in links.children) child.name: child};
      expect(byName['website']!.helperText, 'يبدأ بـ https://');
      expect(byName['website']!.rules.url, isTrue);
      expect(byName['handle']!.rules.regex, r'^[a-z0-9_]+$');
      expect(byName['handle']!.rules.max, 30);

      final system = tabs.children.last as LayoutComponent;
      expect(system.kind, LayoutKind.fieldset);
      expect(system.children.single.name, 'last_login_ip');
      expect(system.children.single.disabled, isTrue);
    });

    test('the infolist holds every v1 entry kind', () {
      final users = panel.resource('users')!;
      final grid = users.infolist.single as LayoutComponent;
      final kinds = grid.children.cast<EntryComponent>().map((e) => e.kind);

      expect(kinds, [
        EntryKind.text,
        EntryKind.badge,
        EntryKind.image,
        EntryKind.boolean,
        EntryKind.date,
      ]);
    });

    test('a minimal resource parses with defaults', () {
      final posts = panel.resource('posts')!;

      expect(posts.recordKey, 'id');
      expect(posts.search.enabled, isFalse);
      expect(posts.form, isEmpty);
    });
  });

  group('contract/laravel-panel.json', () {
    // The other half of the loop. Until this existed, nothing ever fed the
    // Laravel snapshot to the Dart parser: the PHP snapshot test only proved
    // Laravel still emits what Laravel emitted. A `direction: "DESC"` and an
    // invented `icon_entry` both shipped through exactly this gap.
    late PanelSchema panel;

    setUp(() => panel = PanelSchema.fromJson(fixture('laravel-panel.json')));

    test('parses every resource the Laravel package emits', () {
      expect(panel.version, PanelSchema.supportedVersion);
      expect(panel.resources, isNotEmpty);

      for (final resource in panel.resources) {
        expect(resource.key, isNotEmpty);
        expect(resource.recordKey, isNotEmpty);
      }
    });

    test('every emitted component type is one the client renders', () {
      Iterable<SchemaComponent> flatten(Iterable<SchemaComponent> nodes) sync* {
        for (final node in nodes) {
          yield node;
          if (node is LayoutComponent) yield* flatten(node.children);
        }
      }

      final nodes = [
        for (final resource in panel.resources)
          ...flatten([...resource.form, ...resource.infolist]),
      ];

      expect(nodes, isNotEmpty);
      expect(
        nodes.whereType<UnknownComponent>().map((n) => n.type),
        isEmpty,
        reason: 'an UnknownComponent is skipped entirely in release builds',
      );
    });

    test('the infolist icon entry arrives as a boolean entry', () {
      final posts = panel.resource('posts')!;
      final published = posts.infolist.firstWhere((n) => n.name == 'published');

      expect((published as EntryComponent).kind, EntryKind.boolean);
    });

    test('rules.numeric and rules.messages arrive from the real snapshot, '
        'not just a hand-built fixture', () {
      // Until this, nothing ever fed a real numeric/messages node through
      // the Dart parser against the Laravel-generated snapshot — exactly
      // the icon_entry gap this group exists to close for those two keys.
      Iterable<SchemaComponent> flatten(Iterable<SchemaComponent> nodes) sync* {
        for (final node in nodes) {
          yield node;
          if (node is LayoutComponent) yield* flatten(node.children);
        }
      }

      final nodes = [
        for (final resource in panel.resources)
          ...flatten([...resource.form, ...resource.infolist]),
      ];

      final numeric = nodes.where((n) => n.rules.numeric).toList();
      expect(numeric, isNotEmpty);

      final withMessages = nodes.where((n) => n.rules.messages.isNotEmpty);
      expect(withMessages, isNotEmpty);

      for (final node in withMessages) {
        for (final message in node.rules.messages.values) {
          expect(
            message,
            isNot(contains(':')),
            reason:
                '"$message" on ${node.name} still has an unsubstituted '
                'Laravel placeholder',
          );
        }
      }
    });

    test('rules.email and the textarea type arrive from the real snapshot, '
        'not just a hand-built fixture', () {
      // client_validator_test.dart proves the parser accepts rules.email off
      // hand-built JSON; nothing before this fed a real email/textarea node
      // from the Laravel-generated snapshot through it — the same
      // JSON-key-to-model-field gap that let an invented `icon_entry` and a
      // `direction: DESC` ship silently, once each, through this group.
      //
      // Scoped to `banners` specifically, not flattened across every
      // resource: PostResource's fixture form independently declares its
      // own `contact_email`, so an unscoped `firstWhere` over all resources
      // would silently match that node instead and never notice a stripped
      // `banners.contact_email`.
      Iterable<SchemaComponent> flatten(Iterable<SchemaComponent> nodes) sync* {
        for (final node in nodes) {
          yield node;
          if (node is LayoutComponent) yield* flatten(node.children);
        }
      }

      final banners = panel.resource('banners')!;
      final nodes = flatten([...banners.form, ...banners.infolist]).toList();

      final contactEmail = nodes.firstWhere((n) => n.name == 'contact_email');
      expect(contactEmail.rules.email, isTrue);

      final bodyHtml = nodes.firstWhere((n) => n.name == 'body_html');
      expect(bodyHtml.type, 'textarea');
    });

    test('writable arrives from the real snapshot, not just a hand-built '
        'fixture', () {
      // `tag_ids` motivated the key originally; the server now saves
      // multi-valued relationships, so it arrives writable and the field
      // that carries the lock in the real snapshot is `gated_tag_ids` —
      // a relation select behind a `->disabled()` gate. Scoped to
      // `banners`, the same reason `contact_email`/`body_html` above are:
      // an unscoped search over every resource risks matching a same-named
      // field elsewhere and never noticing this one was stripped.
      Iterable<SchemaComponent> flatten(Iterable<SchemaComponent> nodes) sync* {
        for (final node in nodes) {
          yield node;
          if (node is LayoutComponent) yield* flatten(node.children);
        }
      }

      final banners = panel.resource('banners')!;
      final nodes = flatten([...banners.form, ...banners.infolist]).toList();

      final tagIds = nodes.firstWhere((n) => n.name == 'tag_ids');
      expect(tagIds.writable, isTrue);

      final gated = nodes.firstWhere((n) => n.name == 'gated_tag_ids');
      expect(gated.disabled, isTrue);
    });

    test('the real snapshot carries a group on a grouped resource', () {
      // Three separate phases have had a contract addition slip through by
      // asserting only against hand-built JSON: icon_entry, then numeric and
      // messages, then email and textarea. This is that assertion.
      final grouped = panel.resources.where((r) => r.group != null);

      expect(grouped, isNotEmpty);
    });
  });

  test('an unknown component type degrades instead of throwing', () {
    final panel = PanelSchema.fromJson(fixture('unknown_component.json'));
    final form = panel.resource('signatures')!.form;

    expect(form.first, isA<UnknownComponent>());
    expect(form.first.type, 'signature_pad');
    expect(form.last, isA<TextComponent>(), reason: 'siblings still parse');
  });

  test('a newer contract version is rejected', () {
    expect(
      () => PanelSchema.fromJson(fixture('future_version.json')),
      throwsA(isA<UnsupportedSchemaVersionException>()),
    );
  });
}

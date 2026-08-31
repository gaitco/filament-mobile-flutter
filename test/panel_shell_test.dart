import 'dart:async';

import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/panel_notification.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_event_transport.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/resource_labels.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/panel_provider.dart';
import 'package:filament_mobile/ui/panel_shell.dart';
import 'package:filament_mobile/ui/resource_form_screen.dart';
import 'package:filament_mobile/ui/resource_list_screen.dart';
import 'package:filament_mobile/ui/resource_row.dart';
import 'package:filament_mobile/ui/resource_view_screen.dart';
import 'package:filament_mobile/ui/widget_slots.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/form_fixtures.dart';
import 'support/pump_until_found.dart';

ResourceSchema _resource(String key, String plural) => ResourceSchema(
  key: key,
  labels: ResourceLabels(singular: key, plural: plural),
  permissions: const ResourcePermissions.all(),
  card: const CardLayout(titleField: 'name'),
  search: const ResourceSearch(enabled: true),
  form: [
    SchemaComponent.fromJson(const {
      'type': 'text',
      'name': 'name',
      'label': 'Name',
    }, '$key.form[0]'),
  ],
  infolist: [
    SchemaComponent.fromJson(const {
      'type': 'text_entry',
      'name': 'name',
      'label': 'Name',
    }, '$key.infolist[0]'),
    // A targeted entry: tapping it opens tag 6 inside the same pane.
    SchemaComponent.fromJson(const {
      'type': 'text_entry',
      'name': 'tag.name',
      'label': 'Tag',
      'config': {
        'target': {'resource': 'tags', 'record': 'tag.id'},
      },
    }, '$key.infolist[1]'),
  ],
);

/// Two resources, three records each, every write succeeding.
class _ShellSource extends FakeSource {
  _ShellSource({
    PanelDirection direction = PanelDirection.ltr,
    NotificationsConfig? notifications,
  }) : _panel = PanelSchema(
         version: PanelSchema.supportedVersion,
         id: 'admin',
         title: 'Admin',
         direction: direction,
         notifications: notifications,
         resources: [_resource('posts', 'Posts'), _resource('tags', 'Tags')],
       ),
       super(
         components: [
           SchemaComponent.fromJson(const {
             'type': 'text',
             'name': 'name',
             'label': 'Name',
           }, 'posts.form[0]'),
         ],
         writeResult: const WriteSuccess({'id': 9}),
       );

  final PanelSchema _panel;
  int listCalls = 0;

  @override
  Future<PanelSchema> panel() async => _panel;

  @override
  Future<DashboardData> dashboard() async => const DashboardData();

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
    bool reorder = false,
    Map<String, Object?> filters = const {},
  }) async {
    listCalls++;
    return PaginatedRecords(
      records: [
        for (var i = 1; i <= 3; i++)
          ResourceRecord.fromJson(
            {'id': i, 'name': '$resourceKey $i'},
            'id',
            permissions: const {'update': true, 'delete': true},
          ),
      ],
      meta: const PageMeta(currentPage: 1, lastPage: 1, perPage: 20, total: 3),
    );
  }

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async =>
      ResourceRecord.fromJson(
        {
          'id': id,
          'name': '$resourceKey $id',
          'tag': {'id': 6, 'name': 'Tag six'},
        },
        'id',
        permissions: const {'update': true, 'delete': true},
      );

  @override
  Future<WriteResult> destroy(String resourceKey, Object id) async =>
      const WriteSuccess({});
}

Future<_ShellSource> _pumpShell(
  WidgetTester tester,
  double width, {
  PanelDirection direction = PanelDirection.ltr,
  FilamentWidgetRegistry? widgetRegistry,
  VoidCallback? onLogout,
  List<FilamentLanguageOption> languages = const [],
  String? activeLanguage,
  ValueChanged<String>? onLanguageSelected,
  _ShellSource? source,
  FilamentEventTransport? eventTransport,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  source ??= _ShellSource(direction: direction);
  final panelProvider = PanelProvider(source);
  await tester.pumpWidget(
    MaterialApp(
      home: PanelShell(
        source: source,
        panelProvider: panelProvider,
        widgetRegistry: widgetRegistry,
        eventTransport: eventTransport,
        onLogout: onLogout,
        languages: languages,
        activeLanguage: activeLanguage,
        onLanguageSelected: onLanguageSelected,
      ),
    ),
  );
  // The drawer's entries are not even built until it opens, so the load is
  // awaited on the provider rather than on any text.
  while (panelProvider.panel == null) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
  return source;
}

/// Page depth of the one nested navigator the shell owns at this form
/// factor — its stack is page-driven, so the pages list IS the route stack
/// (the form, pushed as a plain route on top in compact, is not counted).
int _depth(WidgetTester tester) => tester
    .widget<Navigator>(
      find.descendant(
        of: find.byType(PanelShell),
        matching: find.byType(Navigator),
      ),
    )
    .pages
    .length;

Future<void> _openPosts(WidgetTester tester) async {
  // The rail's unselected label is painted transparent, so the text itself
  // never hit-tests — the destination under it does.
  await tester.tap(find.text('Posts').last, warnIfMissed: false);
  await tester.pumpAndSettle();
  await pumpUntilFound(tester, find.text('posts 1'));
}

/// Detail-pane page count at expanded: placeholder + the current pane.
int _detailDepth(WidgetTester tester) =>
    tester.widget<Navigator>(find.byType(Navigator).last).pages.length;

Future<void> _openRelated(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('entry.related.tag.name')));
  await tester.pumpAndSettle();
  await pumpUntilFound(tester, find.text('tags 6'));
  await tester.pumpAndSettle();
}

ResourceRow _row(WidgetTester tester, String title) => tester.widget(
  find.ancestor(of: find.text(title), matching: find.byType(ResourceRow)),
);

/// A [_ShellSource] that also implements the notifications sidecar (P21) —
/// the panel node defaults to declared, so constructing one is the "both
/// gates open" fixture. The base [_ShellSource]/[FakeSource] deliberately do
/// NOT implement [NotificationsDataSource]: every pre-P21 shell test above
/// doubles as proof the bell stays hidden for a host that never opted in.
class _NotifyingSource extends _ShellSource implements NotificationsDataSource {
  _NotifyingSource({
    this.unread = 2,
    super.notifications = const NotificationsConfig(
      poll: Duration(seconds: 30),
    ),
  });

  int unread;
  int notificationsCalls = 0;
  final readIds = <String>[];
  final deletedIds = <String>[];
  int markAllCalls = 0;
  bool cleared = false;

  @override
  Future<NotificationsPage> notifications({int page = 1}) async {
    notificationsCalls++;
    return NotificationsPage(
      items: [
        PanelNotification(
          id: 'n-1',
          title: 'Order shipped',
          body: 'Order #7 left the warehouse',
          status: 'success',
          date: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        PanelNotification(
          id: 'n-2',
          title: 'Welcome',
          readAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
      unread: unread,
    );
  }

  @override
  Future<int> markNotificationRead(String id) async {
    readIds.add(id);
    return unread = unread > 0 ? unread - 1 : 0;
  }

  @override
  Future<int> markAllNotificationsRead() async {
    markAllCalls++;
    return unread = 0;
  }

  @override
  Future<void> deleteNotification(String id) async => deletedIds.add(id);

  @override
  Future<void> clearNotifications() async => cleared = true;
}

/// A [_NotifyingSource] whose panel also publishes the user's private
/// notification channel — the realtime-configured host.
class _ChannelNotifyingSource extends _NotifyingSource {
  _ChannelNotifyingSource()
    : super(
        notifications: const NotificationsConfig(
          poll: Duration(seconds: 30),
          channel: 'App.Models.User.7',
        ),
      );
}

/// The `_EventTransport` idiom from realtime_signals_test.dart: sync
/// broadcast streams a test can push invalidation events into.
class _BellEventTransport implements FilamentEventTransport {
  final controllers = <String, StreamController<RealtimeEvent>>{};

  @override
  Stream<RealtimeEvent> events(String channel) =>
      (controllers[channel] ??= StreamController.broadcast(sync: true)).stream;

  void add(String channel, RealtimeEvent event) =>
      controllers[channel]!.add(event);
}

void main() {
  testWidgets('forwards one custom-widget registry to owned screens', (
    tester,
  ) async {
    final registry = FilamentWidgetRegistry()
      ..register(
        FilamentWidgetSlot.resourceListBeforeContent,
        (context, scope) => Text(
          'host widget for ${(scope as ResourceListWidgetScope).resource.key}',
        ),
      );

    await _pumpShell(tester, 800, widgetRegistry: registry);
    await _openPosts(tester);

    expect(find.text('host widget for posts'), findsOneWidget);
  });

  group('language picker (P22)', () {
    const languages = [
      FilamentLanguageOption('en', 'English'),
      FilamentLanguageOption('ar', 'العربية'),
    ];

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byType(CircleAvatar));
      await tester.pumpAndSettle();
    }

    testWidgets('entries with a check on the active tag; tap reports the '
        'chosen tag', (tester) async {
      String? chosen;
      await _pumpShell(
        tester,
        400,
        languages: languages,
        activeLanguage: 'en',
        onLanguageSelected: (tag) => chosen = tag,
        onLogout: () {},
      );
      await openMenu(tester);

      expect(find.text('English'), findsOneWidget);
      expect(find.text('العربية'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      // The check sits beside the active language's label only.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('English'),
            matching: find.byType(PopupMenuItem<void>),
          ),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();
      expect(chosen, 'ar');
    });

    testWidgets('no callback → no entries; menu still shows for onLogout', (
      tester,
    ) async {
      await _pumpShell(tester, 400, languages: languages, onLogout: () {});
      await openMenu(tester);

      expect(find.text('English'), findsNothing);
      expect(find.text('Log out'), findsOneWidget);
    });

    testWidgets('one language is nothing to switch to', (tester) async {
      await _pumpShell(
        tester,
        400,
        languages: const [FilamentLanguageOption('en', 'English')],
        onLanguageSelected: (_) {},
      );

      // Without onLogout either, the whole profile menu stays hidden —
      // exactly the pre-P22 AppBar.
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('languages alone show the menu without a log-out item', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        400,
        languages: languages,
        onLanguageSelected: (_) {},
      );
      await openMenu(tester);

      expect(find.text('English'), findsOneWidget);
      expect(find.text('Log out'), findsNothing);
    });
  });

  group('notification bell (P21)', () {
    const bellKey = ValueKey('panel.notifications.bell');

    Badge bellBadge(WidgetTester tester) => tester.widget<Badge>(
      find.descendant(of: find.byKey(bellKey), matching: find.byType(Badge)),
    );

    testWidgets('hidden when the panel declares no notifications node', (
      tester,
    ) async {
      // The default _ShellSource has no node AND no sidecar — the pre-P21
      // AppBar exactly.
      await _pumpShell(tester, 400);
      expect(find.byKey(bellKey), findsNothing);
    });

    testWidgets('hidden when the source lacks the sidecar, even declared', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        400,
        source: _ShellSource(
          notifications: const NotificationsConfig(poll: Duration(seconds: 30)),
        ),
      );
      expect(find.byKey(bellKey), findsNothing);
    });

    testWidgets('visible with the unread count on the badge', (tester) async {
      await _pumpShell(tester, 400, source: _NotifyingSource());

      expect(find.byKey(bellKey), findsOneWidget);
      expect(bellBadge(tester).isLabelVisible, isTrue);
      expect(
        find.descendant(of: find.byKey(bellKey), matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('badge label hides at zero', (tester) async {
      await _pumpShell(tester, 400, source: _NotifyingSource(unread: 0));

      expect(find.byKey(bellKey), findsOneWidget);
      expect(bellBadge(tester).isLabelVisible, isFalse);
    });

    testWidgets('bell opens the sheet with rows; row tap marks read', (
      tester,
    ) async {
      final source = _NotifyingSource();
      await _pumpShell(tester, 400, source: source);

      await tester.tap(find.byKey(bellKey));
      await tester.pumpAndSettle();
      expect(find.text('Order shipped'), findsOneWidget);
      expect(find.text('Order #7 left the warehouse'), findsOneWidget);
      expect(find.text('Welcome'), findsOneWidget);

      await tester.tap(find.text('Order shipped'));
      await tester.pumpAndSettle();
      expect(source.readIds, ['n-1']);
      expect(
        find.descendant(of: find.byKey(bellKey), matching: find.text('1')),
        findsOneWidget,
        reason: 'the badge takes the server-answered count',
      );
    });

    testWidgets('mark-all-read shows only while unread, and zeroes the badge', (
      tester,
    ) async {
      final source = _NotifyingSource();
      await _pumpShell(tester, 400, source: source);
      await tester.tap(find.byKey(bellKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('notifications.markAllRead')));
      await tester.pumpAndSettle();

      expect(source.markAllCalls, 1);
      expect(bellBadge(tester).isLabelVisible, isFalse);
      expect(
        find.byKey(const ValueKey('notifications.markAllRead')),
        findsNothing,
        reason: 'nothing left to mark',
      );
    });

    testWidgets('clear-all asks first, then empties the feed', (tester) async {
      final source = _NotifyingSource();
      await _pumpShell(tester, 400, source: source);
      await tester.tap(find.byKey(bellKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('notifications.clearAll')));
      await tester.pumpAndSettle();
      expect(
        find.text(const FilamentStrings().clearNotificationsTitle),
        findsOneWidget,
      );
      expect(source.cleared, isFalse, reason: 'nothing deleted before confirm');

      await tester.tap(
        find.byKey(const ValueKey('notifications.clearAll.confirm')),
      );
      await tester.pumpAndSettle();

      expect(source.cleared, isTrue);
      expect(
        find.text(const FilamentStrings().notificationsEmpty),
        findsOneWidget,
      );
    });

    testWidgets('a realtime event refreshes through the published channel', (
      tester,
    ) async {
      final transport = _BellEventTransport();
      final source = _ChannelNotifyingSource();
      await _pumpShell(tester, 400, source: source, eventTransport: transport);
      final calls = source.notificationsCalls;

      source.unread = 5;
      transport.add(
        'App.Models.User.7',
        // Filament's own `database-notifications.sent` carries an empty
        // payload — any event on the channel is a refetch signal.
        const RealtimeEvent.changed(resourceKey: 'notifications'),
      );
      await tester.pumpAndSettle();

      expect(source.notificationsCalls, calls + 1);
      expect(
        find.descendant(of: find.byKey(bellKey), matching: find.text('5')),
        findsOneWidget,
      );
    });
  });

  group('compact (400)', () {
    testWidgets('drawer → list → view pushes on the nested navigator', (
      tester,
    ) async {
      await _pumpShell(tester, 400);
      expect(_depth(tester), 1);

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      await _openPosts(tester);
      expect(find.byType(ResourceListScreen), findsOneWidget);
      expect(_depth(tester), 2);

      await tester.tap(find.text('posts 1'));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceViewScreen), findsOneWidget);
      expect(_depth(tester), 3);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  group('compact delete', () {
    testWidgets('refreshes the list it pops back to', (tester) async {
      final source = await _pumpShell(tester, 400);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await _openPosts(tester);
      await tester.tap(find.text('posts 1'));
      await tester.pumpAndSettle();
      final listCalls = source.listCalls;

      await tester.tap(find.byKey(const ValueKey('record.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(const FilamentStrings().deleteConfirm).last);
      await tester.pumpAndSettle();

      expect(find.byType(ResourceListScreen), findsOneWidget);
      expect(source.listCalls, listCalls + 1);
    });
  });

  group('medium (700)', () {
    testWidgets('rail replaces the drawer; same pushes', (tester) async {
      await _pumpShell(tester, 700);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(Drawer, skipOffstage: false), findsNothing);

      await _openPosts(tester);
      expect(_depth(tester), 2);

      await tester.tap(find.text('posts 1'));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceViewScreen), findsOneWidget);
      expect(_depth(tester), 3);
    });
  });

  group('expanded (1200)', () {
    testWidgets('sidebar + master rows + empty detail placeholder', (
      tester,
    ) async {
      await _pumpShell(tester, 1200);
      expect(find.byKey(const ValueKey('panel.sidebar')), findsOneWidget);
      await _openPosts(tester);

      expect(find.byType(ResourceRow), findsNWidgets(3));
      expect(
        find.text(const FilamentStrings().noRecordSelected),
        findsOneWidget,
      );
    });

    testWidgets('row tap replaces the detail pane without a push', (
      tester,
    ) async {
      await _pumpShell(tester, 1200);
      await _openPosts(tester);
      final depthBefore = _depth(tester);

      await tester.tap(find.text('posts 1'));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceViewScreen), findsOneWidget);
      expect(_row(tester, 'posts 1').selected, isTrue);
      final depthSelected = _depth(tester);
      expect(depthSelected, lessThanOrEqualTo(depthBefore + 1));

      // A second selection swaps, never stacks.
      await tester.tap(find.text('posts 2'));
      await tester.pumpAndSettle();
      expect(_row(tester, 'posts 2').selected, isTrue);
      expect(_row(tester, 'posts 1').selected, isFalse);
      expect(_depth(tester), depthSelected);
      expect(find.byType(ResourceListScreen), findsOneWidget);
    });

    testWidgets('edit → form pane; save → toast + view pane', (tester) async {
      await _pumpShell(tester, 1200);
      await _openPosts(tester);
      await tester.tap(find.text('posts 1'));
      await tester.pumpAndSettle();
      final depth = _depth(tester);

      await tester.tap(find.byKey(const ValueKey('record.edit')));
      await pumpUntilFound(tester, find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceFormScreen), findsOneWidget);
      expect(find.byType(ResourceViewScreen), findsNothing);
      expect(_depth(tester), depth);

      await tester.tap(find.byKey(const ValueKey('form.submit')));
      await tester.pumpAndSettle();
      expect(find.text(const FilamentStrings().saved), findsOneWidget);
      expect(find.byType(ResourceFormScreen), findsNothing);
      expect(find.byType(ResourceViewScreen), findsOneWidget);
      expect(find.byType(ResourceListScreen), findsOneWidget);
    });

    testWidgets('FAB → create form in the pane; Esc clears', (tester) async {
      await _pumpShell(tester, 1200);
      await _openPosts(tester);

      await tester.tap(find.byKey(const ValueKey('resource.create')));
      await pumpUntilFound(tester, find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceFormScreen), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ResourceFormScreen), findsNothing);
      expect(
        find.text(const FilamentStrings().noRecordSelected),
        findsOneWidget,
      );
    });

    testWidgets('create → save selects the new record in the pane', (
      tester,
    ) async {
      final source = await _pumpShell(tester, 1200);
      await _openPosts(tester);
      final listCalls = source.listCalls;

      await tester.tap(find.byKey(const ValueKey('resource.create')));
      await pumpUntilFound(tester, find.byKey(const ValueKey('form.submit')));
      await tester.tap(find.byKey(const ValueKey('form.submit')));
      await tester.pumpAndSettle();

      expect(find.byType(ResourceViewScreen), findsOneWidget);
      expect(find.text('posts 9'), findsOneWidget);
      expect(source.listCalls, listCalls + 1, reason: 'list refreshed');
    });

    testWidgets('delete in the view clears the pane and refreshes the list', (
      tester,
    ) async {
      final source = await _pumpShell(tester, 1200);
      await _openPosts(tester);
      await tester.tap(find.text('posts 1'));
      await tester.pumpAndSettle();
      final listCalls = source.listCalls;

      await tester.tap(find.byKey(const ValueKey('record.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(const FilamentStrings().deleteConfirm).last);
      await tester.pumpAndSettle();

      expect(find.byType(ResourceViewScreen), findsNothing);
      expect(
        find.text(const FilamentStrings().noRecordSelected),
        findsOneWidget,
      );
      expect(source.listCalls, listCalls + 1);
    });

    testWidgets('↓ then Enter selects and opens the first row', (tester) async {
      await _pumpShell(tester, 1200);
      await _openPosts(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_row(tester, 'posts 1').selected, isTrue);
      expect(find.byType(ResourceViewScreen), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(ResourceViewScreen), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_row(tester, 'posts 2').selected, isTrue);
    });

    testWidgets('shortcuts yield to a focused text field', (tester) async {
      await _pumpShell(tester, 1200);
      await _openPosts(tester);
      await tester.tap(find.text('posts 1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField).first); // the list's search
      await tester.enterText(find.byType(TextField).first, 'abc');
      await tester.pumpAndSettle();
      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.escape,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      expect(_row(tester, 'posts 1').selected, isTrue);
      expect(find.byType(ResourceViewScreen), findsOneWidget);
      expect(find.text('abc'), findsOneWidget);
    });

    testWidgets('Enter on a focused form button activates it', (tester) async {
      await _pumpShell(tester, 1200);
      await _openPosts(tester);
      await tester.tap(find.text('posts 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('record.edit')));
      await pumpUntilFound(tester, find.byKey(const ValueKey('form.submit')));
      await tester.pumpAndSettle();

      // Focus the form's field, Tab onto Save, Enter: a save (toast), not
      // the shell's open-selection shortcut (which shows no toast).
      await tester.tap(find.byType(TextField).last);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text(const FilamentStrings().saved), findsOneWidget);
      expect(find.byType(ResourceViewScreen), findsOneWidget);
    });

    testWidgets('master pane is at least 360 wide at the threshold', (
      tester,
    ) async {
      await _pumpShell(tester, 840);
      await _openPosts(tester);
      expect(
        tester.getSize(find.byType(ResourceListScreen)).width,
        greaterThanOrEqualTo(360),
      );
    });

    testWidgets('a related record pushes in the pane; its edit pushes too', (
      tester,
    ) async {
      await _pumpShell(tester, 1200);
      await _openPosts(tester);
      await tester.tap(find.text('posts 1'));
      await tester.pumpAndSettle();
      final depth = _detailDepth(tester);

      await _openRelated(tester);
      expect(_detailDepth(tester), depth, reason: 'pushed, not a page swap');
      expect(_row(tester, 'posts 1').selected, isTrue);

      await tester.tap(find.byKey(const ValueKey('record.edit')));
      await pumpUntilFound(tester, find.byType(ResourceFormScreen));
      await tester.pumpAndSettle();
      expect(_detailDepth(tester), depth);
      expect(_row(tester, 'posts 1').selected, isTrue);

      await tester.tap(find.byKey(const ValueKey('form.submit')));
      await tester.pumpAndSettle();
      expect(find.byType(ResourceFormScreen), findsNothing);
      expect(find.text('tags 6'), findsOneWidget, reason: 'back on the tag');
      expect(find.byType(ResourceListScreen), findsOneWidget);
    });

    testWidgets('system back pops a pushed pane route, not the app', (
      tester,
    ) async {
      await _pumpShell(tester, 1200);
      await _openPosts(tester);
      await tester.tap(find.text('posts 1'));
      await tester.pumpAndSettle();
      await _openRelated(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('tags 6'), findsNothing);
      expect(find.byType(ResourceViewScreen), findsOneWidget);
      expect(find.byType(PanelShell), findsOneWidget);
    });

    testWidgets('RTL: sidebar sits on the right', (tester) async {
      await _pumpShell(tester, 1200, direction: PanelDirection.rtl);
      final sidebar = tester.getRect(
        find.byKey(const ValueKey('panel.sidebar')),
      );
      expect(sidebar.left, greaterThan(600));
      expect(sidebar.right, 1200);
    });
  });

  group('breakpoint crossing', () {
    testWidgets('1200 → 400 with a selection puts the view route on top', (
      tester,
    ) async {
      await _pumpShell(tester, 1200);
      await _openPosts(tester);
      await tester.tap(find.text('posts 2'));
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();

      expect(find.byType(ResourceViewScreen), findsOneWidget);
      expect(find.text('posts 2'), findsOneWidget);
      expect(_depth(tester), 3);
      expect(find.byKey(const ValueKey('panel.sidebar')), findsNothing);
    });

    testWidgets('400 → 1200 shows the list with the selection highlighted', (
      tester,
    ) async {
      await _pumpShell(tester, 400);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await _openPosts(tester);
      await tester.tap(find.text('posts 3'));
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();

      expect(find.byType(ResourceListScreen), findsOneWidget);
      expect(find.byType(ResourceViewScreen), findsOneWidget);
      expect(_row(tester, 'posts 3').selected, isTrue);
    });
  });
}

import 'dart:async';

import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:filament_mobile/state/panel_provider.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubSource implements ResourceDataSource {
  _StubSource({
    this.panelResult,
    this.error,
    this.cachedPanelResult,
    this.cachedPanelError,
  });

  final PanelSchema? panelResult;
  final Object? error;
  final PanelSchema? cachedPanelResult;
  final Object? cachedPanelError;
  int panelCalls = 0;

  bool _holdNextPanel = false;
  Completer<PanelSchema>? _heldPanel;

  /// Makes the next `panel()` call hang, so a test can assert on the state
  /// published from cache while the revalidation is still in flight.
  void holdNextPanel() => _holdNextPanel = true;

  void completeHeldPanel(PanelSchema panel) => _heldPanel!.complete(panel);

  @override
  Future<PanelSchema> panel() async {
    panelCalls++;
    if (_holdNextPanel) {
      _holdNextPanel = false;
      return (_heldPanel = Completer<PanelSchema>()).future;
    }
    if (error != null) throw error!;
    return panelResult!;
  }

  @override
  Future<PanelSchema?> cachedPanel() async {
    if (cachedPanelError != null) throw cachedPanelError!;
    return cachedPanelResult;
  }

  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
  }) async => throw UnimplementedError();

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async => throw UnimplementedError();

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async =>
      throw UnimplementedError();

  @override
  Future<WriteResult> create(String resourceKey, Map<String, dynamic> values) =>
      throw UnimplementedError();

  @override
  Future<WriteResult> update(
    String resourceKey,
    Object id,
    Map<String, dynamic> values,
  ) => throw UnimplementedError();

  @override
  Future<WriteResult> destroy(String resourceKey, Object id) =>
      throw UnimplementedError();

  @override
  Future<ActionResult> runAction(
    String resourceKey,
    Object id,
    String action,
  ) => throw UnimplementedError();

  @override
  Future<OptionsPage> options(
    String resourceKey, {

    required String field,

    Object? recordId,

    required Map<String, dynamic> values,

    required String query,
  }) => throw UnimplementedError();

  @override
  Future<List<SchemaComponent>> state(
    String resourceKey, {
    Object? recordId,
    required Map<String, dynamic> values,
    required String changed,
  }) => throw UnimplementedError();

  @override
  Future<DashboardData> dashboard() => throw UnimplementedError();

  @override
  Future<UploadResult> uploadFile(
    String resourceKey,
    String field, {
    required List<int> bytes,
    required String filename,
  }) => throw UnimplementedError();
}

PanelSchema get _panel => PanelSchema.fromJson(const {
  'version': 1,
  'panel': {'id': 'mobile', 'title': 'لوحة التحكم'},
  'resources': [],
});

PanelSchema get _otherPanel => PanelSchema.fromJson(const {
  'version': 1,
  'panel': {'id': 'mobile', 'title': 'محدث'},
  'resources': [],
});

void main() {
  test('starts in initial', () {
    expect(PanelProvider(_StubSource()).status, LoadStatus.initial);
  });

  test('load() moves through loading to success', () async {
    final provider = PanelProvider(_StubSource(panelResult: _panel));
    final seen = <LoadStatus>[];
    provider.addListener(() => seen.add(provider.status));

    await provider.load();

    expect(seen, [LoadStatus.loading, LoadStatus.success]);
    expect(provider.panel!.title, 'لوحة التحكم');
    expect(provider.errorMessage, isNull);
  });

  test('a transport failure becomes failure with a message', () async {
    final provider = PanelProvider(
      _StubSource(error: Exception('تعذّر الاتصال')),
    );

    await provider.load();

    expect(provider.status, LoadStatus.failure);
    expect(provider.errorMessage, contains('تعذّر الاتصال'));
    expect(provider.needsAppUpdate, isFalse);
  });

  test('an unsupported schema version sets needsAppUpdate', () async {
    final provider = PanelProvider(
      _StubSource(
        error: const UnsupportedSchemaVersionException(found: 2, supported: 1),
      ),
    );

    await provider.load();

    expect(provider.status, LoadStatus.failure);
    expect(provider.needsAppUpdate, isTrue);
  });

  test('load() can be retried after a failure', () async {
    final source = _StubSource(error: Exception('boom'));
    final provider = PanelProvider(source);

    await provider.load();
    expect(provider.status, LoadStatus.failure);

    await provider.load();
    expect(source.panelCalls, 2);
  });

  test(
    'a cachedPanel() that throws degrades to no cache, never breaks load()',
    () async {
      // The interface mandates null and the in-package implementation is
      // throw-proof, but a third-party ResourceDataSource might not be —
      // a broken cache read must never break the app.
      final provider = PanelProvider(
        _StubSource(
          cachedPanelError: StateError('broken host cache'),
          panelResult: _panel,
        ),
      );
      final seen = <LoadStatus>[];
      provider.addListener(() => seen.add(provider.status));

      await provider.load();

      expect(seen, [LoadStatus.loading, LoadStatus.success]);
      expect(provider.panel!.title, 'لوحة التحكم');
    },
  );

  group('cold start with a cached panel', () {
    test('publishes the cached panel before the network resolves', () async {
      final source = _StubSource(
        cachedPanelResult: _panel,
        panelResult: _panel,
      );
      source.holdNextPanel();
      final provider = PanelProvider(source);

      final pending = provider.load();

      // Flushes every microtask the cache read and the cache-publish notify
      // need, without letting panel() (held on a Completer) resolve.
      await Future<void>.delayed(Duration.zero);

      expect(provider.status, LoadStatus.success);
      expect(provider.panel!.title, 'لوحة التحكم');

      source.completeHeldPanel(_panel);
      await pending;
    });

    test(
      'a revalidation returning the same schema keeps the panel and never flips to loading',
      () async {
        final source = _StubSource(
          cachedPanelResult: _panel,
          panelResult: _panel,
        );
        final provider = PanelProvider(source);
        final seen = <LoadStatus>[];
        provider.addListener(() => seen.add(provider.status));

        await provider.load();

        expect(seen, isNot(contains(LoadStatus.loading)));
        expect(provider.status, LoadStatus.success);
        expect(provider.panel!.title, 'لوحة التحكم');
      },
    );

    test('a revalidation returning a different schema replaces it', () async {
      final source = _StubSource(
        cachedPanelResult: _panel,
        panelResult: _otherPanel,
      );
      final provider = PanelProvider(source);

      await provider.load();

      expect(provider.status, LoadStatus.success);
      expect(provider.panel!.title, 'محدث');
    });

    test(
      'a revalidation failure keeps the cached panel and does not enter failure',
      () async {
        final source = _StubSource(
          cachedPanelResult: _panel,
          error: Exception('تعذّر الاتصال'),
        );
        final provider = PanelProvider(source);
        final seen = <LoadStatus>[];
        provider.addListener(() => seen.add(provider.status));

        await provider.load();

        expect(provider.status, LoadStatus.success);
        expect(provider.panel!.title, 'لوحة التحكم');
        expect(provider.errorMessage, isNull);
        expect(seen, isNot(contains(LoadStatus.failure)));
        expect(seen, isNot(contains(LoadStatus.loading)));
      },
    );

    test(
      'an unsupported schema version during revalidation still surfaces needsAppUpdate, even with a cache published',
      () async {
        final source = _StubSource(
          cachedPanelResult: _panel,
          error: const UnsupportedSchemaVersionException(
            found: 2,
            supported: 1,
          ),
        );
        final provider = PanelProvider(source);

        await provider.load();

        expect(provider.status, LoadStatus.failure);
        expect(provider.needsAppUpdate, isTrue);
      },
    );

    // Judgement call — see task-5-report.md: unlike a generic revalidation
    // failure, a 401 must still surface `isUnauthenticated`, because the
    // screens only ever check `isUnauthenticated` once `status.isFailure` is
    // true (see e.g. panel_index_screen.dart). Leaving status at `success`
    // here would make the flag unreachable and keep a signed-out user
    // looking at a panel they no longer have access to.
    test(
      'a 401 during revalidation still marks unauthenticated, even with a cache published',
      () async {
        final source = _StubSource(
          cachedPanelResult: _panel,
          error: const FilamentTransportException('غير مصرح', statusCode: 401),
        );
        final provider = PanelProvider(source);

        await provider.load();

        expect(provider.status, LoadStatus.failure);
        expect(provider.isUnauthenticated, isTrue);
      },
    );
  });

  test('a cold failure with no cache still enters failure, as today', () async {
    final source = _StubSource(error: Exception('تعذّر الاتصال'));
    final provider = PanelProvider(source);

    await provider.load();

    expect(provider.status, LoadStatus.failure);
    expect(provider.errorMessage, contains('تعذّر الاتصال'));
  });
}

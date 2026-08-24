import 'dart:io';

import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_example/http_filament_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in only, like live_reorder_test.dart: proves the full P24 filter
/// slice against a real panel — the schema publishes the three filter kinds
/// the host's ArticlesTable now declares (`SelectFilter`, `TernaryFilter`,
/// `TrashedFilter`), a `SelectFilter` value actually narrows the list, and
/// a `TrashedFilter` reaches rows the default list hides — read-only, so
/// there is nothing to restore afterwards.
///
/// ```
/// FILAMENT_LIVE_BASE_URL=http://filament-mobile-host.test \
/// FILAMENT_LIVE_TOKEN=<a real Sanctum bearer token> \
/// FILAMENT_LIVE_FILTERS_RESOURCE=articles \
/// flutter test test/live_filters_test.dart
/// ```
void main() {
  final baseUrl = Platform.environment['FILAMENT_LIVE_BASE_URL'];
  final token = Platform.environment['FILAMENT_LIVE_TOKEN'];
  final key =
      Platform.environment['FILAMENT_LIVE_FILTERS_RESOURCE'] ?? 'articles';

  test('exercises every published filter kind against a live host', () async {
    if (baseUrl == null || token == null) {
      markTestSkipped('FILAMENT_LIVE_BASE_URL / FILAMENT_LIVE_TOKEN not set.');
      return;
    }

    final source = RestResourceDataSource(
      transport: HttpFilamentTransport(baseUrl: baseUrl, token: () => token),
    );

    // /schema publishes all three filter kinds the host declares: a plain
    // SelectFilter (status), a TernaryFilter (featured) and a TrashedFilter
    // (trashed) — each shapes to a 'select' node per FilterDeclaration.
    // containsAll rather than an exact set: the point is "these three
    // kinds publish", not "nothing else does" — an unrelated filter added
    // to the host later must not fail a test about this one.
    final panel = await source.panel();
    final resource = panel.resource(key);
    expect(resource, isNotNull, reason: '$key must be a published resource');
    expect(
      resource!.filters.map((f) => f.name),
      containsAll(['status', 'featured', 'trashed']),
      reason:
          '$key must publish status/featured/trashed filter nodes — '
          'seed them on the host\'s table() before running this test',
    );

    // Shape, not just presence — a regression that published the right
    // names with the wrong contents would still pass a bare name check.
    // Read off the RAW /schema JSON, not the parsed SelectComponent: the
    // client model does not carry `config.placeholder` through today (a
    // pre-existing gap, out of scope here), so the placeholder claim can
    // only be pinned against the wire document itself.
    final rawTransport = HttpFilamentTransport(
      baseUrl: baseUrl,
      token: () => token,
    );
    final rawSchema = await rawTransport.get('/api/mobile-panel/schema');
    final rawResources = rawSchema['resources'] as List;
    final rawResource = rawResources.cast<Map<String, dynamic>>().firstWhere(
      (r) => r['key'] == key,
    );
    final rawFilters = (rawResource['filters'] as List)
        .cast<Map<String, dynamic>>();
    Map<String, dynamic> rawFilter(String name) =>
        rawFilters.firstWhere((f) => f['name'] == name);

    final statusOptions = (rawFilter('status')['config']['options'] as List)
        .cast<Map<String, dynamic>>()
        .map((o) => o['value'])
        .toSet();
    expect(statusOptions, {'draft', 'review', 'published'});

    final featuredConfig = rawFilter('featured')['config'] as Map;
    final featuredOptions = (featuredConfig['options'] as List)
        .cast<Map<String, dynamic>>()
        .map((o) => o['value'])
        .toSet();
    expect(featuredOptions, {'1', '0'});
    expect(featuredConfig['placeholder'], isNotNull);

    // filter[status]=draft narrows the list to draft rows only.
    final draftOnly = await source.list(key, filters: {'status': 'draft'});
    expect(draftOnly.records, isNotEmpty);
    expect(
      draftOnly.records.every((r) => r.attributes['status'] == 'draft'),
      isTrue,
      reason: 'every record filter[status]=draft returns must be a draft',
    );

    // filter[trashed]=1 (with_trashed) unions in the soft-deleted rows —
    // the total must grow past the default (excludes-trashed) list.
    final defaultList = await source.list(key);
    final withTrashed = await source.list(key, filters: {'trashed': '1'});
    expect(
      withTrashed.meta.total,
      greaterThan(defaultList.meta.total),
      reason:
          'filter[trashed]=1 must widen the list past the default, which '
          'excludes trashed rows — seed at least one soft-deleted $key '
          'row on the host before running this test',
    );

    // filter[trashed]=0 (only_trashed) isolates the soft-deleted rows.
    // isNotEmpty alone would pass even if the filter silently fell back to
    // the default (non-trashed) list — that list is always non-empty too
    // — so pin it with arithmetic only the real partition satisfies:
    // "only trashed" must be exactly "with trashed" minus "without".
    final onlyTrashed = await source.list(key, filters: {'trashed': '0'});
    expect(
      onlyTrashed.records,
      isNotEmpty,
      reason:
          'seed at least one soft-deleted $key row on the host before '
          'running this test',
    );
    expect(
      onlyTrashed.meta.total,
      withTrashed.meta.total - defaultList.meta.total,
      reason:
          'filter[trashed]=0 must isolate exactly the rows filter[trashed]=1 '
          'adds over the default list — a fallback to the default list '
          'would still be non-empty but would fail this arithmetic',
    );

    // The actual claim this endpoint pair exists to prove: a trashed
    // record is hidden from the default list but reachable by id.
    // Comparing against the SAME page default_list already fetched (not a
    // full-list re-fetch) still catches a silent fallback: if
    // filter[trashed]=0 broke and returned the default list's own page 1
    // instead, its first id would trivially be a member of defaultList's
    // page too.
    final defaultIds = defaultList.records.map((r) => r.id).toSet();
    final trashedId = onlyTrashed.records.first.id;
    expect(
      defaultIds.contains(trashedId),
      isFalse,
      reason:
          'a filter[trashed]=0 record must not appear in the default '
          '(excludes-trashed) list',
    );

    // Fetching it directly by id must still 200, proving the detail
    // endpoint (show()) does not apply the list's default trashed-
    // exclusion the way the list endpoint does.
    final trashedRecord = await source.record(key, trashedId);
    expect(trashedRecord.id, trashedId);
  });
}

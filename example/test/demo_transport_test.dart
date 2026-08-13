import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_example/demo_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo schema parses into two groups and five resources', () async {
    final source = RestResourceDataSource(transport: DemoTransport());
    final panel = await source.panel();

    // Five resources, two groups: `reviews` is the child resource behind the
    // products relation — published so that relation is WRITABLE — and it is
    // deliberately absent from `navigation`, because a resource reachable only
    // through its parent has no business as a top-level index entry. The two
    // counts disagreeing is the point, so both are asserted.
    expect(panel.resources, hasLength(5));
    expect(panel.navigation.map((g) => g.group), ['Shop', 'People']);
    expect(panel.resource('reviews'), isNotNull);
    expect(
      panel.navigation.expand((g) => g.resources),
      isNot(contains('reviews')),
    );
  });

  test('products list and record round-trip', () async {
    final source = RestResourceDataSource(transport: DemoTransport());
    final page = await source.list('products');

    expect(page.records, isNotEmpty);
    final record = await source.record('products', page.records.first.id);
    expect(record.get('name'), isNotNull);
  });

  test('every screen the demo can show renders in the panel\'s own '
      'direction', () async {
    // Whole-branch review, Important 4: `/dashboard` carries its own
    // `direction` (Task 4b made it the dashboard's own carrier rather than a
    // host parameter), and the demo payload never set it — so
    // `DEMO_SCREEN=dashboard` produced an LTR screenshot of an `ar` panel
    // while `task-6-report.md` claimed all four modes render RTL. Nothing in
    // the example suite touched the demo's direction at all, which is how a
    // docs-only task broke it silently.
    final source = RestResourceDataSource(transport: DemoTransport());

    final panel = await source.panel();
    final dashboard = await source.dashboard();

    expect(panel.direction, PanelDirection.rtl);
    expect(
      dashboard.direction,
      panel.direction,
      reason:
          'the dashboard is its own direction carrier — an Arabic panel '
          'whose dashboard answers ltr renders one screen the wrong way '
          'round',
    );
  });

  test('uploadFile returns a fake stored path under the filename', () async {
    final source = RestResourceDataSource(transport: DemoTransport());

    final result = await source.uploadFile(
      'products',
      'photo',
      bytes: const [1, 2, 3],
      filename: 'photo.png',
    );

    expect(result, isA<UploadSuccess>());
    expect((result as UploadSuccess).path, 'demo/photo.png');
  });
}

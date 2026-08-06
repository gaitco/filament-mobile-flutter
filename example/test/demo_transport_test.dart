import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_example/demo_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo schema parses into two groups and four resources', () async {
    final source = RestResourceDataSource(transport: DemoTransport());
    final panel = await source.panel();

    expect(panel.resources, hasLength(4));
    expect(panel.navigation.map((g) => g.group), ['Shop', 'People']);
  });

  test('products list and record round-trip', () async {
    final source = RestResourceDataSource(transport: DemoTransport());
    final page = await source.list('products');

    expect(page.records, isNotEmpty);
    final record = await source.record('products', page.records.first.id);
    expect(record.get('name'), isNotNull);
  });
}

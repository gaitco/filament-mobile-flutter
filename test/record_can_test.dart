import 'package:filament_mobile/data/record_can.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The bug this prevents: asking a RESOURCE whether it may delete, and
  // getting "yes, this resource supports deletion" back as though it meant
  // "yes, you may delete THIS row". Under an ownership policy those disagree
  // for most records. The signature makes the confusion unrepresentable —
  // passing a ResourceSchema is a compile error, so there is no runtime test
  // for that half, by design.
  test('reads the per-record block', () {
    const record = ResourceRecord(id: 1, permissions: {'delete': true});
    expect(recordCan(record, 'delete'), isTrue);
  });

  test('an absent ability is denied, never assumed', () {
    const record = ResourceRecord(id: 1, permissions: {'view': true});
    expect(recordCan(record, 'delete'), isFalse);
  });

  test('a record from the list endpoint denies everything', () {
    // The list endpoint does not compute per-record permissions, so its
    // records carry an empty block. Defaulting those to "allowed" would show
    // a delete button on every row in a list.
    const record = ResourceRecord(id: 1);
    expect(recordCan(record, 'delete'), isFalse);
  });
}

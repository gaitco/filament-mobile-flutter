import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses items and prefers thumbUrl for display', () {
    final set = MediaSet.fromJson(const [
      {
        'uuid': 'u1',
        'url': 'https://x/a.jpg',
        'thumbUrl': 'https://x/t.jpg',
        'name': 'a.jpg',
        'size': 10,
        'mime': 'image/jpeg',
      },
      {'uuid': 'u2', 'url': 'https://x/b.jpg', 'thumbUrl': null},
    ], 'photos.__media');

    expect(set.items, hasLength(2));
    expect(set.items.first.displayUrl, 'https://x/t.jpg');
    expect(set.items.last.displayUrl, 'https://x/b.jpg');
  });

  test('drops a malformed item instead of throwing', () {
    final set = MediaSet.fromJson(const [
      {'uuid': 'u1', 'url': 'https://x/a.jpg'},
      {'name': 'no-uuid.jpg'},
      'not-a-map',
    ], 'photos.__media');

    expect(set.items, hasLength(1));
  });

  test('of() reads the flat sibling and answers null when absent', () {
    final record = ResourceRecord.fromJson(const {
      'id': 1,
      'photos': ['u1'],
      'photos.__media': [
        {'uuid': 'u1', 'url': 'https://x/a.jpg'},
      ],
    }, 'id');

    expect(MediaSet.of(record, 'photos')!.items.single.uuid, 'u1');
    expect(MediaSet.of(record, 'cover'), isNull);
  });

  test('of() answers null when the sibling is not a list', () {
    final record = ResourceRecord.fromJson(const {
      'id': 1,
      'cover': 'u1',
      'cover.__media': 'not-a-list',
      'poster': 'u2',
      'poster.__media': {'uuid': 'u2', 'url': 'https://x/p.jpg'},
    }, 'id');

    expect(MediaSet.of(record, 'cover'), isNull);
    expect(MediaSet.of(record, 'poster'), isNull);
  });
}

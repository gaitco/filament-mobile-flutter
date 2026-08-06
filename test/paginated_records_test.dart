import 'package:filament_mobile/data/paginated_records.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PageMeta', () {
    test('parses the contract meta shape', () {
      final meta = PageMeta.fromJson(const {
        'current_page': 1,
        'last_page': 4,
        'per_page': 20,
        'total': 68,
      });

      expect(meta.currentPage, 1);
      expect(meta.lastPage, 4);
      expect(meta.perPage, 20);
      expect(meta.total, 68);
    });

    test('hasMore is true until the last page', () {
      PageMeta at(int page, int last) =>
          PageMeta(currentPage: page, lastPage: last, perPage: 20, total: 68);

      expect(at(1, 4).hasMore, isTrue);
      expect(at(3, 4).hasMore, isTrue);
      expect(at(4, 4).hasMore, isFalse);
    });

    test('a single-page result has no more', () {
      expect(
        PageMeta.fromJson(const {
          'current_page': 1,
          'last_page': 1,
          'per_page': 20,
          'total': 3,
        }).hasMore,
        isFalse,
      );
    });

    test('missing meta keys default to a safe single page', () {
      final meta = PageMeta.fromJson(const {});

      expect(meta.currentPage, 1);
      expect(meta.lastPage, 1);
      expect(meta.hasMore, isFalse);
    });
  });
}

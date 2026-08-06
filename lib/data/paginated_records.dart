import 'package:equatable/equatable.dart';

import 'resource_record.dart';

/// The `meta` block of a list response.
///
/// Missing keys default to a single complete page: a client that cannot tell
/// how many pages there are must not scroll forever asking for more.
class PageMeta extends Equatable {
  const PageMeta({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  factory PageMeta.fromJson(Map<String, dynamic> json) {
    int read(String key, int fallback) {
      final value = json[key];
      return value is int ? value : fallback;
    }

    return PageMeta(
      currentPage: read('current_page', 1),
      lastPage: read('last_page', 1),
      perPage: read('per_page', 0),
      total: read('total', 0),
    );
  }

  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  bool get hasMore => currentPage < lastPage;

  @override
  List<Object?> get props => [currentPage, lastPage, perPage, total];
}

class PaginatedRecords extends Equatable {
  const PaginatedRecords({required this.records, required this.meta});

  final List<ResourceRecord> records;
  final PageMeta meta;

  @override
  List<Object?> get props => [records, meta];
}

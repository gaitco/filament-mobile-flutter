import 'dart:convert';

import 'package:filament_mobile/ports/filament_transport.dart';

import 'contract_goldens.dart';

/// Serves the real Laravel output committed at `contract/laravel-panel.json`.
///
/// The path is relative because `flutter test` runs with the package directory
/// as its working directory.
class GoldenTransport implements FilamentTransport {
  GoldenTransport({this.rows = const []});

  final List<Map<String, dynamic>> rows;

  static Map<String, dynamic> get panelJson =>
      jsonDecode(contractFile('laravel-panel.json').readAsStringSync())
          as Map<String, dynamic>;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    if (path.endsWith('/schema')) return panelJson;

    final segments = path.split('/');
    final isRecord = segments.length > 3;

    if (isRecord) {
      return {
        'data': rows.isEmpty ? {'id': 1} : rows.first,
        'permissions': const {'view': true, 'update': false, 'delete': false},
      };
    }

    return {
      'data': rows,
      'meta': {
        'current_page': 1,
        'last_page': 1,
        'per_page': 20,
        'total': rows.length,
      },
    };
  }

  @override
  Future<FilamentResponse> post(String path, Map<String, dynamic> body) =>
      throw UnimplementedError('GoldenTransport is read-only');

  @override
  Future<FilamentResponse> put(String path, Map<String, dynamic> body) =>
      throw UnimplementedError('GoldenTransport is read-only');

  @override
  Future<FilamentResponse> delete(String path) =>
      throw UnimplementedError('GoldenTransport is read-only');
}

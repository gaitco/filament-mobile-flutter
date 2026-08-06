import 'package:filament_mobile/ports/filament_transport.dart';

/// Records every call and returns queued responses, so a test can assert the
/// exact path and query the data source built.
class FakeTransport implements FilamentTransport {
  FakeTransport(
    this._responses, {
    Map<String, FilamentResponse> writes = const {},
  }) : _writes = writes;

  final Map<String, Map<String, dynamic>> _responses;

  /// Keyed `'<METHOD> <path>'`, e.g. `'POST /api/mobile-panel/banners'`.
  final Map<String, FilamentResponse> _writes;

  final List<({String path, Map<String, dynamic>? query})> calls = [];

  Object? errorToThrow;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    calls.add((path: path, query: query));

    if (errorToThrow != null) throw errorToThrow!;

    final response = _responses[path];
    if (response == null) {
      throw StateError('FakeTransport has no response queued for `$path`');
    }
    return response;
  }

  @override
  Future<FilamentResponse> post(String path, Map<String, dynamic> body) =>
      _write('POST', path);

  @override
  Future<FilamentResponse> put(String path, Map<String, dynamic> body) =>
      _write('PUT', path);

  @override
  Future<FilamentResponse> delete(String path) => _write('DELETE', path);

  Future<FilamentResponse> _write(String method, String path) async {
    calls.add((path: path, query: null));

    if (errorToThrow != null) throw errorToThrow!;

    final key = '$method $path';
    final response = _writes[key];
    if (response == null) {
      throw StateError('FakeTransport has no response queued for `$key`');
    }
    return response;
  }
}

/// A transport whose every call throws, so a data source can be tested
/// against a genuine transport failure — no socket, DNS, timeout.
class ThrowingTransport implements FilamentTransport {
  const ThrowingTransport(this._error);

  final Object _error;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async => throw _error;

  @override
  Future<FilamentResponse> post(String path, Map<String, dynamic> body) async =>
      throw _error;

  @override
  Future<FilamentResponse> put(String path, Map<String, dynamic> body) async =>
      throw _error;

  @override
  Future<FilamentResponse> delete(String path) async => throw _error;
}

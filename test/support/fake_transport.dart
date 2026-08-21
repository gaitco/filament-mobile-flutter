import 'package:filament_mobile/ports/filament_conditional_transport.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/ports/filament_upload_transport.dart';

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

  final List<({String path, Map<String, dynamic>? query, Object? body})> calls =
      [];

  Object? errorToThrow;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    calls.add((path: path, query: query, body: null));

    if (errorToThrow != null) throw errorToThrow!;

    final response = _responses[path];
    if (response == null) {
      throw StateError('FakeTransport has no response queued for `$path`');
    }
    return response;
  }

  @override
  Future<FilamentResponse> post(String path, Map<String, dynamic> body) =>
      _write('POST', path, body);

  @override
  Future<FilamentResponse> put(String path, Map<String, dynamic> body) =>
      _write('PUT', path, body);

  @override
  Future<FilamentResponse> delete(String path) => _write('DELETE', path, null);

  /// [body] is captured on [calls] (P18) so a test can assert exactly what a
  /// write sent — e.g. `reorder()`'s `{"order": ids}` — not just that some
  /// request hit the path.
  Future<FilamentResponse> _write(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    calls.add((path: path, query: null, body: body));

    if (errorToThrow != null) throw errorToThrow!;

    final key = '$method $path';
    final response = _writes[key];
    if (response == null) {
      throw StateError('FakeTransport has no response queued for `$key`');
    }
    return response;
  }
}

/// A [FakeTransport] that also implements the optional upload port, so a
/// test can drive `uploadFile()` all the way to a real transport call.
///
/// A second class rather than folding this onto [FakeTransport] itself: a
/// test asserting the missing-port case needs a transport that genuinely
/// does not implement [FilamentUploadTransport], and `FakeTransport is
/// FilamentUploadTransport` must stay false for that to mean anything.
class FakeUploadTransport extends FakeTransport
    implements FilamentUploadTransport {
  FakeUploadTransport(
    super.responses, {
    super.writes,
    this.uploadResponse,
    this.uploadError,
  });

  final FilamentResponse? uploadResponse;
  final Object? uploadError;

  ({String path, List<int> bytes, String filename, String field})? lastUpload;

  @override
  Future<FilamentResponse> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    String field = 'file',
  }) async {
    lastUpload = (path: path, bytes: bytes, filename: filename, field: field);

    if (errorToThrow != null) throw errorToThrow!;
    if (uploadError != null) throw uploadError!;

    final response = uploadResponse;
    if (response == null) {
      throw StateError('FakeUploadTransport has no upload response queued.');
    }
    return response;
  }
}

/// A [FakeTransport] that also implements the optional conditional-GET port,
/// so a test can drive revalidation (etag sent, 304 vs 200) all the way to a
/// real transport call.
///
/// A second class rather than folding this onto [FakeTransport] itself, same
/// reasoning as [FakeUploadTransport]: a test asserting the no-conditional-
/// port fallback needs a transport that genuinely does not implement
/// [FilamentConditionalTransport].
class FakeConditionalTransport extends FakeTransport
    implements FilamentConditionalTransport {
  FakeConditionalTransport(
    super.responses, {
    super.writes,
    Map<String, List<ConditionalResponse>>? conditionalResponses,
  }) : _conditionalResponses = {
         for (final entry in (conditionalResponses ?? const {}).entries)
           entry.key: List.of(entry.value),
       };

  final Map<String, List<ConditionalResponse>> _conditionalResponses;

  final List<({String path, String? etag})> conditionalCalls = [];

  @override
  Future<ConditionalResponse> getConditional(
    String path, {
    String? etag,
  }) async {
    conditionalCalls.add((path: path, etag: etag));

    if (errorToThrow != null) throw errorToThrow!;

    final queue = _conditionalResponses[path];
    if (queue == null || queue.isEmpty) {
      throw StateError(
        'FakeConditionalTransport has no conditional response queued for '
        '`$path`',
      );
    }
    return queue.removeAt(0);
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

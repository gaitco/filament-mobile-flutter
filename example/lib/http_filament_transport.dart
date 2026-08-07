import 'dart:convert';

import 'package:filament_mobile/filament_mobile.dart';
import 'package:http/http.dart' as http;

/// A [FilamentTransport] built on `package:http`, talking to a live panel
/// that exposes `gait/filament-mobile`'s routes.
///
/// This is a real host implementation, not a fake: every method here is
/// exactly what a production app's own networking layer would do — decode a
/// GET's body, throw on its failure, and pass a write's status straight
/// through. See [FilamentTransport]'s own doc comment for why writes and
/// reads are asymmetric.
class HttpFilamentTransport
    implements
        FilamentTransport,
        FilamentUploadTransport,
        FilamentConditionalTransport {
  HttpFilamentTransport({
    required this.baseUrl,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// e.g. `https://example.test` — no trailing slash. `RestResourceDataSource`
  /// supplies the `/api/mobile-panel` route prefix; this is the origin only.
  final String baseUrl;

  /// A Sanctum bearer token. Read fresh on every call rather than captured
  /// once, so a host that rotates it mid-session (or points this at an
  /// expired one for a pilot) does not need a new transport instance.
  final String Function() token;

  final http.Client _client;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Authorization': 'Bearer ${token()}',
  };

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query?.map((key, value) => MapEntry(key, '$value')),
    );

    final response = await _client.get(uri, headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // The one line FilamentTransportException's doc comment asks for: a
      // 401 carries its status so the read-path providers can tell "you were
      // signed out" apart from a generic server failure.
      throw FilamentTransportException(
        _messageOf(response),
        statusCode: response.statusCode,
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<ConditionalResponse> getConditional(
    String path, {
    String? etag,
  }) async {
    // Deliberately not routed through get(): get() throws on every non-2xx,
    // and a 304 is one — it would arrive there as an indistinguishable
    // thrown failure instead of the "unchanged" outcome the caller needs.
    final response = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: {..._headers, if (etag != null) 'If-None-Match': etag},
    );

    if (response.statusCode == 304) {
      return ConditionalResponse(
        notModified: true,
        etag: response.headers['etag'],
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FilamentTransportException(
        _messageOf(response),
        statusCode: response.statusCode,
      );
    }

    return ConditionalResponse(
      notModified: false,
      body: jsonDecode(response.body) as Map<String, dynamic>,
      etag: response.headers['etag'],
    );
  }

  @override
  Future<FilamentResponse> post(String path, Map<String, dynamic> body) =>
      _write(_client.post, path, body);

  @override
  Future<FilamentResponse> put(String path, Map<String, dynamic> body) =>
      _write(_client.put, path, body);

  @override
  Future<FilamentResponse> delete(String path) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
    );

    return FilamentResponse(
      statusCode: response.statusCode,
      // A 204's empty body must decode as `{}`, not go through jsonDecode —
      // see FilamentTransport.delete's doc comment; an empty string throws.
      body: response.body.isEmpty
          ? const {}
          : jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<FilamentResponse> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    String field = 'file',
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll(_headers)
      ..fields['field'] = field
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

    final response = await http.Response.fromStream(
      await _client.send(request),
    );

    return FilamentResponse(
      statusCode: response.statusCode,
      body: response.body.isEmpty
          ? const {}
          : jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Shared by [post] and [put] — same headers, same JSON body, same
  /// pass-through-the-status response shape.
  Future<FilamentResponse> _write(
    Future<http.Response> Function(
      Uri url, {
      Map<String, String>? headers,
      Object? body,
      Encoding? encoding,
    })
    method,
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await method(
      Uri.parse('$baseUrl$path'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    return FilamentResponse(
      statusCode: response.statusCode,
      body: response.body.isEmpty
          ? const {}
          : jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  String _messageOf(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } on FormatException {
      // Not JSON — the generic message below is the answer.
    }

    return 'Request to $baseUrl failed with status ${response.statusCode}.';
  }
}

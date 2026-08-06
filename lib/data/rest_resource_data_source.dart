import '../ports/filament_transport.dart';
import '../schema/panel_schema.dart';
import '../schema/resource_schema.dart';
import '../schema/schema_component.dart';
import 'options_page.dart';
import 'paginated_records.dart';
import 'resource_data_source.dart';
import 'resource_record.dart';
import 'write_result.dart';

/// Talks to `gait/filament-mobile` over a host-supplied [FilamentTransport].
///
/// Caches the panel document, because every list and record call needs its
/// resource's `recordKey` and the document changes far less often than a list
/// is scrolled.
class RestResourceDataSource implements ResourceDataSource {
  RestResourceDataSource({
    required FilamentTransport transport,
    String prefix = '/api/mobile-panel',
  }) : _transport = transport,
       prefix = _normalisePrefix(prefix);

  /// Exactly one leading slash, no trailing one — unless the host handed us a
  /// whole URL, which is passed through with only its trailing slash removed.
  ///
  /// A host's base URL conventionally has no trailing slash (Dio's own), so a
  /// relative prefix concatenates into `example.comapi/...` — a DNS failure on
  /// the very first request rather than an HTTP error.
  ///
  /// The absolute case is not hypothetical: a host whose HTTP client has no
  /// base URL, or whose panel lives on a different host from its API, passes
  /// the full origin here. Prefixing `https://example.com/api` with a slash
  /// turns it into the relative path `/https:/example.com/api`, and every
  /// request 404s against the host's own origin.
  static String _normalisePrefix(String prefix) {
    final trimmed = prefix.trim().replaceAll(RegExp(r'/+$'), '');
    // An empty prefix must stay empty: forcing a slash onto it builds
    // `//schema`, which some servers route and some 404.
    if (trimmed.isEmpty) return '';
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed)) {
      return trimmed;
    }
    return '/${trimmed.replaceAll(RegExp(r'^/+'), '')}';
  }

  final FilamentTransport _transport;
  final String prefix;

  PanelSchema? _panel;

  @override
  Future<PanelSchema> panel() async {
    return _panel ??= PanelSchema.fromJson(
      await _transport.get('$prefix/schema'),
    );
  }

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async {
    final resource = await _resource(resourceKey);

    // Absent parameters are omitted rather than sent as null: the server
    // rejects an unknown sort key with a 422, and an empty `search` would
    // otherwise be a search for nothing.
    final response = await _transport.get(
      '$prefix/$resourceKey',
      query: {
        'page': '$page',
        if (search != null && search.trim().isNotEmpty) 'search': search,
        if (sort != null && sort.trim().isNotEmpty) 'sort': sort,
        if (direction != null && direction.trim().isNotEmpty)
          'direction': direction,
      },
    );

    final rows = response['data'];
    final meta = response['meta'];

    return PaginatedRecords(
      records: [
        if (rows is List)
          for (final row in rows)
            if (row is Map<String, dynamic>)
              ResourceRecord.fromJson(row, resource.recordKey),
      ],
      meta: PageMeta.fromJson(meta is Map<String, dynamic> ? meta : const {}),
    );
  }

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async {
    final resource = await _resource(resourceKey);

    final response = await _transport.get('$prefix/$resourceKey/$id');

    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Record response for `$resourceKey/$id` has no data.');
    }

    final permissions = response['permissions'];

    return ResourceRecord.fromJson(
      data,
      resource.recordKey,
      permissions: permissions is Map<String, dynamic> ? permissions : null,
    );
  }

  @override
  Future<WriteResult> create(
    String resourceKey,
    Map<String, dynamic> values,
  ) async {
    try {
      return _interpret(await _transport.post('$prefix/$resourceKey', values));
    } catch (e) {
      return WriteFailed(messageOf(e));
    }
  }

  @override
  Future<WriteResult> update(
    String resourceKey,
    Object id,
    Map<String, dynamic> values,
  ) async {
    try {
      return _interpret(
        await _transport.put('$prefix/$resourceKey/$id', values),
      );
    } catch (e) {
      return WriteFailed(messageOf(e));
    }
  }

  @override
  Future<WriteResult> destroy(String resourceKey, Object id) async {
    try {
      return _interpret(await _transport.delete('$prefix/$resourceKey/$id'));
    } catch (e) {
      return WriteFailed(messageOf(e));
    }
  }

  @override
  Future<List<SchemaComponent>> state(
    String resourceKey, {
    Object? recordId,
    required Map<String, dynamic> values,
    required String changed,
  }) async {
    final response = await _transport.post('$prefix/$resourceKey/state', {
      'record_id': recordId,
      'state': values,
      'changed': changed,
    });

    // Unlike the writes, `state()` has no data-carrying failure outcome to
    // return — its contract is "the current form", not a result union — so a
    // non-2xx throws here exactly as `get()` does, rather than silently
    // parsing an error body's absent `components` key as an empty form.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FilamentTransportException(_messageOf(response.body));
    }

    return SchemaComponent.listFromJson(
      response.body,
      'components',
      '$resourceKey/state',
    );
  }

  @override
  Future<OptionsPage> options(
    String resourceKey, {
    required String field,
    Object? recordId,
    required Map<String, dynamic> values,
    required String query,
  }) async {
    final response = await _transport.post('$prefix/$resourceKey/options', {
      'field': field,
      'record_id': recordId,
      'state': values,
      'q': query,
    });

    // Like `state()` and unlike the writes: there is no data-carrying failure
    // outcome to return, so a non-2xx throws rather than letting an error
    // body's absent `options` key parse as "this select has none" — a silently
    // empty picker is indistinguishable from a genuine empty result.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FilamentTransportException(_messageOf(response.body));
    }

    final raw = response.body['options'];

    return OptionsPage(
      options: [
        if (raw is List)
          for (final entry in raw)
            if (entry is Map<String, dynamic> && entry['value'] != null)
              SelectOption(
                value: entry['value'] as Object,
                label: '${entry['label'] ?? entry['value']}',
              ),
      ],
      hasMore: response.body['hasMore'] == true,
    );
  }

  WriteResult _interpret(FilamentResponse response) {
    final body = response.body;

    return switch (response.statusCode) {
      >= 200 && < 300 => WriteSuccess(
        body['data'] is Map<String, dynamic>
            ? body['data'] as Map<String, dynamic>
            : const {},
      ),
      422 => WriteInvalid(_errorsOf(body)),
      403 => WriteDenied(_messageOf(body)),
      404 => WriteGone(_messageOf(body)),
      _ => WriteFailed(_messageOf(body)),
    };
  }

  /// Laravel's shape is `{"errors": {"field": ["message"]}}`. Anything else
  /// degrades to no field errors: a malformed body must not turn a recoverable
  /// validation failure into a dead form.
  Map<String, List<String>> _errorsOf(Map<String, dynamic> body) {
    final errors = body['errors'];
    if (errors is! Map<String, dynamic>) return const {};

    return {
      for (final entry in errors.entries)
        if (entry.value is List)
          entry.key: [for (final message in entry.value as List) '$message'],
    };
  }

  String _messageOf(Map<String, dynamic> body) {
    final message = body['message'];
    return message is String && message.isNotEmpty ? message : '';
  }

  Future<ResourceSchema> _resource(String key) async {
    final resource = (await panel()).resource(key);

    if (resource == null) {
      throw StateError(
        'Resource `$key` is not in the panel. Either it declares no mobile() '
        'on the server, or the current user may not view it.',
      );
    }

    return resource;
  }
}

import '../dashboard/dashboard_data.dart';
import '../ports/filament_schema_cache.dart';
import '../ports/filament_transport.dart';
import '../ports/filament_upload_transport.dart';
import '../schema/panel_schema.dart';
import '../schema/relation_descriptor.dart';
import '../schema/resource_schema.dart';
import '../schema/schema_component.dart';
import 'action_result.dart';
import 'options_page.dart';
import 'paginated_records.dart';
import 'resource_data_source.dart';
import 'resource_record.dart';
import 'schema_cache_store.dart';
import 'upload_result.dart';
import 'write_result.dart';

/// Talks to `gait/filament-mobile` over a host-supplied [FilamentTransport].
///
/// Caches the panel document in memory for the life of this instance,
/// because every list and record call needs its resource's `recordKey` and
/// the document changes far less often than a list is scrolled. Optionally
/// also persists it across restarts and revalidates it with a conditional
/// GET — see [cache] and [cacheKey] — through a [SchemaCacheStore].
class RestResourceDataSource implements ResourceDataSource {
  RestResourceDataSource({
    required FilamentTransport transport,
    String prefix = '/api/mobile-panel',
    FilamentSchemaCache? cache,
    String? cacheKey,
  }) : this._(
         transport: transport,
         prefix: _normalisePrefix(prefix),
         cache: cache,
         cacheKey: cacheKey,
       );

  RestResourceDataSource._({
    required FilamentTransport transport,
    required this.prefix,
    FilamentSchemaCache? cache,
    String? cacheKey,
  }) : _transport = transport,
       _schemaCache = SchemaCacheStore(
         transport: transport,
         path: '$prefix/schema',
         cache: cache,
         cacheKey: cacheKey,
       );

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
  final SchemaCacheStore _schemaCache;

  PanelSchema? _panel;

  @override
  Future<PanelSchema> panel() async => _panel ??= await _schemaCache.panel();

  @override
  Future<PanelSchema?> cachedPanel() => _schemaCache.cachedPanel();

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
    final actions = response['actions'];

    return ResourceRecord.fromJson(
      data,
      resource.recordKey,
      permissions: permissions is Map<String, dynamic> ? permissions : null,
      actions: actions is List ? actions : null,
    );
  }

  /// One relation manager's rows for record [id] — the same envelope [list]
  /// parses, against the sibling URL `RelationController` serves. Unlike
  /// [list], the child rows' own key comes from [relation] itself
  /// (`relation.recordKey`), not from this resource's schema: the related
  /// model is routinely a different one, with a different route key.
  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
  }) async {
    final response = await _transport.get(
      '$prefix/$resourceKey/$id/relations/${relation.key}',
      query: {'page': '$page'},
    );

    final rows = response['data'];
    final meta = response['meta'];

    return PaginatedRecords(
      records: [
        if (rows is List)
          for (final row in rows)
            if (row is Map<String, dynamic>)
              ResourceRecord.fromJson(row, relation.recordKey),
      ],
      meta: PageMeta.fromJson(meta is Map<String, dynamic> ? meta : const {}),
    );
  }

  /// The three relation-row writes (P9) sit beside [relation], the read:
  /// same sibling URL family, same never-throw contract as
  /// [create]/[update]/[destroy] — a 4xx comes back as data and only a
  /// transport failure throws, which the `catch` folds into [WriteFailed]
  /// exactly the way those three do.
  @override
  Future<WriteResult> createRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Map<String, dynamic> values,
  ) async {
    try {
      return _interpret(
        await _transport.post(
          '$prefix/$resourceKey/$id/relations/${relation.key}',
          values,
        ),
      );
    } catch (e) {
      return WriteFailed(messageOf(e));
    }
  }

  @override
  Future<WriteResult> updateRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
    Map<String, dynamic> values,
  ) async {
    try {
      return _interpret(
        await _transport.put(
          '$prefix/$resourceKey/$id/relations/${relation.key}/$childId',
          values,
        ),
      );
    } catch (e) {
      return WriteFailed(messageOf(e));
    }
  }

  @override
  Future<WriteResult> deleteRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
  ) async {
    try {
      return _interpret(
        await _transport.delete(
          '$prefix/$resourceKey/$id/relations/${relation.key}/$childId',
        ),
      );
    } catch (e) {
      return WriteFailed(messageOf(e));
    }
  }

  @override
  Future<ActionResult> runAction(
    String resourceKey,
    Object id,
    String action,
  ) async {
    try {
      final response = await _transport.post(
        '$prefix/$resourceKey/$id/actions/$action',
        const {},
      );

      final message = response.body['message'];

      // 2xx is the only success. Every other status — 403, 404, 422, 500 —
      // is a refusal or a fault, and either leaves the record untouched
      // from the client's point of view: only a success triggers the
      // caller's re-fetch.
      return response.statusCode >= 200 && response.statusCode < 300
          ? ActionSuccess(message is String ? message : null)
          : ActionFailed(message is String ? message : null);
    } catch (e) {
      // Same contract as create/update/destroy: the transport throws on
      // socket/DNS/timeout, and a tapped button with no network must come
      // back as a failed action, never an unhandled async error.
      return ActionFailed(messageOf(e));
    }
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

  @override
  Future<DashboardData> dashboard() async =>
      DashboardData.fromJson(await _transport.get('$prefix/dashboard'));

  @override
  Future<UploadResult> uploadFile(
    String resourceKey,
    String field, {
    required List<int> bytes,
    required String filename,
  }) async {
    // Capability is detected, not assumed: a host that never implemented
    // the optional upload port gets an actionable message, not a crash or
    // a silent no-op — this is also the signal Task 6's form field reads
    // to stay read-only.
    //
    // `FilamentUploadTransport` is a sibling interface, not a subtype of
    // `FilamentTransport`, so Dart cannot promote `_transport` from the
    // `is!` check below — the explicit cast is required, not decorative.
    if (_transport is! FilamentUploadTransport) {
      return const UploadFailed(
        'This host transport does not implement FilamentUploadTransport, '
        'so files cannot be uploaded. Implement it alongside '
        'FilamentTransport to enable this field.',
      );
    }
    final transport = _transport as FilamentUploadTransport;

    try {
      final response = await transport.upload(
        '$prefix/$resourceKey/upload',
        bytes: bytes,
        filename: filename,
        field: field,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final path = response.body['path'];
        return path is String
            ? UploadSuccess(path)
            : UploadFailed(
                'Upload succeeded but the server sent no path.',
                statusCode: response.statusCode,
              );
      }

      final message = response.body['message'];
      return UploadFailed(
        message is String ? message : null,
        statusCode: response.statusCode,
      );
    } catch (e) {
      // Same contract as create/update/destroy: the transport throws on
      // socket/DNS/timeout, and an offline upload must come back as a
      // failed result, never an unhandled async error.
      return UploadFailed(messageOf(e));
    }
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

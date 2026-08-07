import '../dashboard/dashboard_data.dart';
import '../schema/panel_schema.dart';
import '../schema/relation_descriptor.dart';
import 'action_result.dart';
import 'options_page.dart';
import '../schema/schema_component.dart';
import 'paginated_records.dart';
import 'resource_record.dart';
import 'upload_result.dart';
import 'write_result.dart';

/// Everything the screens need from the server.
///
/// Abstract so tests can drive the screens from a fake without a transport,
/// and so a host could substitute a cached or offline implementation later.
abstract interface class ResourceDataSource {
  /// GET /schema
  Future<PanelSchema> panel();

  /// The cached panel, if there is a usable one — parsed, never rendered
  /// from bytes this build cannot read.
  ///
  /// Never touches the network: a cache hit or miss is a storage question,
  /// not a server one. A cold start calls this first to paint immediately,
  /// then calls [panel] as usual to revalidate behind it. Implementations
  /// with no cache configured return `null` unconditionally.
  Future<PanelSchema?> cachedPanel();

  /// GET /{resource}
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page,
    String? search,
    String? sort,
    String? direction,
  });

  /// GET /{resource}/{id} — the only call that returns per-record permissions.
  Future<ResourceRecord> record(String resourceKey, Object id);

  /// GET /{resource}/{id}/relations/{relation} — one relation manager's child
  /// rows, in the same `{data, meta}` envelope [list] uses. The same read
  /// path as [list] against a sibling URL, so it is fetched the same way:
  /// through this data source, never a closure a host has to hand-wire.
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page,
  });

  /// POST /{resource} — never throws on a 4xx; see [WriteResult].
  Future<WriteResult> create(String resourceKey, Map<String, dynamic> values);

  /// PUT /{resource}/{id} — never throws on a 4xx; see [WriteResult].
  Future<WriteResult> update(
    String resourceKey,
    Object id,
    Map<String, dynamic> values,
  );

  /// DELETE /{resource}/{id} — never throws on a 4xx; see [WriteResult].
  Future<WriteResult> destroy(String resourceKey, Object id);

  /// POST /{resource}/{id}/actions/{action} — runs one of the record's own
  /// [RecordAction]s. Never throws on a 4xx or 5xx; see [ActionResult].
  ///
  /// The caller re-fetches the record on success only: the action may have
  /// changed fields, permissions or the action list itself, and this method
  /// carries none of that back — only whether it ran. A failure leaves the
  /// record untouched, so there is nothing to re-fetch.
  Future<ActionResult> runAction(String resourceKey, Object id, String action);

  /// POST /{resource}/options — the options for a select whose list `/schema`
  /// refused to inline.
  ///
  /// [values] carries the form's current state because options depend on
  /// siblings: a pilot measured a dependent picker narrowing 6 -> 2 -> 1 as its
  /// parent changed. Sending an empty map makes every dependent select wrong.
  Future<OptionsPage> options(
    String resourceKey, {
    required String field,
    Object? recordId,
    required Map<String, dynamic> values,
    required String query,
  });

  /// POST /{resource}/state — re-evaluates the form against values typed but
  /// not yet submitted, so `visible`/`disabled`/`hidden` closures answer on
  /// mobile exactly as they do in the web panel.
  Future<List<SchemaComponent>> state(
    String resourceKey, {
    Object? recordId,
    required Map<String, dynamic> values,
    required String changed,
  });

  /// GET /dashboard — the panel's widgets, values already computed.
  ///
  /// Values are live: they are not cached the way [panel] is, and a re-read
  /// re-runs the panel's own queries, so pull-to-refresh always shows the
  /// current numbers rather than a stale snapshot.
  Future<DashboardData> dashboard();

  /// POST /{resource}/upload — uploads a file for a single-file upload
  /// field. [field] is the field's statePath, so a nested field is
  /// addressable.
  ///
  /// Fails with [UploadFailed] rather than throwing, including when the
  /// host's transport has not implemented the optional
  /// `FilamentUploadTransport` port — the same never-throw contract every
  /// other write has.
  Future<UploadResult> uploadFile(
    String resourceKey,
    String field, {
    required List<int> bytes,
    required String filename,
  });
}

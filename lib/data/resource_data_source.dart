import '../schema/panel_schema.dart';
import 'action_result.dart';
import 'options_page.dart';
import '../schema/schema_component.dart';
import 'paginated_records.dart';
import 'resource_record.dart';
import 'write_result.dart';

/// Everything the screens need from the server.
///
/// Abstract so tests can drive the screens from a fake without a transport,
/// and so a host could substitute a cached or offline implementation later.
abstract interface class ResourceDataSource {
  /// GET /schema
  Future<PanelSchema> panel();

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
}

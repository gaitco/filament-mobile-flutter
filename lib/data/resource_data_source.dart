import '../dashboard/dashboard_data.dart';
import '../schema/panel_schema.dart';
import '../schema/relation_descriptor.dart';
import 'action_result.dart';
import 'options_page.dart';
import 'panel_notification.dart';
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
  ///
  /// [reorder]: true switches to the full, unpaginated, reorder-ordered list
  /// — `?reorder=1` — and [sort]/[direction] are omitted from the request
  /// entirely, mirroring the server's own contract (P18): reorder mode
  /// discards the sort column outright, the same way Filament's own
  /// reorder-mode table does. [search] still applies in this mode.
  ///
  /// [filters] (P24): name => `String` (single value) or `List<String>`
  /// (multiple). Encoded on the wire as INDEXED keys —
  /// `filter[tags][0]=a&filter[tags][1]=b` — never repeated ones
  /// (`filter[tags][]=a&...`). [FilamentTransport.get] hands the host a FLAT
  /// map, and the reference host stringifies every value
  /// (`example/lib/http_filament_transport.dart`), so a `List<String>` value
  /// would go out as the literal `"[a, b]"`. Distinct indexed keys stay
  /// scalar strings — no change needed to the port or to any host — and PHP
  /// parses `filter[tags][0]`/`filter[tags][1]` into the same array
  /// `filter[tags][]` would have produced. The server accepts both forms;
  /// this client sends only the indexed one. Do not "simplify" this to
  /// repeated keys — that silently breaks multiple filters.
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page,
    String? search,
    String? sort,
    String? direction,
    bool reorder,
    Map<String, Object?> filters,
  });

  /// GET /{resource}/{id} — the only call that returns per-record permissions.
  Future<ResourceRecord> record(String resourceKey, Object id);

  /// GET /{resource}/{id}/relations/{relation} — one relation manager's child
  /// rows, in the same `{data, meta}` envelope [list] uses. The same read
  /// path as [list] against a sibling URL, so it is fetched the same way:
  /// through this data source, never a closure a host has to hand-wire.
  ///
  /// [search]/[sort]/[direction] (P11) mirror [list]'s exactly: the endpoint
  /// answers them with the resource index's contract — an unknown sort key is
  /// a 422, and a declared default sort applies when [sort] is absent.
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page,
    String? search,
    String? sort,
    String? direction,
  });

  /// POST /{resource}/{id}/relations/{relation} — creates one child row
  /// through the relationship (P9). Same never-throw contract as [create];
  /// a 422 carries `errors` keyed by the CHILD resource's field names.
  Future<WriteResult> createRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Map<String, dynamic> values,
  );

  /// PUT /{resource}/{id}/relations/{relation}/{childId} — updates one child
  /// row, resolved through the relationship (P9): [childId] is the related
  /// model's own key (the relation's published `recordKey`), and a child that
  /// is not this parent's answers 404, never a cross-parent write.
  Future<WriteResult> updateRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
    Map<String, dynamic> values,
  );

  /// DELETE /{resource}/{id}/relations/{relation}/{childId} — removes one
  /// child row, resolved through the relationship exactly as [updateRelation].
  Future<WriteResult> deleteRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
  );

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

  /// POST /{resource}/reorder — commits a full drag-to-reorder (P18), in the
  /// records' new top-to-bottom order. [ids] are route keys
  /// (`ResourceRecord.id`), first entry first — see
  /// `ResourceListProvider.saveReorder()`, the only caller.
  ///
  /// Unlike the writes above, there is no data-carrying failure outcome to
  /// return — same contract as [state]/[options] — so a non-2xx throws
  /// `FilamentTransportException` rather than degrading into a silent no-op.
  Future<void> reorder(String resourceKey, List<Object> ids);

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

/// Optional capability for remotely searchable table-filter options.
///
/// Kept outside [ResourceDataSource] so existing host-supplied data sources do
/// not break when upgrading. [RestResourceDataSource] implements it; custom
/// sources can opt in when they are ready to render `optionsUrl` filters.
abstract interface class FilterOptionsDataSource {
  Future<OptionsPage> filterOptions(
    String resourceKey, {
    required String filter,
    required String query,
  });
}

/// Optional capability for the in-app notification bell (P21).
///
/// A sidecar like [FilterOptionsDataSource], for the same reason: existing
/// host-supplied data sources must not break when upgrading.
/// [RestResourceDataSource] implements it; `PanelShell` draws the bell only
/// when the panel declared `notifications` AND the source implements this —
/// the double gate, so a capability the host cannot serve is never rendered.
abstract interface class NotificationsDataSource {
  /// GET /notifications?page=N — newest first, plus the top-level `unread`.
  Future<NotificationsPage> notifications({int page});

  /// POST /notifications/{id}/read — answers the new unread count.
  Future<int> markNotificationRead(String id);

  /// POST /notifications/read-all — answers the new unread count (0).
  Future<int> markAllNotificationsRead();

  /// DELETE /notifications/{id} — Filament's per-row "close".
  Future<void> deleteNotification(String id);

  /// DELETE /notifications — deletes read AND unread, mirroring the web
  /// bell's `clearNotifications()` verbatim.
  Future<void> clearNotifications();
}

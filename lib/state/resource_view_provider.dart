import 'package:flutter/foundation.dart';

import '../data/action_result.dart';
import '../data/paginated_records.dart';
import '../data/record_action.dart';
import '../data/resource_data_source.dart';
import '../data/resource_record.dart';
import '../data/write_result.dart';
import '../ports/filament_transport.dart';
import '../schema/relation_descriptor.dart';
import '../schema/resource_schema.dart';
import 'load_status.dart';

/// Loads one record for the detail screen.
///
/// Holds the [resource] alongside the record because the screen needs both:
/// the schema supplies the infolist and the title, the record supplies the
/// values *and* its own per-record permissions. The two permission blocks are
/// deliberately not merged here — see [ResourceRecord.permissions].
class ResourceViewProvider extends ChangeNotifier {
  ResourceViewProvider({
    required this.source,
    required this.resource,
    required this.id,
  });

  final ResourceDataSource source;
  final ResourceSchema resource;
  final Object id;

  LoadStatus _status = LoadStatus.initial;
  ResourceRecord? _record;
  String? _errorMessage;
  bool _isUnauthenticated = false;

  LoadStatus get status => _status;
  ResourceRecord? get record => _record;
  String? get errorMessage => _errorMessage;

  /// True when the load failed on a 401 — see [FilamentTransportException.statusCode].
  bool get isUnauthenticated => _isUnauthenticated;

  /// Loads the record.
  ///
  /// [keepPrevious] holds the currently-shown record while the new one loads,
  /// and holds it through a failure too — a refresh that fails must not cost
  /// the user the data they were already reading. Default false so a first
  /// load, or a move to a different record, never shows the previous one's
  /// values under the new one's title.
  Future<void> load({bool keepPrevious = false}) =>
      _load(keepPrevious: keepPrevious, silentFailure: false);

  /// Background revalidation: keeps both the record and a successful screen
  /// state through a transient failure. Authentication failures still surface.
  Future<void> refresh() => _load(keepPrevious: true, silentFailure: true);

  Future<void> _load({
    required bool keepPrevious,
    required bool silentFailure,
  }) async {
    final preserve = keepPrevious && _record != null;
    _status = LoadStatus.loading;
    _errorMessage = null;
    _isUnauthenticated = false;
    if (!keepPrevious) _record = null;
    notifyListeners();

    try {
      _record = await source.record(resource.key, id);
      _status = LoadStatus.success;
    } catch (e) {
      if (e is FilamentTransportException && e.statusCode == 401) {
        _isUnauthenticated = true;
      }
      _errorMessage = messageOf(e);
      _status = preserve && silentFailure && !_isUnauthenticated
          ? LoadStatus.success
          : LoadStatus.failure;
    }

    notifyListeners();
  }

  /// Deletes this record. A pass-through, not a state change: the outcome
  /// decides whether the screen pops or stays, and either way this provider's
  /// own `_record`/`_status` describe a record that either no longer exists or
  /// was never touched — nothing here needs updating either way.
  Future<WriteResult> delete() => source.destroy(resource.key, id);

  /// Run [action] against this record and, on success, re-fetch — an
  /// action's most common effect is changing exactly the `permissions` and
  /// `actions` this provider is holding, so the pre-run record is stale the
  /// moment the call succeeds.
  ///
  /// The result is returned rather than folded into [status]: the screen
  /// decides whether the message is a snack bar or a banner, and a failed
  /// action is not a failed screen — the record is still fine to display.
  Future<ActionResult> runAction(RecordAction action) async {
    final result = await source.runAction(resource.key, id, action.name);

    if (result is ActionSuccess) {
      await load();
    }

    return result;
  }

  /// One [relation]'s rows for the record this provider holds — the same
  /// read path `load()` uses, against a sibling URL. A pass-through, not a
  /// state change: `RelationSectionWidget` owns its own loading/failure
  /// state for it, the same division `ResourceListProvider` keeps between
  /// itself and the screen that renders its pages.
  Future<PaginatedRecords> loadRelation(
    RelationDescriptor relation, {
    int page = 1,
  }) => source.relation(resource.key, id, relation, page: page);
}

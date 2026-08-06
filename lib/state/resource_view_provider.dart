import 'package:flutter/foundation.dart';

import '../data/resource_data_source.dart';
import '../data/resource_record.dart';
import '../data/write_result.dart';
import '../ports/filament_transport.dart';
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
    required ResourceDataSource source,
    required this.resource,
    required this.id,
  }) : _source = source;

  final ResourceDataSource _source;
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
  Future<void> load({bool keepPrevious = false}) async {
    _status = LoadStatus.loading;
    _errorMessage = null;
    _isUnauthenticated = false;
    if (!keepPrevious) _record = null;
    notifyListeners();

    try {
      _record = await _source.record(resource.key, id);
      _status = LoadStatus.success;
    } catch (e) {
      if (e is FilamentTransportException && e.statusCode == 401) {
        _isUnauthenticated = true;
      }
      _errorMessage = messageOf(e);
      _status = LoadStatus.failure;
    }

    notifyListeners();
  }

  /// Deletes this record. A pass-through, not a state change: the outcome
  /// decides whether the screen pops or stays, and either way this provider's
  /// own `_record`/`_status` describe a record that either no longer exists or
  /// was never touched — nothing here needs updating either way.
  Future<WriteResult> delete() => _source.destroy(resource.key, id);
}

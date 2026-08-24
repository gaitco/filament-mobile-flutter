import 'package:flutter/foundation.dart';

import '../dashboard/dashboard_data.dart';
import '../data/resource_data_source.dart';
import '../ports/filament_transport.dart';
import 'load_status.dart';

/// Loads the dashboard once and holds it for [DashboardScreen].
///
/// A plain [ChangeNotifier], structured exactly like [PanelProvider] — same
/// status/error/unauthenticated shape — with one deliberate omission: there
/// is no `needsAppUpdate`. The dashboard carries no contract version to be
/// behind on.
class DashboardProvider extends ChangeNotifier {
  DashboardProvider(this._source);

  final ResourceDataSource _source;

  LoadStatus _status = LoadStatus.initial;
  DashboardData? _data;
  String? _errorMessage;
  bool _isUnauthenticated = false;

  LoadStatus get status => _status;
  DashboardData? get data => _data;
  String? get errorMessage => _errorMessage;

  /// True when the load failed on a 401 — see [FilamentTransportException.statusCode].
  bool get isUnauthenticated => _isUnauthenticated;

  Future<void> load({bool keepPrevious = false}) =>
      _load(keepPrevious: keepPrevious, silentFailure: false);

  /// Timer-driven revalidation that preserves an already-rendered dashboard
  /// through a transient failure. A 401 still replaces it with signed-out.
  Future<void> refresh() => _load(keepPrevious: true, silentFailure: true);

  Future<void> _load({
    required bool keepPrevious,
    required bool silentFailure,
  }) async {
    final preserve = keepPrevious && _data != null;
    _status = LoadStatus.loading;
    _errorMessage = null;
    _isUnauthenticated = false;
    notifyListeners();

    try {
      _data = await _source.dashboard();
      _status = LoadStatus.success;
    } catch (e) {
      // A 404 here is "this panel serves no dashboard" — a read-only host
      // (gait/nova-mobile's first slice) or a panel with the dashboard
      // disabled — and an empty dashboard is what the screen should show,
      // not an error with a Retry that can never succeed. Only 404: a 401
      // is still the session, anything else is still a failure.
      if (e is FilamentTransportException && e.statusCode == 404) {
        _data = const DashboardData();
        _status = LoadStatus.success;
        notifyListeners();
        return;
      }
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
}

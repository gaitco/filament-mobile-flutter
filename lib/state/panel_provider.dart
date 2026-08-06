import 'package:flutter/foundation.dart';

import '../data/resource_data_source.dart';
import '../ports/filament_transport.dart';
import '../schema/panel_schema.dart';
import 'load_status.dart';

/// Loads the panel document once and holds it for every screen.
///
/// A plain [ChangeNotifier] with no package dependency: a host may wrap it in
/// `provider`, or screens may listen through `ListenableBuilder`.
class PanelProvider extends ChangeNotifier {
  PanelProvider(this._source);

  final ResourceDataSource _source;

  LoadStatus _status = LoadStatus.initial;
  PanelSchema? _panel;
  String? _errorMessage;
  bool _needsAppUpdate = false;
  bool _isUnauthenticated = false;

  LoadStatus get status => _status;
  PanelSchema? get panel => _panel;
  String? get errorMessage => _errorMessage;

  /// True when the server speaks a newer contract than this build understands.
  /// The UI shows a blocking "update the app" screen: a half-rendered panel
  /// would hide whatever it could not parse.
  bool get needsAppUpdate => _needsAppUpdate;

  /// True when the load failed on a 401 — see [FilamentTransportException.statusCode].
  bool get isUnauthenticated => _isUnauthenticated;

  Future<void> load() async {
    _status = LoadStatus.loading;
    _errorMessage = null;
    _needsAppUpdate = false;
    _isUnauthenticated = false;
    notifyListeners();

    try {
      _panel = await _source.panel();
      _status = LoadStatus.success;
    } on UnsupportedSchemaVersionException catch (e) {
      _needsAppUpdate = true;
      _errorMessage = messageOf(e);
      _status = LoadStatus.failure;
    } catch (e) {
      if (e is FilamentTransportException && e.statusCode == 401) {
        _isUnauthenticated = true;
      }
      _errorMessage = messageOf(e);
      _status = LoadStatus.failure;
    }

    notifyListeners();
  }
}

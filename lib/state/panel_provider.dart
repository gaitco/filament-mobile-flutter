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
    // Cold-start fast path: a cached panel (Task 4's cachedPanel(), which
    // never touches the network and never throws) is published immediately
    // so the user sees the panel instead of a spinner over a ~200 KB fetch.
    // No cache means today's behaviour: a loading state while panel() runs.
    PanelSchema? cached;
    try {
      cached = await _source.cachedPanel();
    } catch (_) {
      // The interface mandates null-on-no-cache and the in-package
      // implementation never throws, but a third-party ResourceDataSource
      // might. A broken cache read degrades to "no cache" — load() never
      // threw before this call existed, and must not start now.
    }
    final hadCache = cached != null;

    if (hadCache) {
      _panel = cached;
      _status = LoadStatus.success;
    } else {
      _status = LoadStatus.loading;
    }
    _errorMessage = null;
    _needsAppUpdate = false;
    _isUnauthenticated = false;
    notifyListeners();

    try {
      _panel = await _source.panel();
      _status = LoadStatus.success;
    } on UnsupportedSchemaVersionException catch (e) {
      // Always surfaces, cache or not: a cached document only ever holds an
      // older, valid schema, and this branch does not touch it — there is
      // nothing wrong with the cache to clear. But a too-new server response
      // means the user must update the app, and a stale panel rendered on
      // top of that fact would hide it more convincingly than showing
      // nothing at all — the same reasoning the class doc gives for not
      // half-rendering an unparseable panel.
      _needsAppUpdate = true;
      _errorMessage = messageOf(e);
      _status = LoadStatus.failure;
    } catch (e) {
      final unauthenticated =
          e is FilamentTransportException && e.statusCode == 401;
      if (unauthenticated) {
        // Unlike other revalidation failures, a 401 always ends in failure:
        // a signed-out session must not keep showing a panel, even a cached
        // one, and the screens only look at isUnauthenticated once
        // status.isFailure is true.
        _isUnauthenticated = true;
        _errorMessage = messageOf(e);
        _status = LoadStatus.failure;
      } else if (!hadCache) {
        _errorMessage = messageOf(e);
        _status = LoadStatus.failure;
      }
    }

    notifyListeners();
  }
}

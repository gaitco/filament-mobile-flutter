import 'package:flutter/foundation.dart';

import '../data/panel_notification.dart';
import '../data/resource_data_source.dart';
import '../ports/filament_transport.dart';
import 'load_status.dart';

/// Holds the notification feed and badge count for `PanelShell`'s bell (P21).
///
/// The [DashboardProvider] shape — `load`/`refresh`, a timer-driven refresh
/// preserves the last good render through a transient failure, 401 →
/// [isUnauthenticated] — plus mutations that apply the server's answer on
/// success and surface [errorMessage] on failure. Deliberately no optimistic
/// state: a failed request would have to unwind it.
///
/// Notifications are a sidecar capability ([NotificationsDataSource]); a
/// source without it loads as a benign empty success, never an error the
/// host cannot fix at runtime.
// ponytail: page 1 only — the sheet shows the newest page and the badge only
// needs `unread`; add a loadMore/pagination path when a host needs the
// archive.
class NotificationsProvider extends ChangeNotifier {
  NotificationsProvider(this._source);

  final ResourceDataSource _source;

  LoadStatus _status = LoadStatus.initial;
  NotificationsPage _page = const NotificationsPage();
  bool _loaded = false;
  String? _errorMessage;
  bool _isUnauthenticated = false;

  LoadStatus get status => _status;
  List<PanelNotification> get items => _page.items;
  int get unread => _page.unread;
  String? get errorMessage => _errorMessage;

  /// True when the load failed on a 401 — see
  /// [FilamentTransportException.statusCode].
  bool get isUnauthenticated => _isUnauthenticated;

  Future<void> load({bool keepPrevious = false}) =>
      _load(keepPrevious: keepPrevious, silentFailure: false);

  /// Timer/realtime-driven revalidation that preserves an already-rendered
  /// feed through a transient failure. A 401 still surfaces as signed-out.
  Future<void> refresh() => _load(keepPrevious: true, silentFailure: true);

  Future<void> _load({
    required bool keepPrevious,
    required bool silentFailure,
  }) async {
    // `NotificationsDataSource` is a sibling interface, not a subtype of
    // `ResourceDataSource`, so Dart cannot promote from the `is!` check —
    // the explicit cast below is required, not decorative (the
    // `FilamentUploadTransport` precedent).
    if (_source is! NotificationsDataSource) {
      // The shell never draws the bell for such a source (the double gate),
      // so this is only ever a directly composed provider — an empty feed,
      // not a failure.
      _status = LoadStatus.success;
      notifyListeners();
      return;
    }
    final source = _source as NotificationsDataSource;

    final preserve = keepPrevious && _loaded;
    _status = LoadStatus.loading;
    _errorMessage = null;
    _isUnauthenticated = false;
    notifyListeners();

    try {
      _page = await source.notifications();
      _loaded = true;
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

  /// Marks one row read. The row updates locally and the badge takes the
  /// count the SERVER answered — never a local guess a failed request would
  /// have to unwind.
  Future<bool> markRead(String id) => _mutate((source) async {
    final unread = await source.markNotificationRead(id);
    _page = NotificationsPage(
      items: [
        for (final item in _page.items)
          if (item.id == id && item.isUnread) _read(item) else item,
      ],
      unread: unread,
      currentPage: _page.currentPage,
      lastPage: _page.lastPage,
    );
  });

  Future<bool> markAllRead() => _mutate((source) async {
    final unread = await source.markAllNotificationsRead();
    _page = NotificationsPage(
      items: [
        for (final item in _page.items)
          if (item.isUnread) _read(item) else item,
      ],
      unread: unread,
      currentPage: _page.currentPage,
      lastPage: _page.lastPage,
    );
  });

  /// Removes one row (Filament's per-row "close"). The DELETE answers 204
  /// with no count, so an unread row's removal decrements the badge locally;
  /// the next poll reconciles.
  Future<bool> deleteOne(String id) => _mutate((source) async {
    await source.deleteNotification(id);
    final removed = _page.items.where((item) => item.id == id);
    final wasUnread = removed.isNotEmpty && removed.first.isUnread;
    _page = NotificationsPage(
      items: [
        for (final item in _page.items)
          if (item.id != id) item,
      ],
      unread: wasUnread && _page.unread > 0 ? _page.unread - 1 : _page.unread,
      currentPage: _page.currentPage,
      lastPage: _page.lastPage,
    );
  });

  /// Deletes everything, read and unread — the web bell's
  /// `clearNotifications()` verbatim. The UI confirms first.
  Future<bool> clearAll() => _mutate((source) async {
    await source.clearNotifications();
    _page = const NotificationsPage();
  });

  Future<bool> _mutate(
    Future<void> Function(NotificationsDataSource source) run,
  ) async {
    // Same sibling-interface cast as [_load].
    if (_source is! NotificationsDataSource) return false;
    final source = _source as NotificationsDataSource;

    try {
      await run(source);
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = messageOf(e);
      notifyListeners();
      return false;
    }
  }

  static PanelNotification _read(PanelNotification item) => PanelNotification(
    id: item.id,
    title: item.title,
    body: item.body,
    status: item.status,
    color: item.color,
    date: item.date,
    readAt: DateTime.now(),
    actions: item.actions,
  );
}

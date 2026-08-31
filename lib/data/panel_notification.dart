import 'package:equatable/equatable.dart';

/// One action button on a notification: a label and the URL it opens.
///
/// The server publishes only URL-carrying actions — a Livewire
/// event-dispatching action cannot run headlessly and is dropped there,
/// fail-closed per entry — and this parser drops any malformed remnant the
/// same way.
class NotificationAction extends Equatable {
  const NotificationAction({required this.label, required this.url});

  static NotificationAction? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final label = value['label'];
    final url = value['url'];
    if (label is! String || label.isEmpty || url is! String || url.isEmpty) {
      return null;
    }
    return NotificationAction(label: label, url: url);
  }

  final String label;
  final String url;

  @override
  List<Object?> get props => [label, url];
}

/// One row of the user's Filament database-notification feed (P21).
///
/// Parsing is lenient throughout — a malformed action entry is dropped, a
/// malformed row is dropped by [NotificationsPage], and nothing here throws:
/// the bell is an additive feature, and one bad row must never take the
/// whole feed down.
class PanelNotification extends Equatable {
  const PanelNotification({
    required this.id,
    this.title = '',
    this.body,
    this.status,
    this.color,
    this.date,
    this.readAt,
    this.actions = const [],
  });

  /// Null — dropped — when the row has no usable string `id`: without the
  /// uuid there is nothing to mark read or delete, so the row cannot be
  /// acted on at all.
  static PanelNotification? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    if (id is! String || id.isEmpty) return null;

    final title = value['title'];
    final body = value['body'];
    final status = value['status'];
    final color = value['color'];
    final actions = value['actions'];

    return PanelNotification(
      id: id,
      title: title is String ? title : '',
      body: body is String && body.isNotEmpty ? body : null,
      status: status is String && status.isNotEmpty ? status : null,
      color: color is String && color.isNotEmpty ? color : null,
      date: _date(value['date']),
      readAt: _date(value['readAt']),
      actions: [
        if (actions is List)
          for (final entry in actions)
            if (NotificationAction.fromJson(entry) case final action?) action,
      ],
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  final String id;

  /// Rendered as plain text: Filament allows markdown here, and a styled
  /// title degrades to its raw text — the rich-text precedent, documented
  /// on the contract.
  final String title;
  final String? body;

  /// The existing semantic vocabulary (`success`/`warning`/`danger`/`info`),
  /// null when the notification declared none.
  final String? status;
  final String? color;
  final DateTime? date;
  final DateTime? readAt;
  final List<NotificationAction> actions;

  bool get isUnread => readAt == null;

  @override
  List<Object?> get props => [
    id,
    title,
    body,
    status,
    color,
    date,
    readAt,
    actions,
  ];
}

/// One page of `GET /notifications`: the rows plus the one top-level count
/// the badge needs.
class NotificationsPage extends Equatable {
  const NotificationsPage({
    this.items = const [],
    this.unread = 0,
    this.currentPage = 1,
    this.lastPage = 1,
  });

  factory NotificationsPage.fromJson(Map<String, dynamic> json) {
    final rows = json['data'];
    final meta = json['meta'];
    int metaInt(String key) {
      final value = meta is Map<String, dynamic> ? meta[key] : null;
      return value is int && value >= 1 ? value : 1;
    }

    final unread = json['unread'];

    return NotificationsPage(
      items: [
        if (rows is List)
          for (final row in rows)
            if (PanelNotification.fromJson(row) case final parsed?) parsed,
      ],
      // Wrong-typed reads as 0 — the badge simply stays hidden, never throws.
      unread: unread is int && unread >= 0 ? unread : 0,
      currentPage: metaInt('current_page'),
      lastPage: metaInt('last_page'),
    );
  }

  final List<PanelNotification> items;
  final int unread;
  final int currentPage;
  final int lastPage;

  @override
  List<Object?> get props => [items, unread, currentPage, lastPage];
}

import 'package:flutter/material.dart';

import '../data/panel_notification.dart';
import '../ports/filament_strings.dart';
import '../state/notifications_provider.dart';
import 'semantic_badge.dart';

/// The notification bell's panel (P21): header actions, then the feed's
/// first page as rows.
///
/// A plain content widget, not itself a route — `PanelShell` decides whether
/// to host it in a `showModalBottomSheet` (compact) or a `showDialog`
/// (medium/expanded), and wraps it in the `Directionality` a sheet/dialog
/// route does not inherit on its own; see `FilterSheet`'s class doc for the
/// same split.
class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({
    required this.provider,
    this.strings = const FilamentStrings(),
    this.onLinkTap,
    super.key,
  });

  final NotificationsProvider provider;
  final FilamentStrings strings;

  /// Where a notification action's URL goes — the rich-text link rule: no
  /// URL-launcher dependency, the host owns navigation. Actions render only
  /// when this is wired; a button the host cannot honour is never drawn.
  final void Function(String href)? onLinkTap;

  @override
  Widget build(BuildContext context) {
    // Listens on its own, independent of whatever opened it — a sheet/dialog
    // route is a sibling in the Navigator's overlay, so marking a row read
    // must be reflected here, not just after it closes.
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            Flexible(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.notificationsTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (provider.unread > 0)
            TextButton(
              key: const ValueKey('notifications.markAllRead'),
              onPressed: provider.markAllRead,
              child: Text(strings.markAllRead),
            ),
          if (provider.items.isNotEmpty)
            IconButton(
              key: const ValueKey('notifications.clearAll'),
              tooltip: strings.clearNotificationsTitle,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClear(context),
            ),
        ],
      ),
    );
  }

  /// Clear deletes read and unread alike — the delete-record confirm
  /// precedent: destructive and unrecoverable, so it asks first.
  Future<void> _confirmClear(BuildContext context) async {
    // The dialog is an overlay route, a sibling of this sheet — re-apply the
    // direction this sheet's content was wrapped in (valid here, unlike in
    // the opener: this context IS a descendant of the wrap).
    final direction = Directionality.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: direction,
        child: AlertDialog(
          title: Text(strings.clearNotificationsTitle),
          content: Text(strings.clearNotificationsBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            TextButton(
              key: const ValueKey('notifications.clearAll.confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.clearNotificationsConfirm),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) await provider.clearAll();
  }

  Widget _body(BuildContext context) {
    if ((provider.status.isLoading || provider.status.isInitial) &&
        provider.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.status.isFailure) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(provider.errorMessage ?? strings.loadFailed),
            TextButton(onPressed: provider.load, child: Text(strings.retry)),
          ],
        ),
      );
    }

    if (provider.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(strings.notificationsEmpty)),
      );
    }

    return ListView(
      shrinkWrap: true,
      children: [for (final item in provider.items) _row(context, item)],
    );
  }

  Widget _row(BuildContext context, PanelNotification item) {
    final theme = Theme.of(context);
    final dotColor =
        SemanticBadge.colorFor(item.status) ??
        SemanticBadge.colorFor(item.color) ??
        theme.colorScheme.primary;

    return ListTile(
      key: ValueKey('notification.${item.id}'),
      // Row tap marks it read — the web bell's own behaviour; a read row
      // has nothing left to do on tap.
      onTap: item.isUnread ? () => provider.markRead(item.id) : null,
      leading: item.isUnread
          ? Icon(Icons.circle, size: 10, color: dotColor)
          : const SizedBox(width: 10),
      title: Text(
        item.title,
        style: item.isUnread
            ? const TextStyle(fontWeight: FontWeight.w600)
            : null,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.body case final body?)
            Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (_time(item.date) case final time?)
            Text(time, style: theme.textTheme.bodySmall),
          if (onLinkTap != null && item.actions.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final action in item.actions)
                  TextButton(
                    onPressed: () => onLinkTap!(action.url),
                    child: Text(action.label),
                  ),
              ],
            ),
        ],
      ),
      trailing: IconButton(
        tooltip: strings.dismissNotification,
        icon: const Icon(Icons.close, size: 18),
        onPressed: () => provider.deleteOne(item.id),
      ),
    );
  }

  /// Relative for the recent past, absolute (`yyyy-mm-dd`, formatted by hand
  /// — no intl dependency) beyond 30 days. Null when the row carried no
  /// parseable date, so the line simply doesn't render.
  String? _time(DateTime? date) {
    if (date == null) return null;
    final elapsed = DateTime.now().difference(date);
    if (elapsed.inMinutes < 1) return strings.timeJustNow;
    if (elapsed.inHours < 1) return strings.timeMinutesAgo(elapsed.inMinutes);
    if (elapsed.inDays < 1) return strings.timeHoursAgo(elapsed.inHours);
    if (elapsed.inDays <= 30) return strings.timeDaysAgo(elapsed.inDays);

    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

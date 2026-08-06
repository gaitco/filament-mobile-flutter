/// The outcome of running a record action.
///
/// Sealed so a caller's `switch` is exhaustive, exactly like `WriteResult`:
/// an action that halts is a named outcome the server chose, not an error
/// to be lumped in with a broken connection.
sealed class ActionResult {
  const ActionResult();
}

/// The action ran. [message] is the action's own success notification title
/// when it declared one — null is ordinary, and the client shows its own
/// generic confirmation then.
final class ActionSuccess extends ActionResult {
  const ActionSuccess(this.message);

  final String? message;
}

/// The action refused (HTTP 422 — Filament's `Halt`), or any other non-2xx
/// (403, 404, 500). [message] is its failure notification title when it
/// declared one.
final class ActionFailed extends ActionResult {
  const ActionFailed(this.message);

  final String? message;
}

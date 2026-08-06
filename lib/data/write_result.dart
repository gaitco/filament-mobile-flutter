/// The outcome of a write, as data.
///
/// Sealed so a caller's `switch` is exhaustive — adding an outcome later is a
/// compile error rather than a silently unhandled branch, the same reasoning
/// `PanelViewState` uses.
sealed class WriteResult {
  const WriteResult();
}

final class WriteSuccess extends WriteResult {
  const WriteSuccess(this.data);
  final Map<String, dynamic> data;
}

final class WriteInvalid extends WriteResult {
  const WriteInvalid(this.errors);

  /// Keyed by field name, exactly as Laravel sends it. A key matching no field
  /// is the caller's problem to surface, never to drop — see the form banner.
  final Map<String, List<String>> errors;
}

final class WriteDenied extends WriteResult {
  const WriteDenied(this.message);
  final String message;
}

final class WriteGone extends WriteResult {
  const WriteGone(this.message);
  final String message;
}

final class WriteFailed extends WriteResult {
  const WriteFailed(this.message);
  final String message;
}

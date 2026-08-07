/// The outcome of uploading a file for a single-file upload field.
///
/// Sealed so a caller's `switch` is exhaustive, exactly like [ActionResult]:
/// mirrors its shape because an upload's contract is the same one — it either
/// ran or it did not, and the caller needs the reason.
sealed class UploadResult {
  const UploadResult();
}

/// The upload succeeded. [path] is the stored path the server returned —
/// what the field's value becomes, and what the ordinary write path then
/// saves as a plain string.
final class UploadSuccess extends UploadResult {
  const UploadSuccess(this.path);

  final String path;
}

/// The upload did not happen: a refusal (422 too large/wrong type, 403 not
/// resolvable/writable/disabled), a transport failure, or a host transport
/// that has not implemented [FilamentUploadTransport]. [message] is the
/// user-facing reason when one is known.
final class UploadFailed extends UploadResult {
  const UploadFailed(this.message, {this.statusCode});

  final String? message;

  /// The HTTP status the server answered with, mirroring
  /// `FilamentTransportException.statusCode`. Null when there was no
  /// response to read one from — a transport throw (offline, DNS) or a host
  /// transport that never implemented [FilamentUploadTransport] — which is
  /// exactly the set of failures a form field cannot blame on this one
  /// field, so `ResourceFormProvider.uploadFile()` routes anything but a
  /// literal `422` to the form banner rather than the field.
  final int? statusCode;
}

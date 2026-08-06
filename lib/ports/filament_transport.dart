/// The package's only network dependency.
///
/// A host implements this over whatever HTTP client it already uses, so
/// retries, token refresh, offline detection and error mapping all stay in the
/// host's stack. The package never sees them.
abstract interface class FilamentTransport {
  /// Performs a GET and returns the decoded JSON object.
  ///
  /// Throws on transport or HTTP failure; the caller converts that into a
  /// [PanelFailure]. The message of the thrown error is shown to the user, so
  /// a host should throw something already translated.
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query});

  /// Performs a POST and returns the response, whatever its status.
  ///
  /// **Deliberately asymmetric with [get], which throws on an HTTP failure.**
  /// These throw ONLY on transport failure — no socket, DNS, timeout. A 422,
  /// 403 or 404 must come back as a [FilamentResponse]: the package owns what
  /// a status means, so a host cannot silently turn field-level validation
  /// messages into a generic error by forgetting a rule.
  Future<FilamentResponse> post(String path, Map<String, dynamic> body);

  /// See the asymmetry note on [post] — this throws only on transport failure.
  Future<FilamentResponse> put(String path, Map<String, dynamic> body);

  /// See the asymmetry note on [post] — this throws only on transport failure.
  ///
  /// A destroy typically answers 204 with an empty body. Decode that as
  /// `body: const {}`, not `null` or a raw empty-string parse — an HTTP
  /// client's default JSON decoder often throws on an empty response body,
  /// which would turn a genuine success into a spurious [WriteFailed].
  Future<FilamentResponse> delete(String path);
}

/// One HTTP response, status included.
///
/// Writes return this rather than throwing, because a 422's body carries the
/// field messages a form needs. See the asymmetry note on [FilamentTransport].
class FilamentResponse {
  const FilamentResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, dynamic> body;
}

/// A failure carrying a message that is already fit for the user.
///
/// Dart's own `Exception('x').toString()` is `"Exception: x"`, so a host
/// throwing a plain exception leaks that prefix onto the screen. This one
/// stringifies to the bare message, and exists so no host has to write it.
///
/// [statusCode] is **advisory and optional** — `get()` throws on both
/// transport and HTTP failure with no status attached today, so a host that
/// wants a 401 to be told apart from a generic [PanelFailure] sets
/// `statusCode: 401` on the exception it throws from its
/// `FilamentTransport.get()` implementation — the one line a host adds; the
/// package's read-path providers map that status to `isUnauthenticated`,
/// and the screens surface it as [PanelUnauthenticated].
/// A host that never sets it keeps today's behaviour —
/// every thrown failure still becomes [PanelFailure] — because [statusCode]
/// defaults to `null` and stays out of its way.
class FilamentTransportException implements Exception {
  const FilamentTransportException(this.message, {this.statusCode});

  final String message;

  /// The HTTP status that caused this, when the host's transport knows it.
  /// `null` if unset — see the class doc for what setting it unlocks.
  final int? statusCode;

  @override
  String toString() => message;
}

/// The text a provider shows for a thrown [error].
///
/// Prefers a `message` field when the thrown object has one — a host's own
/// failure type usually carries the translated text there, while its
/// `toString()` is a debug dump — and falls back to `toString()`.
String messageOf(Object error) {
  try {
    final message = (error as dynamic).message;
    if (message is String && message.isNotEmpty) return message;
  } catch (_) {
    // No `message` on this type; the fallback below is the answer.
  }

  return error.toString();
}

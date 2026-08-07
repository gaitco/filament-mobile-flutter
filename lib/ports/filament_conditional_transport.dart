import 'filament_transport.dart';

/// The optional conditional-GET half of the transport, separate from
/// [FilamentTransport] on purpose.
///
/// **Not a method on `FilamentTransport`.** P6a established this the hard way
/// and it was verified against the analyzer: `FilamentTransport` is an
/// `abstract interface class`, hosts implement it with `implements`, and
/// `implements` inherits the interface without any implementation — so adding
/// a member, even one with a default body, is a compile error in every
/// existing host. A second interface is additive: a host that never
/// revalidates is untouched, and one that does implements both.
///
/// **`get()` cannot serve this.** It throws on every non-2xx status, so a 304
/// would arrive as a thrown failure indistinguishable from a real error — the
/// caller has no way to tell "unchanged" from "broken". And `FilamentResponse`
/// carries only `statusCode` and `body`; nothing in `lib/` reads a header
/// today, so the `ETag` a revalidating request needs to see has nowhere to
/// land.
///
/// A 304 **must** come back as a [ConditionalResponse] with
/// `notModified: true` — never a throw, and never a synthesised empty body
/// dressed up as a 200.
abstract interface class FilamentConditionalTransport {
  /// GETs [path], sending `If-None-Match: <etag>` when [etag] is non-null.
  Future<ConditionalResponse> getConditional(String path, {String? etag});
}

/// The outcome of one conditional GET.
class ConditionalResponse {
  const ConditionalResponse({required this.notModified, this.body, this.etag})
    // A 304 carries no body to decode; a host implementation that sets both
    // is buggy in a way its own tests should catch, not something the
    // caller should have to guard against.
    : assert(!notModified || body == null);

  /// True for a 304: the caller's cached document is still current.
  final bool notModified;

  /// The decoded body of a 200. Null when [notModified] — a 304 carries no
  /// body to decode, and the caller already has one.
  final Map<String, dynamic>? body;

  /// The response's `ETag`, when it sent one, for the caller to store
  /// alongside the document it now has.
  final String? etag;
}

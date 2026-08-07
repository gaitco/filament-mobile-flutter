import 'filament_transport.dart';

/// The optional upload half of the transport, separate from
/// [FilamentTransport] on purpose.
///
/// Adding a member to [FilamentTransport] would be a breaking change for
/// every host: it is an `abstract interface class`, hosts implement it with
/// `implements`, and `implements` inherits the interface without any
/// implementation — so even a member with a default body fails to compile in
/// a host that has not written it. A second interface is additive: a host
/// that never uploads is untouched, and one that does implements both.
///
/// Bytes, not JSON: a base64 body would hold a photo whole in memory on both
/// ends and collide with PHP's `post_max_size` in ways that read as server
/// bugs. Implement this with your client's real multipart support.
abstract interface class FilamentUploadTransport {
  Future<FilamentResponse> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    String field = 'file',
  });
}

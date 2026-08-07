import 'filament_file_picker.dart';

/// Persists the panel schema document across app restarts, the host's way.
///
/// This package ships exactly two runtime dependencies (`flutter`,
/// `equatable`), and that is a load-bearing feature — same reasoning as
/// [FilamentFilePicker]. So storage is the host's: over `shared_preferences`,
/// Hive, a file, whatever it already carries.
///
/// **Without a cache the client behaves exactly as it does today**: in-memory
/// only, lost on restart. That is the honest no-op, not a degraded mode.
///
/// **The [String] key is the host's, and scoping it is a safety property, not
/// a style choice.** `/schema` is per-user — policies filter which resources
/// appear — so a cached document is one user's view of the panel. The host
/// must scope the key to the signed-in user (a user id, a token hash — its
/// choice); a constant or otherwise unscoped key would let a second user on
/// the same device open the first user's cached panel index. This package
/// cannot enforce that: it has no identity concept, by design, so it
/// documents the obligation instead. A host that supplies no key gets no
/// persistence — which fails safe, the same as omitting this port entirely.
abstract interface class FilamentSchemaCache {
  Future<CachedSchema?> read(String key);
  Future<void> write(String key, CachedSchema value);
  Future<void> clear(String key);
}

/// One cached panel document.
class CachedSchema {
  const CachedSchema({required this.document, this.etag});

  /// The decoded body, re-encoded — never a re-serialised model.
  ///
  /// Neither transport port ever exposes raw wire bytes: both `get()` and
  /// `getConditional()` hand back an already-decoded `Map<String, dynamic>`,
  /// so there is no original JSON string in this package to store. This is
  /// `jsonEncode()` of that same decoded map, which is what makes it safe: a
  /// key `PanelSchema.fromJson` does not yet recognise is still in that map
  /// and survives the round trip. Encoding the **model** instead would let
  /// this package's own types silently become the cache's schema and drop
  /// such a key on write, never to be recovered.
  ///
  /// Key order or escaping may differ from what the server originally sent,
  /// and that is inert: [etag] is never recomputed or compared against
  /// these bytes — it is an opaque token, stored beside the document and
  /// echoed back in `If-None-Match`.
  final String document;

  final String? etag;
}

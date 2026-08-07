import 'dart:convert';

import '../ports/filament_conditional_transport.dart';
import '../ports/filament_schema_cache.dart';
import '../ports/filament_transport.dart';
import '../schema/panel_schema.dart';

/// Owns the read-parse-revalidate cycle for the panel document, so
/// `RestResourceDataSource` stays thin.
///
/// Three parties must agree here: the server's ETag, the cached bytes, and
/// the parsed model. A write to [FilamentSchemaCache] always carries the
/// document exactly as decoded off the wire together with the ETag that
/// describes those same bytes, in one [CachedSchema] — never two separate
/// calls — so a cache entry can never claim an ETag for a document it does
/// not hold.
class SchemaCacheStore {
  // Named `this._foo`: Dart exposes the public counterpart (`foo`) as the
  // callsite name for a private initializing formal, so callers outside
  // this file still write `transport:`/`path:`/`cache:`/`cacheKey:`.
  SchemaCacheStore({
    required this._transport,
    required this._path,
    this._cache,
    this._cacheKey,
  });

  final FilamentTransport _transport;

  /// The full request path, e.g. `/api/mobile-panel/schema`.
  final String _path;
  final FilamentSchemaCache? _cache;

  /// The host's key, per [FilamentSchemaCache]'s scoping obligation. Null
  /// means no persistence, even when [_cache] is supplied — fail-safe.
  final String? _cacheKey;

  /// [_cacheKey], with an empty or whitespace-only key demoted to null.
  /// `cacheKey: user?.id ?? ''` is the natural host shape when nobody is
  /// signed in, and an empty string is a real, shared, unscoped persistent
  /// key — exactly the cross-user hazard the key exists to prevent. A
  /// whitespace-only key is the same accident with formatting; no honest
  /// per-user scope is blank.
  String? get _effectiveKey {
    final key = _cacheKey;
    if (key == null || key.trim().isEmpty) return null;
    return key;
  }

  /// The cached panel, if there is a usable one — parsed, never rendered
  /// from bytes this build cannot read. Touches storage only, never the
  /// network.
  Future<PanelSchema?> cachedPanel() async {
    final cache = _cache;
    final key = _effectiveKey;
    if (cache == null || key == null) return null;

    return (await _readValid(cache, key))?.panel;
  }

  /// Fetches the panel. Uses a conditional GET and the cache when both are
  /// configured; otherwise this is exactly today's plain `get()`.
  Future<PanelSchema> panel() async {
    final cache = _cache;
    final key = _effectiveKey;
    final transport = _transport;

    final entry = cache != null && key != null
        ? await _readValid(cache, key)
        : null;

    // `FilamentConditionalTransport` is a sibling interface of
    // `FilamentTransport`, not a subtype — hosts implement both on one
    // class, but Dart cannot promote `transport` across this `is` check, so
    // the cast below is required. Do not "simplify" it away.
    if (transport is FilamentConditionalTransport) {
      final conditional = transport as FilamentConditionalTransport;
      final response = await conditional.getConditional(
        _path,
        etag: entry?.cached.etag,
      );

      if (response.notModified) {
        // The cached document just proved current is the one to return.
        // Nothing to rewrite — the cache already holds exactly this.
        if (entry != null) return entry.panel;
        // A 304 with nothing cached to revalidate against should not
        // happen — a host only echoes an etag it was sent — but if it
        // does, fall through to a plain fetch rather than return nothing.
      } else if (response.body != null) {
        final panel = PanelSchema.fromJson(response.body!);
        if (cache != null && key != null) {
          await _writeSafely(
            cache,
            key,
            CachedSchema(
              document: jsonEncode(response.body),
              etag: response.etag,
            ),
          );
        }
        return panel;
      }
    }

    final body = await transport.get(_path);
    final panel = PanelSchema.fromJson(body);
    if (cache != null && key != null) {
      await _writeSafely(
        cache,
        key,
        CachedSchema(document: jsonEncode(body), etag: null),
      );
    }
    return panel;
  }

  /// Reads [key], parsing the stored document. A document this build cannot
  /// read — malformed JSON, or a schema version newer than
  /// [PanelSchema.supportedVersion] — is cleared rather than surfaced: a
  /// stale cache must never throw `UnsupportedSchemaVersionException` and
  /// trigger the "update your app" screen from bytes nobody rendered.
  ///
  /// [cache.read] itself is also guarded (see [_readSafely]): this fires on
  /// every cold start, the most common path in the feature, so a closed
  /// Hive box or a corrupted preferences entry must not take a healthy
  /// transport down with it.
  Future<({CachedSchema cached, PanelSchema panel})?> _readValid(
    FilamentSchemaCache cache,
    String key,
  ) async {
    final stored = await _readSafely(cache, key);
    if (stored == null) return null;

    try {
      final decoded = jsonDecode(stored.document);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('cached schema document is not an object');
      }
      // Deliberately broad: this also catches a genuine bug in
      // PanelSchema.fromJson, which would then be treated as "stale cache"
      // rather than surfaced. Chosen, not overlooked — the alternative is a
      // cache entry that can crash a cold start, which is worse than one
      // that occasionally masks a parser regression during development.
      return (cached: stored, panel: PanelSchema.fromJson(decoded));
    } catch (_) {
      await _clearSafely(cache, key);
      return null;
    }
  }

  Future<CachedSchema?> _readSafely(
    FilamentSchemaCache cache,
    String key,
  ) async {
    try {
      return await cache.read(key);
    } catch (_) {
      // Persistence is an optimisation; a broken cache must fall through to
      // a normal fetch exactly as if it had never been configured.
      return null;
    }
  }

  Future<void> _clearSafely(FilamentSchemaCache cache, String key) async {
    try {
      await cache.clear(key);
    } catch (_) {
      // Best-effort: the caller already treats this entry as unusable
      // regardless of whether the host could actually remove it.
    }
  }

  Future<void> _writeSafely(
    FilamentSchemaCache cache,
    String key,
    CachedSchema value,
  ) async {
    try {
      await cache.write(key, value);
    } catch (_) {
      // Persistence is an optimisation; the fetch it is trying to cache
      // must succeed regardless of whether storage does.
    }
  }
}

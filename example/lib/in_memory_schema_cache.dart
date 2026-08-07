import 'package:filament_mobile/filament_mobile.dart';

/// A [FilamentSchemaCache] that lives only as long as the process — gone on
/// restart, unlike a real host's.
///
/// A real app persists across restarts with `shared_preferences` or Hive;
/// this exists only to exercise the port end to end without adding either
/// dependency to the example, which otherwise carries none beyond
/// `filament_mobile` and `http`.
class InMemorySchemaCache implements FilamentSchemaCache {
  final _entries = <String, CachedSchema>{};

  @override
  Future<CachedSchema?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, CachedSchema value) async {
    _entries[key] = value;
  }

  @override
  Future<void> clear(String key) async {
    _entries.remove(key);
  }
}

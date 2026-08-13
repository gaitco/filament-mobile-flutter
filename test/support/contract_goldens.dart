import 'dart:convert';
import 'dart:io';

/// A shared contract golden, found wherever `contract/` happens to sit.
///
/// Searched UPWARD from the current directory rather than hardcoded as
/// `../../contract`, because this package is tested from two different depths:
/// in the monorepo it lives at `dart/filament_mobile/` and the goldens are two
/// levels up at the repo root, while in the public mirror the package IS the
/// repo root and they sit directly inside it. A fixed depth resolves in one
/// layout and silently fails in the other — and CI now runs in the mirror,
/// because a public repo's Actions minutes are free (see this package's own
/// `.github/workflows/ci.yml`).
///
/// Throws rather than skipping. These goldens are the only thing checking that
/// the client can still parse what the server really emits; a suite that
/// quietly stopped reading them would stay green while the wire drifted, which
/// is exactly how `icon_entry` survived a whole phase.
File contractFile(String name) {
  var dir = Directory.current;

  // Four is the monorepo's two plus slack. The walk stops at the filesystem
  // root, where `parent` returns the same directory.
  for (var i = 0; i < 4; i++) {
    final candidate = File('${dir.path}/contract/$name');
    if (candidate.existsSync()) return candidate;

    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  throw StateError(
    'contract/$name not found in any directory above ${Directory.current.path}'
    ' — the shared goldens are missing, so the contract tests cannot run.',
  );
}

/// The decoded golden, for the common case.
Map<String, dynamic> contractJson(String name) =>
    jsonDecode(contractFile(name).readAsStringSync()) as Map<String, dynamic>;

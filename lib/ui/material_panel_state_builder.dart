import 'package:flutter/material.dart';

import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';

/// The fallback the package ships so it runs standalone in tests and in an app
/// that has not written an adapter yet. A host overrides this with its own
/// loading, empty and error widgets.
PanelBodyBuilder materialPanelStateBuilder([
  FilamentStrings strings = const FilamentStrings(),
]) {
  return (context, state) => switch (state) {
    PanelLoading() => const Center(child: CircularProgressIndicator()),
    PanelEmpty(:final message) => Center(
      key: const ValueKey('panel.empty'),
      child: Text(message ?? strings.empty),
    ),
    PanelFailure(:final message, :final retry) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: Text(strings.retry)),
        ],
      ),
    ),
    // Distinct from PanelFailure on purpose — a lock icon, not a generic
    // error — so a signed-out user is told they were signed out, not that
    // the server broke. See PanelUnauthenticated's doc comment for why.
    PanelUnauthenticated(:final message, :final retry) => Center(
      key: const ValueKey('panel.unauthenticated'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: Text(strings.retry)),
        ],
      ),
    ),
    PanelData(:final content) => content,
  };
}

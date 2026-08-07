import 'package:flutter/material.dart';

import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';
import '../schema/resource_schema.dart' show PanelDirection;

/// Maps the panel's published [direction] to Flutter's [TextDirection].
/// `lib/schema/` stays Flutter-free by design, so this mapping lives here,
/// the one file every screen already imports for
/// [materialPanelStateBuilder], rather than a seventh new import per screen.
///
/// A screen's own `State.context` is an ANCESTOR of the `Directionality`
/// [withPanelDirection] wraps around its `build()` output, not a descendant
/// — `Directionality.of(that context)` reads whatever the *host* set, not
/// this wrap, which is exactly the bug review finding 2 (fix round 1)
/// caught in an early version of the overlay-route fix below. Any screen
/// method that opens a route (`showDialog`/`showModalBottomSheet`/a picker's
/// `builder:`) from outside a widget's own `build(BuildContext)` — where
/// `context` genuinely is positioned below the wrap — must resolve the
/// direction from the schema value directly, via this function, not by
/// calling `Directionality.of(context)`.
TextDirection textDirectionOf(PanelDirection direction) =>
    direction == PanelDirection.rtl ? TextDirection.rtl : TextDirection.ltr;

/// Wraps [child] in the [Directionality] [direction] resolves to,
/// unconditionally — not a host opt-in (design spec, "Flutter").
///
/// Every screen wraps its whole returned widget (`Scaffold` included), not
/// just the body, so the app bar — title alignment, the back button's side —
/// follows the panel's own layout too.
Widget withPanelDirection(PanelDirection direction, Widget child) {
  return Directionality(
    textDirection: textDirectionOf(direction),
    child: child,
  );
}

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

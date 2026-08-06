import 'package:flutter/widgets.dart';

/// What a screen is currently showing.
///
/// Sealed on purpose: a host's `switch` is exhaustive, so adding a state later
/// is a compile error rather than a silently blank screen.
sealed class PanelViewState {
  const PanelViewState();
}

final class PanelLoading extends PanelViewState {
  const PanelLoading();
}

final class PanelEmpty extends PanelViewState {
  const PanelEmpty({this.message});

  final String? message;
}

final class PanelFailure extends PanelViewState {
  const PanelFailure({required this.message, required this.retry});

  final String message;
  final VoidCallback retry;
}

/// The session is signed out — distinct from [PanelFailure] because "the
/// server is broken" and "you were logged out" call for different actions
/// from the user, and conflating them was the 2026-08-04 incident.
///
/// A host reaches this state by throwing a `FilamentTransportException` with
/// `statusCode: 401` from its `FilamentTransport.get()` implementation; see
/// that class's doc comment for the one line that wires it up. A host that
/// never sets `statusCode` never produces this state — every failure still
/// lands on [PanelFailure], unchanged from before this type existed.
final class PanelUnauthenticated extends PanelViewState {
  const PanelUnauthenticated({required this.message, required this.retry});

  final String message;
  final VoidCallback retry;
}

final class PanelData extends PanelViewState {
  const PanelData({required this.content});

  final Widget content;
}

/// How a host renders each state. See `MaterialPanelStateBuilder` for the
/// fallback the package ships so it runs standalone.
///
/// The returned widget is placed in the screen's `Scaffold.body`, under an
/// `AppBar` the screen already owns. A host should return a **body**, not a
/// `Scaffold`: returning a whole-screen error widget nests a second app bar
/// inside the first.
typedef PanelBodyBuilder =
    Widget Function(BuildContext context, PanelViewState state);

@Deprecated(
  'Renamed to PanelBodyBuilder, which says where its widget lands. '
  'Identical signature — change the type name only.',
)
typedef PanelStateBuilder = PanelBodyBuilder;

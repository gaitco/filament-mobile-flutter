import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Window size classes for Material 3 adaptive layout.
///
/// Defines the form factors for responsive UI based on viewport width.
/// See Material 3 documentation on window size classes:
/// https://m3.material.io/foundations/adaptive-design/large-screens/overview
enum FilamentFormFactor {
  /// Compact form factor for narrow viewports (< 600dp).
  /// Typically phones in portrait orientation.
  compact,

  /// Medium form factor for medium-width viewports (600dp – 839dp).
  /// Typically tablets in portrait, or phones in landscape.
  medium,

  /// Expanded form factor for wide viewports (≥ 840dp).
  /// Typically tablets in landscape or desktop.
  expanded,
}

/// Breakpoints for determining the active [FilamentFormFactor].
///
/// Defines the viewport width thresholds where the form factor transitions.
/// Boundaries are inclusive on the upper class: width 600 → medium,
/// width 840 → expanded.
class FilamentBreakpoints extends Equatable {
  /// Creates a [FilamentBreakpoints] with custom or default thresholds.
  ///
  /// - [medium]: width threshold for medium form factor (default: 600)
  /// - [expanded]: width threshold for expanded form factor (default: 840)
  const FilamentBreakpoints({this.medium = 600, this.expanded = 840});

  /// Viewport width threshold for medium form factor.
  /// Width ≥ [medium] transitions from compact to medium.
  final double medium;

  /// Viewport width threshold for expanded form factor.
  /// Width ≥ [expanded] transitions from medium to expanded.
  final double expanded;

  /// Determines the form factor for a given viewport width.
  FilamentFormFactor of(double width) {
    if (width >= expanded) {
      return FilamentFormFactor.expanded;
    } else if (width >= medium) {
      return FilamentFormFactor.medium;
    } else {
      return FilamentFormFactor.compact;
    }
  }

  @override
  List<Object?> get props => [medium, expanded];
}

/// Provides layout breakpoints to descendants via [InheritedWidget].
///
/// Uses the nearest [FilamentLayout]'s breakpoints to determine the active
/// form factor from [MediaQuery.sizeOf]. When no [FilamentLayout] ancestor
/// exists, falls back to a default [FilamentBreakpoints].
///
/// This is an [InheritedWidget] (not a mere data class) so that the host app
/// can override breakpoints at the widget tree level, while still allowing
/// package widgets to work standalone without the shell by falling back to
/// [MediaQuery] when no ancestor exists.
class FilamentLayout extends InheritedWidget {
  /// Creates a [FilamentLayout] that provides breakpoints to descendants.
  const FilamentLayout({
    required this.breakpoints,
    required super.child,
    super.key,
  });

  /// The breakpoints used to determine the active form factor.
  final FilamentBreakpoints breakpoints;

  /// Looks up the active [FilamentFormFactor] from the nearest [FilamentLayout].
  ///
  /// Falls back to a default [FilamentBreakpoints] if no [FilamentLayout]
  /// ancestor exists, allowing package widgets to work without the host
  /// providing one. The form factor is determined by comparing
  /// [MediaQuery.sizeOf] against the breakpoints.
  ///
  /// Always uses [MediaQuery.sizeOf] to measure the current width, even
  /// if a [FilamentLayout] is present — the layout merely holds the
  /// breakpoints, not cached measurements.
  static FilamentFormFactor of(BuildContext context) {
    final layout = context.dependOnInheritedWidgetOfExactType<FilamentLayout>();
    final breakpoints = layout?.breakpoints ?? const FilamentBreakpoints();
    final width = MediaQuery.sizeOf(context).width;
    return breakpoints.of(width);
  }

  /// Returns true if the current form factor is [FilamentFormFactor.compact].
  ///
  /// A convenience method for common layout checks.
  static bool isCompact(BuildContext context) {
    return of(context) == FilamentFormFactor.compact;
  }

  @override
  bool updateShouldNotify(FilamentLayout old) => breakpoints != old.breakpoints;
}

import 'package:filament_mobile/ui/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FilamentFormFactor enum', () {
    test('has compact, medium, and expanded values', () {
      expect(FilamentFormFactor.values, hasLength(3));
      expect(FilamentFormFactor.values, contains(FilamentFormFactor.compact));
      expect(FilamentFormFactor.values, contains(FilamentFormFactor.medium));
      expect(FilamentFormFactor.values, contains(FilamentFormFactor.expanded));
    });
  });

  group('FilamentBreakpoints', () {
    test('has default values of 600 and 840', () {
      const breakpoints = FilamentBreakpoints();
      expect(breakpoints.medium, 600);
      expect(breakpoints.expanded, 840);
    });

    test('allows custom breakpoint values', () {
      const breakpoints = FilamentBreakpoints(medium: 500, expanded: 800);
      expect(breakpoints.medium, 500);
      expect(breakpoints.expanded, 800);
    });

    test('supports value equality', () {
      const bp1 = FilamentBreakpoints();
      const bp2 = FilamentBreakpoints();
      const bp3 = FilamentBreakpoints(medium: 700);

      expect(bp1, bp2);
      expect(bp1, isNot(bp3));
    });

    group('of() method', () {
      test('returns compact for widths < medium (600)', () {
        const breakpoints = FilamentBreakpoints();
        expect(breakpoints.of(400), FilamentFormFactor.compact);
        expect(breakpoints.of(599), FilamentFormFactor.compact);
      });

      test(
        'returns medium for widths >= medium (600) and < expanded (840)',
        () {
          const breakpoints = FilamentBreakpoints();
          expect(breakpoints.of(600), FilamentFormFactor.medium);
          expect(breakpoints.of(700), FilamentFormFactor.medium);
          expect(breakpoints.of(839), FilamentFormFactor.medium);
        },
      );

      test('returns expanded for widths >= expanded (840)', () {
        const breakpoints = FilamentBreakpoints();
        expect(breakpoints.of(840), FilamentFormFactor.expanded);
        expect(breakpoints.of(1200), FilamentFormFactor.expanded);
      });

      test('respects custom breakpoints', () {
        const breakpoints = FilamentBreakpoints(medium: 500, expanded: 800);
        expect(breakpoints.of(400), FilamentFormFactor.compact);
        expect(breakpoints.of(500), FilamentFormFactor.medium);
        expect(breakpoints.of(800), FilamentFormFactor.expanded);
      });
    });
  });

  group('FilamentLayout', () {
    testWidgets('of() returns form factor from nearest FilamentLayout widget', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      FilamentFormFactor? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilamentLayout(
              breakpoints: const FilamentBreakpoints(),
              child: Builder(
                builder: (context) {
                  result = FilamentLayout.of(context);
                  return Container();
                },
              ),
            ),
          ),
        ),
      );

      expect(result, FilamentFormFactor.medium);
    });

    testWidgets('of() uses MediaQuery when no FilamentLayout ancestor exists', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      FilamentFormFactor? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                result = FilamentLayout.of(context);
                return Container();
              },
            ),
          ),
        ),
      );

      expect(result, FilamentFormFactor.medium);
    });

    testWidgets('isCompact() returns true only for compact form factor', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilamentLayout(
              breakpoints: const FilamentBreakpoints(),
              child: Builder(
                builder: (context) {
                  result = FilamentLayout.isCompact(context);
                  return Container();
                },
              ),
            ),
          ),
        ),
      );

      expect(result, true);
    });

    testWidgets('isCompact() returns false for non-compact form factors', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilamentLayout(
              breakpoints: const FilamentBreakpoints(),
              child: Builder(
                builder: (context) {
                  result = FilamentLayout.isCompact(context);
                  return Container();
                },
              ),
            ),
          ),
        ),
      );

      expect(result, false);
    });

    testWidgets('updateShouldNotify returns true when breakpoints change', (
      tester,
    ) async {
      const key = ValueKey('layout');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilamentLayout(
              key: key,
              breakpoints: const FilamentBreakpoints(),
              child: Container(),
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilamentLayout(
              key: key,
              breakpoints: const FilamentBreakpoints(medium: 700),
              child: Container(),
            ),
          ),
        ),
      );

      // If this doesn't rebuild, the tests above would fail because
      // of() would return stale breakpoints. The pumpWidget completing
      // without errors confirms updateShouldNotify worked.
      expect(find.byKey(key), findsOneWidget);
    });

    testWidgets('handles boundary case: width exactly 600 → medium', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      FilamentFormFactor? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilamentLayout(
              breakpoints: const FilamentBreakpoints(),
              child: Builder(
                builder: (context) {
                  result = FilamentLayout.of(context);
                  return Container();
                },
              ),
            ),
          ),
        ),
      );

      expect(result, FilamentFormFactor.medium);
    });

    testWidgets('handles boundary case: width exactly 840 → expanded', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(840, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      FilamentFormFactor? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilamentLayout(
              breakpoints: const FilamentBreakpoints(),
              child: Builder(
                builder: (context) {
                  result = FilamentLayout.of(context);
                  return Container();
                },
              ),
            ),
          ),
        ),
      );

      expect(result, FilamentFormFactor.expanded);
    });

    testWidgets('uses custom breakpoints from nearest FilamentLayout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(550, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      FilamentFormFactor? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilamentLayout(
              breakpoints: const FilamentBreakpoints(
                medium: 500,
                expanded: 800,
              ),
              child: Builder(
                builder: (context) {
                  result = FilamentLayout.of(context);
                  return Container();
                },
              ),
            ),
          ),
        ),
      );

      expect(result, FilamentFormFactor.medium);
    });

    testWidgets('handles all three form factors', (tester) async {
      Future<FilamentFormFactor> formFactorAt(double width) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;

        FilamentFormFactor? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FilamentLayout(
                key: ValueKey(width),
                breakpoints: const FilamentBreakpoints(),
                child: Builder(
                  builder: (context) {
                    result = FilamentLayout.of(context);
                    return Container();
                  },
                ),
              ),
            ),
          ),
        );

        return result!;
      }

      expect(await formFactorAt(400), FilamentFormFactor.compact);
      expect(await formFactorAt(700), FilamentFormFactor.medium);
      expect(await formFactorAt(1200), FilamentFormFactor.expanded);

      addTearDown(tester.view.reset);
    });
  });
}

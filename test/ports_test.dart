import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/ports/panel_view_state.dart';
import 'package:filament_mobile/ui/material_panel_state_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A host's own failure type: translated text on `message`, a debug dump on
/// `toString()` — the shape the pilot host's `ErrorHandler` has.
class _HostFailure implements Exception {
  _HostFailure(this.message);

  final String message;

  @override
  String toString() => 'ErrorHandler(code: 500, message: $message)';
}

class _Opaque {
  @override
  String toString() => 'opaque failure';
}

/// An [Error] with no `message` member — most of Dart's own Error subtypes
/// have one, so the fallback path needs a type that genuinely lacks it.
class _BareError extends Error {
  @override
  String toString() => 'bare error';
}

void _noop() {}

void main() {
  group('PanelViewState', () {
    test('a switch over it is exhaustive', () {
      // The point of sealing: adding a state must become a compile error,
      // not a silently blank screen. This test documents the five cases.
      String describe(PanelViewState state) => switch (state) {
        PanelLoading() => 'loading',
        PanelEmpty() => 'empty',
        PanelFailure() => 'failure',
        PanelUnauthenticated() => 'unauthenticated',
        PanelData() => 'data',
      };

      expect(describe(const PanelLoading()), 'loading');
      expect(describe(const PanelEmpty()), 'empty');
      expect(describe(PanelFailure(message: 'boom', retry: () {})), 'failure');
      expect(
        describe(PanelUnauthenticated(message: 'signed out', retry: () {})),
        'unauthenticated',
      );
      expect(describe(const PanelData(content: SizedBox.shrink())), 'data');
    });

    test('PanelEmpty carries an optional message', () {
      expect(const PanelEmpty().message, isNull);
      expect(const PanelEmpty(message: 'لا يوجد').message, 'لا يوجد');
    });

    test('PanelFailure carries a working retry callback', () {
      var called = 0;
      final failure = PanelFailure(message: 'boom', retry: () => called++);

      failure.retry();

      expect(called, 1);
      expect(failure.message, 'boom');
    });

    testWidgets(
      'the material builder renders the unauthenticated state distinctly',
      (tester) async {
        // Not as a generic failure — telling a signed-out user the server
        // broke is what happened on 2026-08-04.
        final builder = materialPanelStateBuilder();

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: builder(
                  context,
                  const PanelUnauthenticated(
                    message: 'signed out',
                    retry: _noop,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          find.byKey(const ValueKey('panel.unauthenticated')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        expect(find.text('signed out'), findsOneWidget);

        // Rebuild with PanelFailure and confirm the unauthenticated markers
        // are absent — the two states must not render identically.
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: builder(
                  context,
                  PanelFailure(message: 'signed out', retry: _noop),
                ),
              ),
            ),
          ),
        );

        expect(
          find.byKey(const ValueKey('panel.unauthenticated')),
          findsNothing,
        );
        expect(find.byIcon(Icons.lock_outline), findsNothing);
      },
    );
  });

  group('FilamentTransportException', () {
    // The port's doc tells a host to throw something already translated, but
    // `Exception('x').toString()` is "Exception: x" — so without this class
    // every host writes the same toString()-overriding wrapper.
    test('stringifies to the bare message, with no type prefix', () {
      const failure = FilamentTransportException('تعذّر الاتصال');

      expect(failure.toString(), 'تعذّر الاتصال');
      expect(messageOf(failure), 'تعذّر الاتصال');
    });

    test('messageOf prefers a `message` field, else toString()', () {
      expect(messageOf(_HostFailure('تعذّر الاتصال')), 'تعذّر الاتصال');
      expect(messageOf(_Opaque()), 'opaque failure');
    });

    test('messageOf reads the `message` of an Error too, not only of an '
        'Exception', () {
      // The P1 read-path spec parked a ruling to consult `message` only when
      // `error is! Error`, following Dart's own "an Error is a programmer
      // bug" convention. That narrowing never shipped, and this test pins
      // why it must not: several of Dart's own Error subtypes — ArgumentError,
      // StateError, UnsupportedError — carry a genuine, human-legible
      // `message` that their toString() buries behind a type prefix
      // ("Invalid argument (…): …"), the exact leak FilamentTransportException
      // exists to keep off the screen.
      expect(messageOf(ArgumentError('bad arg')), 'bad arg');
      expect(messageOf(StateError('bad state')), 'bad state');
    });

    test(
      'messageOf falls back to toString() for an Error with no `message`',
      () {
        // The dynamic lookup throws NoSuchMethodError on a type with no
        // `message` member; the catch is what makes that a fallback rather than
        // a crash inside an error handler.
        expect(messageOf(_BareError()), 'bare error');
      },
    );

    test('a 401 exception carries its status', () {
      const e = FilamentTransportException('signed out', statusCode: 401);

      expect(e.statusCode, 401);
    });

    test('statusCode defaults to null, so existing hosts still compile', () {
      // The whole reason for option (a): a host that never sets it keeps
      // today's behaviour rather than breaking.
      const e = FilamentTransportException('offline');

      expect(e.statusCode, isNull);
    });
  });

  group('FilamentStrings', () {
    test('defaults to English', () {
      const strings = FilamentStrings();

      expect(strings.retry, 'Retry');
      expect(strings.empty, 'Nothing here yet');
      expect(strings.searchHint, 'Search');
      expect(strings.sortTitle, 'Sort by');
      expect(strings.updateRequired, 'Please update the app');
      expect(strings.loadFailed, 'Could not load');
    });

    test(
      'every string can be overridden, so a host supplies its own translations',
      () {
        const strings = FilamentStrings(
          retry: 'إعادة المحاولة',
          empty: 'لا يوجد شيء بعد',
          searchHint: 'ابحث',
          sortTitle: 'ترتيب حسب',
          updateRequired: 'من فضلك حدّث التطبيق',
          loadFailed: 'تعذّر التحميل',
        );

        expect(strings.retry, 'إعادة المحاولة');
        expect(strings.searchHint, 'ابحث');
        expect(strings.loadFailed, 'تعذّر التحميل');
      },
    );
  });
}

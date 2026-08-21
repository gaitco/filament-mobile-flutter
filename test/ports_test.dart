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

    test('arabic() translates every field and differs from the defaults', () {
      final strings = FilamentStrings.arabic();
      const defaults = FilamentStrings();

      // Plain fields: non-empty, and not the English they replaced.
      final plain = <String, (String, String)>{
        'retry': (strings.retry, defaults.retry),
        'empty': (strings.empty, defaults.empty),
        'dashboardEmpty': (strings.dashboardEmpty, defaults.dashboardEmpty),
        'chartUnavailable': (
          strings.chartUnavailable,
          defaults.chartUnavailable,
        ),
        'searchHint': (strings.searchHint, defaults.searchHint),
        'sortTitle': (strings.sortTitle, defaults.sortTitle),
        'updateRequired': (strings.updateRequired, defaults.updateRequired),
        'loadFailed': (strings.loadFailed, defaults.loadFailed),
        'fieldRequired': (strings.fieldRequired, defaults.fieldRequired),
        'fieldEmail': (strings.fieldEmail, defaults.fieldEmail),
        'fieldUrl': (strings.fieldUrl, defaults.fieldUrl),
        'fieldPattern': (strings.fieldPattern, defaults.fieldPattern),
        'fieldConfirmed': (strings.fieldConfirmed, defaults.fieldConfirmed),
        'fieldColor': (strings.fieldColor, defaults.fieldColor),
        'save': (strings.save, defaults.save),
        'saveFailed': (strings.saveFailed, defaults.saveFailed),
        'saved': (strings.saved, defaults.saved),
        'deleteConfirmTitle': (
          strings.deleteConfirmTitle,
          defaults.deleteConfirmTitle,
        ),
        'deleteConfirmBody': (
          strings.deleteConfirmBody,
          defaults.deleteConfirmBody,
        ),
        'deleteConfirm': (strings.deleteConfirm, defaults.deleteConfirm),
        'cancel': (strings.cancel, defaults.cancel),
        'create': (strings.create, defaults.create),
        'edit': (strings.edit, defaults.edit),
        'actions': (strings.actions, defaults.actions),
        'actionFailed': (strings.actionFailed, defaults.actionFailed),
        'actionConfirm': (strings.actionConfirm, defaults.actionConfirm),
        'chooseFile': (strings.chooseFile, defaults.chooseFile),
        'uploading': (strings.uploading, defaults.uploading),
        'uploadFailed': (strings.uploadFailed, defaults.uploadFailed),
        'filePickerUnavailable': (
          strings.filePickerUnavailable,
          defaults.filePickerUnavailable,
        ),
        'fileFieldReadOnly': (
          strings.fileFieldReadOnly,
          defaults.fileFieldReadOnly,
        ),
        'addItem': (strings.addItem, defaults.addItem),
        'removeItem': (strings.removeItem, defaults.removeItem),
        'repeaterReadOnly': (
          strings.repeaterReadOnly,
          defaults.repeaterReadOnly,
        ),
        'tagHint': (strings.tagHint, defaults.tagHint),
        'seeAll': (strings.seeAll, defaults.seeAll),
        'relationEmpty': (strings.relationEmpty, defaults.relationEmpty),
        'relationFailed': (strings.relationFailed, defaults.relationFailed),
        'keepTypingToNarrowList': (
          strings.keepTypingToNarrowList,
          defaults.keepTypingToNarrowList,
        ),
        'reorderRecords': (strings.reorderRecords, defaults.reorderRecords),
        'doneReordering': (strings.doneReordering, defaults.doneReordering),
        'reorderFailed': (strings.reorderFailed, defaults.reorderFailed),
        'cancelReordering': (
          strings.cancelReordering,
          defaults.cancelReordering,
        ),
        'noRecordSelected': (
          strings.noRecordSelected,
          defaults.noRecordSelected,
        ),
        'dashboardTitle': (strings.dashboardTitle, defaults.dashboardTitle),
        'logOut': (strings.logOut, defaults.logOut),
      };
      for (final entry in plain.entries) {
        expect(
          entry.value.$1,
          isNotEmpty,
          reason: '${entry.key} must be translated',
        );
        expect(
          entry.value.$1,
          isNot(entry.value.$2),
          reason: '${entry.key} still has its English default',
        );
      }

      // The parameterised closures: bound placed in the Arabic sentence, and
      // every null combination answered.
      expect(strings.fieldMin(5), 'يجب ألا تقل القيمة عن 5');
      expect(strings.fieldMax(5), 'يجب ألا تزيد القيمة عن 5');
      expect(strings.timeFieldRange('9:00', '17:00'), 'بين 9:00 و17:00');
      expect(strings.timeFieldRange('9:00', null), 'من 9:00');
      expect(strings.timeFieldRange(null, '17:00'), 'حتى 17:00');
      expect(strings.timeFieldRange(null, null), isEmpty);
    });

    test('forLocale resolves Arabic for any `ar*` locale tag', () {
      for (final locale in ['ar', 'ar-SA', 'AR', 'ar_EG']) {
        expect(
          FilamentStrings.forLocale(locale).save,
          'حفظ',
          reason: '$locale should resolve Arabic',
        );
      }
    });

    test('forLocale falls back to the English defaults otherwise', () {
      for (final locale in ['en', 'en-GB', 'fr', null]) {
        expect(
          FilamentStrings.forLocale(locale).save,
          'Save',
          reason: '$locale should keep the defaults',
        );
      }
    });
  });
}

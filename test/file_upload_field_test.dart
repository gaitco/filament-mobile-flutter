import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/ports/filament_file_picker.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/ui/resource_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/form_fixtures.dart';
import 'support/pump_until_found.dart';

Widget formHarness({
  required FakeSource source,
  FilamentFilePicker? filePicker,
  Object? recordId,
}) {
  return MaterialApp(
    home: ResourceFormScreen(
      provider: providerFor(source, recordId: recordId),
      filePicker: filePicker,
    ),
  );
}

void main() {
  testWidgets(
    'with no filePicker, the field is read-only with the unavailable note '
    'and tapping does nothing',
    (tester) async {
      final source = FakeSource(components: fileForm());
      await tester.pumpWidget(formHarness(source: source));
      await pumpUntilFound(tester, find.byType(TextField));

      expect(
        find.text(const FilamentStrings().filePickerUnavailable),
        findsOneWidget,
      );
      expect(find.byType(TextButton), findsNothing);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(source.uploadCalls, 0);
    },
  );

  testWidgets(
    'with a picker, tapping calls it, uploads, and shows the returned '
    'path\'s filename',
    (tester) async {
      final source = FakeSource(
        components: fileForm(),
        uploadResult: const UploadSuccess('photos/abc123.png'),
      );
      await tester.pumpWidget(
        formHarness(
          source: source,
          filePicker: (field) async =>
              const PickedFile(bytes: [1, 2, 3], filename: 'me.png'),
        ),
      );
      await pumpUntilFound(tester, find.byType(TextField));

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(source.uploadCalls, 1);
      expect(source.lastUploadField, 'photo');
      expect(source.lastUploadBytes, [1, 2, 3]);
      expect(source.lastUploadFilename, 'me.png');
      expect(find.text('abc123.png'), findsOneWidget);
    },
  );

  testWidgets('a 422 lands on the field as its error and the field keeps its '
      'previous value', (tester) async {
    final source = FakeSource(
      components: fileForm(),
      record: const ResourceRecord(
        id: 7,
        attributes: {'photo': 'photos/original.png'},
      ),
      uploadResult: const UploadFailed(
        'The photo failed to upload.',
        statusCode: 422,
      ),
    );
    await tester.pumpWidget(
      formHarness(
        source: source,
        recordId: 7,
        filePicker: (field) async =>
            const PickedFile(bytes: [9], filename: 'new.png'),
      ),
    );
    await pumpUntilFound(tester, find.byType(TextField));
    expect(find.text('original.png'), findsOneWidget);

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(find.text('The photo failed to upload.'), findsOneWidget);
    // Still the record's stored file — a failed upload never clears it.
    expect(find.text('original.png'), findsOneWidget);
  });

  testWidgets('a second tap while in flight is ignored', (tester) async {
    final source = FakeSource(components: fileForm())..holdNextUpload();
    await tester.pumpWidget(
      formHarness(
        source: source,
        filePicker: (field) async =>
            const PickedFile(bytes: [1], filename: 'x.png'),
      ),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    source.completeHeldUpload();
    await tester.pumpAndSettle();

    expect(source.uploadCalls, 1);
  });

  testWidgets(
    'a readOnly: true component stays inert even with a picker supplied',
    (tester) async {
      final source = FakeSource(components: fileForm(readOnly: true));
      await tester.pumpWidget(
        formHarness(
          source: source,
          filePicker: (field) async =>
              const PickedFile(bytes: [1], filename: 'x.png'),
        ),
      );
      await pumpUntilFound(tester, find.byType(TextField));

      expect(find.byType(TextButton), findsNothing);
      // Not filePickerUnavailable: the server's own rule is why this field
      // is inert, and the note must say that, not blame a missing picker
      // that was in fact supplied.
      expect(
        find.text(const FilamentStrings().fileFieldReadOnly),
        findsOneWidget,
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(source.uploadCalls, 0);
    },
  );

  testWidgets(
    'a disabled component stays inert even with a picker supplied, and '
    'shows no note that isn\'t true',
    (tester) async {
      final source = FakeSource(components: fileForm(disabled: true));
      await tester.pumpWidget(
        formHarness(
          source: source,
          filePicker: (field) async =>
              const PickedFile(bytes: [1], filename: 'x.png'),
        ),
      );
      await pumpUntilFound(tester, find.byType(TextField));

      expect(find.byType(TextButton), findsNothing);
      // Neither note applies here — this field is neither server-readOnly
      // nor missing a picker, it is just disabled, same as any other field.
      expect(
        find.text(const FilamentStrings().fileFieldReadOnly),
        findsNothing,
      );
      expect(
        find.text(const FilamentStrings().filePickerUnavailable),
        findsNothing,
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(source.uploadCalls, 0);
    },
  );

  testWidgets(
    'a non-422 upload failure lands on the form banner, not the field',
    (tester) async {
      final source = FakeSource(
        components: fileForm(),
        record: const ResourceRecord(
          id: 7,
          attributes: {'photo': 'photos/original.png'},
        ),
        uploadResult: const UploadFailed(
          'The server had a problem.',
          statusCode: 500,
        ),
      );
      await tester.pumpWidget(
        formHarness(
          source: source,
          recordId: 7,
          filePicker: (field) async =>
              const PickedFile(bytes: [9], filename: 'new.png'),
        ),
      );
      await pumpUntilFound(tester, find.byType(TextField));

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(find.text('The server had a problem.'), findsOneWidget);
      // The field itself carries no error and its stored value survives —
      // a system fault is not a fact about this field.
      expect(find.text('original.png'), findsOneWidget);
    },
  );

  testWidgets('a picker that throws surfaces the failure instead of crashing', (
    tester,
  ) async {
    final source = FakeSource(components: fileForm());
    await tester.pumpWidget(
      formHarness(
        source: source,
        filePicker: (field) async => throw StateError('permission denied'),
      ),
    );
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(source.uploadCalls, 0);
    expect(find.text(const FilamentStrings().uploadFailed), findsOneWidget);

    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(
      button.onPressed,
      isNotNull,
      reason: 'must recover, not stay stuck spinning',
    );
  });

  group('multiple', () {
    const addKey = ValueKey('file.attachments.add');
    const recordWithTwo = ResourceRecord(
      id: 7,
      attributes: {
        'attachments': ['docs/a.pdf', 'images/b.png'],
      },
    );

    Future<void> pumpMultiple(
      WidgetTester tester,
      FakeSource source, {
      FilamentFilePicker? filePicker,
      Object? recordId,
    }) {
      return tester.pumpWidget(
        formHarness(source: source, filePicker: filePicker, recordId: recordId),
      );
    }

    testWidgets('renders the stored list as basenames', (tester) async {
      final source = FakeSource(
        components: multiFileForm(),
        record: recordWithTwo,
      );
      await pumpMultiple(tester, source, recordId: 7);
      await pumpUntilFound(tester, find.text('a.pdf'));

      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.text('b.png'), findsOneWidget);
      // Never the raw stored paths.
      expect(find.text('docs/a.pdf'), findsNothing);
    });

    testWidgets('removing an item drops it and leaves its siblings', (
      tester,
    ) async {
      final source = FakeSource(
        components: multiFileForm(),
        record: recordWithTwo,
      );
      await pumpMultiple(
        tester,
        source,
        recordId: 7,
        filePicker: (field) async =>
            const PickedFile(bytes: [1], filename: 'c.pdf'),
      );
      await pumpUntilFound(tester, find.text('a.pdf'));

      await tester.tap(find.byKey(const ValueKey('file.attachments.remove.0')));
      await tester.pumpAndSettle();

      expect(find.text('a.pdf'), findsNothing);
      expect(find.text('b.png'), findsOneWidget);
    });

    testWidgets('add picks, uploads once, and appends the returned path', (
      tester,
    ) async {
      final source = FakeSource(
        components: multiFileForm(),
        record: recordWithTwo,
        uploadResult: const UploadSuccess('docs/c.pdf'),
      );
      await pumpMultiple(
        tester,
        source,
        recordId: 7,
        filePicker: (field) async =>
            const PickedFile(bytes: [1, 2, 3], filename: 'c.pdf'),
      );
      await pumpUntilFound(tester, find.text('a.pdf'));

      await tester.tap(find.byKey(addKey));
      await tester.pumpAndSettle();

      expect(source.uploadCalls, 1);
      expect(source.lastUploadField, 'attachments');
      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.text('b.png'), findsOneWidget);
      expect(find.text('c.pdf'), findsOneWidget);
    });

    testWidgets('sequential adds append in order; a later 422 keeps what '
        'already uploaded and lands on the field', (tester) async {
      final source = FakeSource(
        components: multiFileForm(),
        record: recordWithTwo,
        uploadResult: const UploadSuccess('docs/c.pdf'),
      );
      await pumpMultiple(
        tester,
        source,
        recordId: 7,
        filePicker: (field) async =>
            const PickedFile(bytes: [1], filename: 'c.pdf'),
      );
      await pumpUntilFound(tester, find.text('a.pdf'));

      await tester.tap(find.byKey(addKey));
      await tester.pumpAndSettle();
      expect(find.text('c.pdf'), findsOneWidget);

      // The second file in the loop fails its own upload: the path the first
      // call already returned is kept — a failed upload never clears files
      // the field already holds — and the refusal is this field's own.
      source.uploadResult = const UploadFailed('Too large.', statusCode: 422);
      await tester.tap(find.byKey(addKey));
      await tester.pumpAndSettle();

      expect(source.uploadCalls, 2);
      expect(find.text('Too large.'), findsOneWidget);
      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.text('b.png'), findsOneWidget);
      expect(find.text('c.pdf'), findsOneWidget);
    });

    testWidgets('a non-422 upload failure lands on the form banner, not the '
        'field', (tester) async {
      final source = FakeSource(
        components: multiFileForm(),
        record: recordWithTwo,
        uploadResult: const UploadFailed(
          'The server had a problem.',
          statusCode: 500,
        ),
      );
      await pumpMultiple(
        tester,
        source,
        recordId: 7,
        filePicker: (field) async =>
            const PickedFile(bytes: [1], filename: 'c.pdf'),
      );
      await pumpUntilFound(tester, find.text('a.pdf'));

      await tester.tap(find.byKey(addKey));
      await tester.pumpAndSettle();

      expect(find.text('The server had a problem.'), findsOneWidget);
      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.text('b.png'), findsOneWidget);
    });

    testWidgets('the add affordance stops being offered at maxFiles, and '
        'returns once an item is removed', (tester) async {
      final source = FakeSource(
        components: multiFileForm(maxFiles: 2),
        record: recordWithTwo,
      );
      await pumpMultiple(
        tester,
        source,
        recordId: 7,
        filePicker: (field) async =>
            const PickedFile(bytes: [1], filename: 'c.pdf'),
      );
      await pumpUntilFound(tester, find.text('a.pdf'));

      // At the cap: the hint stops offering, it does not block — the server's
      // write-time array max is the rule.
      expect(find.byKey(addKey), findsNothing);

      await tester.tap(find.byKey(const ValueKey('file.attachments.remove.0')));
      await tester.pumpAndSettle();

      expect(find.byKey(addKey), findsOneWidget);
    });

    testWidgets('with no filePicker the list still renders, read-only, with '
        'the unavailable note and no affordances', (tester) async {
      final source = FakeSource(
        components: multiFileForm(),
        record: recordWithTwo,
      );
      await pumpMultiple(tester, source, recordId: 7);
      await pumpUntilFound(tester, find.text('a.pdf'));

      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.text('b.png'), findsOneWidget);
      expect(
        find.text(const FilamentStrings().filePickerUnavailable),
        findsOneWidget,
      );
      expect(find.byKey(addKey), findsNothing);
      expect(
        find.byKey(const ValueKey('file.attachments.remove.0')),
        findsNothing,
      );
    });

    testWidgets('a readOnly: true component stays inert even with a picker '
        'supplied', (tester) async {
      final source = FakeSource(
        components: multiFileForm(readOnly: true),
        record: recordWithTwo,
      );
      await pumpMultiple(
        tester,
        source,
        recordId: 7,
        filePicker: (field) async =>
            const PickedFile(bytes: [1], filename: 'c.pdf'),
      );
      await pumpUntilFound(tester, find.text('a.pdf'));

      expect(find.byKey(addKey), findsNothing);
      expect(
        find.byKey(const ValueKey('file.attachments.remove.0')),
        findsNothing,
      );
      expect(
        find.text(const FilamentStrings().fileFieldReadOnly),
        findsOneWidget,
      );
    });

    testWidgets('a disabled component stays inert and shows no note that '
        'isn\'t true', (tester) async {
      final source = FakeSource(
        components: multiFileForm(disabled: true),
        record: recordWithTwo,
      );
      await pumpMultiple(
        tester,
        source,
        recordId: 7,
        filePicker: (field) async =>
            const PickedFile(bytes: [1], filename: 'c.pdf'),
      );
      await pumpUntilFound(tester, find.text('a.pdf'));

      expect(find.byKey(addKey), findsNothing);
      expect(
        find.byKey(const ValueKey('file.attachments.remove.0')),
        findsNothing,
      );
      expect(
        find.text(const FilamentStrings().fileFieldReadOnly),
        findsNothing,
      );
      expect(
        find.text(const FilamentStrings().filePickerUnavailable),
        findsNothing,
      );
    });

    testWidgets('a scalar value under multiple: true renders instead of '
        'crashing', (tester) async {
      // A server bug, tolerated on read — the tags precedent: a non-list
      // reads as nothing stored, never a crash on a form the user can see.
      final source = FakeSource(
        components: multiFileForm(),
        record: const ResourceRecord(
          id: 7,
          attributes: {'attachments': 'docs/a.pdf'},
        ),
      );
      await pumpMultiple(
        tester,
        source,
        recordId: 7,
        filePicker: (field) async =>
            const PickedFile(bytes: [1], filename: 'c.pdf'),
      );
      await pumpUntilFound(tester, find.byKey(addKey));

      expect(tester.takeException(), isNull);
      expect(find.text('a.pdf'), findsNothing);
      expect(find.byKey(addKey), findsOneWidget);
    });
  });
}

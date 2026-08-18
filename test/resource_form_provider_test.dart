import 'package:filament_mobile/data/relation_submit_target.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/ports/filament_transport.dart';
import 'package:filament_mobile/schema/card_layout.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/load_status.dart';
import 'package:filament_mobile/state/resource_form_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/form_fixtures.dart';

void main() {
  group('/state', () {
    testWidgets('a value survives the component swap', (tester) async {
      // /state returns components and NO values. A naive replace resets the
      // form to empty and the user loses what they typed.
      final source = FakeSource(
        components: formWith(live: 'country_id'),
        stateResponse: formWith(live: 'country_id', reveal: 'city_id'),
      );
      final provider = providerFor(source);
      await provider.load();

      provider.change('name', 'Sara');
      provider.change('country_id', 3);
      await tester.pump(const Duration(milliseconds: 500));

      expect(source.stateCalls, 1);
      expect(
        provider.values['name'],
        'Sara',
        reason: 'a /state swap must not reset what the user typed',
      );
      expect(provider.values['country_id'], 3);

      provider.dispose();
    });

    testWidgets('a stale response never overwrites a fresh one', (
      tester,
    ) async {
      // P1 shipped exactly this bug in ResourceListProvider and fixed it with
      // a request-id guard. Two fast edits, first response resolving last.
      final source = FakeSource(components: formWith(live: 'country_id'));
      final provider = providerFor(source);
      await provider.load();

      source.holdNextState();
      provider.change('country_id', 3);
      await tester.pump(const Duration(milliseconds: 500));

      provider.change('country_id', 9);
      await tester.pump(const Duration(milliseconds: 500));
      source.completeHeldState(formWith(label: 'STALE'));
      await tester.pump();

      expect(source.stateCalls, 2, reason: 'both edits must have dispatched');
      expect(
        provider.components.map((c) => c.label),
        isNot(contains('STALE')),
        reason: 'the first response resolved last and must be dropped',
      );

      provider.dispose();
    });

    testWidgets('/state hidden overrides /schema hidden', (tester) async {
      // The contract's ruling: /schema's hidden is a first-paint hint,
      // /state's is authoritative.
      final source = FakeSource(
        components: formWith(hidden: 'city_id', live: 'country_id'),
        stateResponse: formWith(reveal: 'city_id', live: 'country_id'),
      );
      final provider = providerFor(source);
      await provider.load();

      expect(findComponent(provider.components, 'city_id')!.hidden, isTrue);

      provider.change('country_id', 3);
      await tester.pump(const Duration(milliseconds: 500));

      expect(findComponent(provider.components, 'city_id')!.hidden, isFalse);

      provider.dispose();
    });

    testWidgets('a field revealed by /state keeps what was already typed', (
      tester,
    ) async {
      // Rule 3's other half: revealing a field must not clear it. The seed
      // gave city_id a value while it was hidden; the swap must not drop it.
      final source = FakeSource(
        components: formWith(hidden: 'city_id', live: 'country_id'),
        stateResponse: formWith(reveal: 'city_id', live: 'country_id'),
      );
      final provider = providerFor(source);
      await provider.load();

      provider.change('city_id', 42);
      provider.change('country_id', 3);
      await tester.pump(const Duration(milliseconds: 500));

      expect(findComponent(provider.components, 'city_id')!.hidden, isFalse);
      expect(provider.values['city_id'], 42);

      provider.dispose();
    });

    testWidgets('a non-live field triggers no round-trip', (tester) async {
      // Most forms should make zero /state calls. A provider that calls on
      // every keystroke is a performance bug the contract explicitly avoids.
      final source = FakeSource(components: formWith(live: 'country_id'));
      final provider = providerFor(source);
      await provider.load();

      provider.change('name', 'Sara');
      await tester.pump(const Duration(milliseconds: 500));

      expect(source.stateCalls, 0);

      provider.dispose();
    });

    testWidgets('rapid edits to one live field debounce into one call', (
      tester,
    ) async {
      final source = FakeSource(components: formWith(live: 'country_id'));
      final provider = providerFor(source);
      await provider.load();

      provider.change('country_id', 1);
      await tester.pump(const Duration(milliseconds: 100));
      provider.change('country_id', 2);
      await tester.pump(const Duration(milliseconds: 100));
      provider.change('country_id', 3);
      await tester.pump(const Duration(milliseconds: 500));

      expect(source.stateCalls, 1);
      expect(
        source.lastStateValues!['country_id'],
        3,
        reason: 'the coalesced call carries the last edit, not the first',
      );

      provider.dispose();
    });

    testWidgets('/state is asked about the payload a submit would send', (
      tester,
    ) async {
      // Why payloadFor() and not every value the client holds: the form is
      // re-evaluated against exactly the state that would be saved, so a field
      // the write would drop cannot steer the answer either.
      final source = FakeSource(
        components: formWith(live: 'country_id', hidden: 'city_id'),
      );
      final provider = providerFor(source);
      await provider.load();

      provider.change('city_id', 42);
      provider.change('country_id', 3);
      await tester.pump(const Duration(milliseconds: 500));
      await provider.submit();

      expect(source.lastStateValues, source.lastPayload);
      expect(source.lastStateValues, isNot(contains('city_id')));

      provider.dispose();
    });

    testWidgets('a failed /state leaves the form usable', (tester) async {
      // Degrade, never block: the server revalidates on submit anyway, so a
      // failed round-trip must not strand the user in a form they cannot use.
      final source = FakeSource(
        components: formWith(live: 'country_id'),
        stateError: const FilamentTransportException('لا يوجد اتصال'),
      );
      final provider = providerFor(source);
      await provider.load();

      provider.change('country_id', 3);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        source.stateCalls,
        1,
        reason: 'without this the error path need never have run',
      );
      expect(provider.components, isNotEmpty);
      expect(provider.values['country_id'], 3);
      expect(provider.status, LoadStatus.success);

      provider.dispose();
    });

    testWidgets('dispose cancels a pending debounce', (tester) async {
      // A timer firing after disposal calls notifyListeners() on a dead
      // provider — it throws in debug and leaks in release.
      final source = FakeSource(components: formWith(live: 'country_id'));
      final provider = providerFor(source);
      await provider.load();

      provider.change('country_id', 3);
      provider.dispose();
      await tester.pump(const Duration(milliseconds: 500));

      expect(source.stateCalls, 0);
    });

    testWidgets('a response landing after dispose notifies nobody', (
      tester,
    ) async {
      // The debounce fired before the user left the screen; the response
      // arrives after. notifyListeners() here throws in debug.
      final source = FakeSource(components: formWith(live: 'country_id'));
      final provider = providerFor(source);
      await provider.load();

      source.holdNextState();
      provider.change('country_id', 3);
      await tester.pump(const Duration(milliseconds: 500));
      expect(source.stateCalls, 1);

      provider.dispose();
      source.completeHeldState(formWith(label: 'LATE'));
      await tester.pump();
    });

    testWidgets('a reload drops a /state response still in flight', (
      tester,
    ) async {
      // The same sequencing rule from the other side: the response belongs to
      // the form that existed before the reload.
      final source = FakeSource(components: formWith(live: 'country_id'));
      final provider = providerFor(source);
      await provider.load();

      source.holdNextState();
      provider.change('country_id', 3);
      await tester.pump(const Duration(milliseconds: 500));

      await provider.load();
      source.completeHeldState(formWith(label: 'STALE'));
      await tester.pump();

      expect(provider.components.map((c) => c.label), isNot(contains('STALE')));

      provider.dispose();
    });

    testWidgets('a reload cancels a debounce owed to the old form', (
      tester,
    ) async {
      final source = FakeSource(components: formWith(live: 'country_id'));
      final provider = providerFor(source);
      await provider.load();

      provider.change('country_id', 3);
      await provider.load();
      await tester.pump(const Duration(milliseconds: 500));

      expect(source.stateCalls, 0);
      expect(provider.status, LoadStatus.success);

      provider.dispose();
    });

    testWidgets('a debounce firing mid-load does not strand the form', (
      tester,
    ) async {
      // The reverse of "a reload drops a /state response still in flight", and
      // the reason the two calls do not share a counter: on one counter this
      // /state dispatch invalidates the load that is awaiting its record, and
      // load discards its OWN result — an infinite spinner over a form that
      // never seeds.
      final source = FakeSource(
        components: formWith(live: 'country_id'),
        record: const ResourceRecord(
          id: 7,
          attributes: {'id': 7, 'name': 'Stored'},
        ),
      );
      final provider = providerFor(source, recordId: 7);
      await provider.load();

      source.holdNextRecord();
      final reloading = provider.load();
      provider.change('country_id', 3);
      await tester.pump(const Duration(milliseconds: 500));
      expect(source.stateCalls, 1, reason: 'the debounce must have fired');

      source.completeHeldRecord();
      await tester.pump();
      await reloading;

      expect(provider.status, LoadStatus.success);
      expect(provider.values['name'], 'Stored');

      provider.dispose();
    });
  });

  group('load', () {
    test('an edit seeds its values from the record', () async {
      // Task 1 made GET /{resource}/{id} serialise the form's fields, which is
      // the only reason an edit form can be prefilled at all.
      final source = FakeSource(
        components: formWith(),
        record: const ResourceRecord(
          id: 7,
          attributes: {'id': 7, 'name': 'Stored', 'country_id': 3},
        ),
      );
      final provider = providerFor(source, recordId: 7);
      await provider.load();

      expect(provider.status, LoadStatus.success);
      expect(provider.values['name'], 'Stored');
      expect(provider.values['country_id'], 3);
    });

    test('a failed record load reports why', () async {
      final source = FakeSource(
        components: formWith(),
        recordError: const FilamentTransportException('لا يوجد اتصال'),
      );
      final provider = providerFor(source, recordId: 7);
      await provider.load();

      expect(provider.status, LoadStatus.failure);
      expect(provider.errorMessage, 'لا يوجد اتصال');
    });

    test('a reload clears the errors from the last submit', () async {
      // Re-seeded values with the old submission's errors still on them blames
      // the user for data that is no longer on screen.
      final source = FakeSource(
        components: formWith(),
        writeResult: const WriteInvalid({
          'name': ['الاسم مستخدم بالفعل'],
          'tags.0.id': ['Invalid tag.'],
        }),
      );
      final provider = providerFor(source, recordId: 7);
      await provider.load();
      await provider.submit();
      expect(provider.fieldErrors, isNotEmpty);
      expect(provider.formError, isNotNull);

      await provider.load();

      expect(provider.fieldErrors, isEmpty);
      expect(provider.formError, isNull);
    });
  });

  group('submit', () {
    test('client hints block before any request', () async {
      final source = FakeSource(components: formWith(required: 'name'));
      final provider = providerFor(source);
      await provider.load();

      expect(await provider.submit(), isFalse);
      expect(provider.fieldErrors, contains('name'));
      expect(
        source.writeCalls,
        0,
        reason: 'a blocked submit must not call out',
      );
    });

    test(
      'a malformed color value blocks submission before any request',
      () async {
        // P8 Task 3. Asserts the block is real, not just that an error string
        // appeared somewhere: `submit()` must return false AND the source must
        // never see a create/update call — the same two-part proof
        // "client hints block before any request" gives `required`, run
        // against a value that is present but does not parse.
        final source = FakeSource(components: colorForm());
        final provider = providerFor(source);
        await provider.load();
        provider.change('brand', 'not a color');

        expect(await provider.submit(), isFalse);
        expect(
          provider.fieldErrors['brand'],
          const FilamentStrings().fieldColor,
        );
        expect(
          source.writeCalls,
          0,
          reason: 'a blocked submit must not call out',
        );
      },
    );

    test('a color value valid only in another format still blocks — no '
        'cross-format leniency', () async {
      // rgb(51, 102, 153) is #336699's exact equivalent; the field
      // declared rgb, so a hex string is still malformed for it. Passing
      // this would mean the validator accepted a value by silently
      // reading it as a different format than the one published — the
      // provider-level half of the "never converts" property.
      final source = FakeSource(components: colorForm(format: 'rgb'));
      final provider = providerFor(source);
      await provider.load();
      provider.change('brand', '#336699');

      expect(await provider.submit(), isFalse);
      expect(provider.fieldErrors, contains('brand'));
      expect(source.writeCalls, 0);
    });

    test('fix round 1, Finding 3: an untouched malformed color from a loaded '
        'record does not block editing an unrelated field', () async {
      // The blast radius the finding names: a legacy record holding a
      // color value outside the four Filament-documented regexes (here,
      // 8-digit hex+alpha — valid CSS, not covered by
      // vendor/filament/forms/docs/17-color-picker.md's own suggested
      // pattern) must not make the WHOLE form unsubmittable the moment the
      // user edits a completely different field they never touched.
      final components = [
        SchemaComponent.fromJson(const {
          'type': 'color',
          'name': 'brand',
          'config': {'format': 'hex'},
        }, 'form[0]'),
        SchemaComponent.fromJson(const {
          'type': 'text',
          'name': 'title',
        }, 'form[1]'),
      ];
      final source = FakeSource(
        components: components,
        record: const ResourceRecord(
          id: 7,
          attributes: {'brand': '#aabbccdd', 'title': 'Old'},
        ),
      );
      final provider = providerFor(source, recordId: 7);
      await provider.load();
      provider.change('title', 'New');

      expect(await provider.submit(), isTrue);
      expect(source.lastPayload?['brand'], '#aabbccdd');
      expect(source.lastPayload?['title'], 'New');
    });

    test('a well-formed color value submits normally, unmodified', () async {
      final source = FakeSource(components: colorForm());
      final provider = providerFor(source);
      await provider.load();
      provider.change('brand', 'rgb(10, 20, 30)');

      expect(await provider.submit(), isTrue);
      expect(
        source.lastPayload?['brand'],
        'rgb(10, 20, 30)',
        reason:
            'the exact typed string must reach the payload, never a '
            'converted form',
      );
    });

    test('a server 422 replaces the client hint for that field', () async {
      final source = FakeSource(
        components: formWith(),
        writeResult: const WriteInvalid({
          'name': ['الاسم مستخدم بالفعل'],
        }),
      );
      final provider = providerFor(source);
      await provider.load();
      provider.change('name', 'Sara');

      expect(await provider.submit(), isFalse);
      expect(provider.fieldErrors['name'], 'الاسم مستخدم بالفعل');
    });

    /// P6c close-out re-review. A nested repeater is inert (the server
    /// publishes it `readOnly: true`), but its rows still travel inside the
    /// editable OUTER repeater's value, so the server can still 422 on
    /// `outer_rows.0.inner_rows.0.x`. That key used to be mapped — its first
    /// segment IS an editable repeater on screen — and then rendered nowhere:
    /// `RepeaterFieldWidget` keys errors as `<name>.<index>.<child>`, three
    /// segments, so nothing could look a five-segment key up, and the banner
    /// never saw it. Save did nothing and said nothing.
    test(
      'a 422 keyed deeper than one row reaches the banner, not a map nothing renders',
      () async {
        final source = FakeSource(
          components: nestedRepeaterForm(),
          writeResult: const WriteInvalid({
            'outer_rows.0.inner_rows.0.x': ['Nested row is invalid.'],
          }),
        );
        final provider = providerFor(source);
        await provider.load();

        expect(await provider.submit(), isFalse);
        expect(provider.formError, contains('Nested row is invalid.'));
        expect(
          provider.fieldErrors,
          isEmpty,
          reason: 'no widget can key a five-segment path',
        );
      },
    );

    /// The other half, and the claim the three-segment rule rests on: an
    /// ordinary per-item key still lands on the field. LAYOUT nesting inside
    /// an item template does not lengthen Laravel's key — a `Section`-wrapped
    /// child is still `<repeater>.<index>.<child>` (pinned server-side in
    /// `RepeaterRulesTest`) — so this is the depth the widget renders and the
    /// only depth it can.
    test(
      'a 422 keyed at exactly one row still lands on the row field',
      () async {
        final source = FakeSource(
          components: nestedRepeaterForm(),
          writeResult: const WriteInvalid({
            'outer_rows.0.note': ['Row is invalid.'],
          }),
        );
        final provider = providerFor(source);
        await provider.load();

        expect(await provider.submit(), isFalse);
        expect(provider.fieldErrors['outer_rows.0.note'], 'Row is invalid.');
        expect(provider.formError, isNull);
      },
    );

    test('a 422 key matching no field reaches the form banner', () async {
      // Never dropped. An unmappable error the user cannot see is how a form
      // becomes unsubmittable with no explanation.
      final source = FakeSource(
        components: formWith(),
        writeResult: const WriteInvalid({
          'tags.0.id': ['Invalid tag.'],
        }),
      );
      final provider = providerFor(source);
      await provider.load();

      expect(await provider.submit(), isFalse);
      expect(provider.formError, contains('Invalid tag.'));
    });

    test('a 422 carrying no usable message still explains itself', () async {
      // RestResourceDataSource degrades a malformed 422 body to WriteInvalid({})
      // (rest_resource_data_source.dart:183-186). Rejecting the submission with
      // nothing on screen is the unsubmittable-with-no-explanation case.
      final source = FakeSource(
        components: formWith(),
        writeResult: const WriteInvalid({}),
      );
      final provider = providerFor(source);
      await provider.load();

      expect(await provider.submit(), isFalse);
      expect(provider.formError, const FilamentStrings().saveFailed);
    });

    test('a 422 whose only message is empty still explains itself', () async {
      // A key IS present, so `mapped.isEmpty` alone would not catch this: the
      // field error would be an empty string, rendering as no message at all
      // under a control, with the banner silent.
      final source = FakeSource(
        components: formWith(),
        writeResult: const WriteInvalid({
          'name': [''],
        }),
      );
      final provider = providerFor(source);
      await provider.load();

      expect(await provider.submit(), isFalse);
      expect(provider.fieldErrors, isEmpty);
      expect(provider.formError, const FilamentStrings().saveFailed);
    });

    test('a denial with an empty message still explains itself', () async {
      // _messageOf() returns '' for a body with no `message` key, so a bare
      // 403 would otherwise banner an empty string.
      final source = FakeSource(
        components: formWith(),
        writeResult: const WriteDenied(''),
      );
      final provider = providerFor(source);
      await provider.load();

      expect(await provider.submit(), isFalse);
      expect(provider.formError, const FilamentStrings().saveFailed);
    });

    test('editing a field clears its server error', () async {
      final source = FakeSource(
        components: formWith(),
        writeResult: const WriteInvalid({
          'name': ['الاسم مستخدم بالفعل'],
        }),
      );
      final provider = providerFor(source);
      await provider.load();
      await provider.submit();

      provider.change('name', 'Other');
      expect(provider.fieldErrors.containsKey('name'), isFalse);
    });

    test('create posts, edit puts', () async {
      final source = FakeSource(components: formWith());

      final creating = providerFor(source);
      await creating.load();
      await creating.submit();
      expect(source.lastWrite, 'create');

      final editing = providerFor(source, recordId: 7);
      await editing.load();
      await editing.submit();
      expect(source.lastWrite, 'update');
    });

    test('a success reports true and clears the banner', () async {
      final source = FakeSource(
        components: formWith(),
        writeResult: const WriteSuccess({'id': 7}),
      );
      final provider = providerFor(source);
      await provider.load();

      expect(await provider.submit(), isTrue);
      expect(provider.formError, isNull);
      expect(provider.submitting, isFalse);
    });
  });

  group('uploadFile', () {
    test('success sets the field value', () async {
      final source = FakeSource(
        components: fileForm(),
        uploadResult: const UploadSuccess('photos/new.png'),
      );
      final provider = providerFor(source);
      await provider.load();

      await provider.uploadFile(
        'photo',
        bytes: const [1, 2, 3],
        filename: 'me.png',
      );

      expect(provider.values['photo'], 'photos/new.png');
    });

    test('success on a multiple field appends the returned path', () async {
      // One upload call per file — the endpoint is unchanged — so a multiple
      // field grows its list one path per success rather than being replaced
      // by the path the way a single-file field is.
      final source = FakeSource(
        components: multiFileForm(),
        record: const ResourceRecord(
          id: 7,
          attributes: {
            'attachments': ['docs/a.pdf'],
          },
        ),
        uploadResult: const UploadSuccess('docs/b.pdf'),
      );
      final provider = providerFor(source, recordId: 7);
      await provider.load();

      await provider.uploadFile(
        'attachments',
        bytes: const [1],
        filename: 'b.pdf',
      );

      expect(provider.values['attachments'], ['docs/a.pdf', 'docs/b.pdf']);
    });

    test(
      'success on a multiple field with no stored value starts the list',
      () async {
        final source = FakeSource(
          components: multiFileForm(),
          uploadResult: const UploadSuccess('docs/a.pdf'),
        );
        final provider = providerFor(source);
        await provider.load();

        await provider.uploadFile(
          'attachments',
          bytes: const [1],
          filename: 'a.pdf',
        );

        expect(provider.values['attachments'], ['docs/a.pdf']);
      },
    );

    test('a 422 on a multiple field keeps the stored list untouched', () async {
      final source = FakeSource(
        components: multiFileForm(),
        record: const ResourceRecord(
          id: 7,
          attributes: {
            'attachments': ['docs/a.pdf'],
          },
        ),
        uploadResult: const UploadFailed('Too large.', statusCode: 422),
      );
      final provider = providerFor(source, recordId: 7);
      await provider.load();

      await provider.uploadFile(
        'attachments',
        bytes: const [1],
        filename: 'b.pdf',
      );

      expect(provider.fieldErrors['attachments'], 'Too large.');
      expect(provider.values['attachments'], ['docs/a.pdf']);
    });

    test(
      'a success landing after dispose is dropped, not an assertion',
      () async {
        // The user backs out of the form while the upload is in flight —
        // seconds of window on mobile. Both failure branches were already
        // disposal-guarded; success routed through change(), whose bare
        // notifyListeners() asserts on a disposed ChangeNotifier and
        // propagates out of the widget's un-awaited call.
        final source = FakeSource(
          components: fileForm(),
          uploadResult: const UploadSuccess('photos/new.png'),
        );
        final provider = providerFor(source);
        await provider.load();

        source.holdNextUpload();
        final upload = provider.uploadFile(
          'photo',
          bytes: const [1],
          filename: 'x.png',
        );
        provider.dispose();
        source.completeHeldUpload();

        await upload; // must complete without throwing
      },
    );

    // Same routing rule `submit()`'s own `_applyServerErrors` follows for a
    // write's 422: a field-shaped refusal goes on the field, everything else
    // goes on the banner — tested in both directions.
    test('a 422 lands the message on the field, not the banner', () async {
      final source = FakeSource(
        components: fileForm(),
        uploadResult: const UploadFailed('Too large.', statusCode: 422),
      );
      final provider = providerFor(source);
      await provider.load();

      await provider.uploadFile('photo', bytes: const [1], filename: 'x.png');

      expect(provider.fieldErrors['photo'], 'Too large.');
      expect(provider.formError, isNull);
    });

    test('a non-422 failure reaches the banner, not the field', () async {
      final source = FakeSource(
        components: fileForm(),
        uploadResult: const UploadFailed('Server exploded.', statusCode: 500),
      );
      final provider = providerFor(source);
      await provider.load();

      await provider.uploadFile('photo', bytes: const [1], filename: 'x.png');

      expect(provider.formError, 'Server exploded.');
      expect(provider.fieldErrors.containsKey('photo'), isFalse);
    });

    test(
      'a banner-bound failure with no message falls back to strings.uploadFailed',
      () async {
        final source = FakeSource(
          components: fileForm(),
          uploadResult: const UploadFailed(null, statusCode: 500),
        );
        final provider = providerFor(source);
        await provider.load();

        await provider.uploadFile('photo', bytes: const [1], filename: 'x.png');

        expect(provider.formError, const FilamentStrings().uploadFailed);
      },
    );
  });

  group('relation write-target override (P9)', () {
    const relation = RelationDescriptor(
      key: 'tags',
      label: 'Tags',
      card: CardLayout(titleField: 'name'),
      recordKey: 'name',
    );

    ResourceFormProvider relationFormFor(
      _RelationRecordingSource source, {
      Object? recordId,
    }) => ResourceFormProvider(
      source: source,
      resource: schemaFor(source.components),
      strings: const FilamentStrings(),
      recordId: recordId,
      submitTarget: const RelationSubmitTarget(
        resourceKey: 'banners',
        recordId: 7,
        relation: relation,
      ),
    );

    test('a create submits to the relation endpoint with the parent\'s '
        'coordinates, never the child resource\'s own create', () async {
      final source = _RelationRecordingSource(components: formWith());
      final provider = relationFormFor(source);
      await provider.load();

      provider.change('name', 'sale');
      final saved = await provider.submit();

      expect(saved, isTrue);
      expect(source.relationCalls, ['create']);
      expect(source.lastParent, (resourceKey: 'banners', recordId: 7));
      expect(source.lastRelationPayload?['name'], 'sale');
      expect(
        source.writeCalls,
        0,
        reason: 'the resource write path must stay untouched',
      );
    });

    test('an update submits to the relation row URL, the form\'s recordId '
        'becoming the child segment', () async {
      final source = _RelationRecordingSource(components: formWith());
      final provider = relationFormFor(source, recordId: 'sale');
      await provider.load();

      provider.change('name', 'clearance');
      final saved = await provider.submit();

      expect(saved, isTrue);
      expect(source.relationCalls, ['update']);
      expect(source.lastChildId, 'sale');
      expect(source.lastRelationPayload?['name'], 'clearance');
      expect(source.writeCalls, 0);
    });

    test('a 422 from the relation endpoint maps onto the same fields and '
        'banner machinery a resource write uses', () async {
      final source = _RelationRecordingSource(
        components: formWith(),
        writeResult: const WriteInvalid({
          'name': ['The name field is required.'],
        }),
      );
      final provider = relationFormFor(source);
      await provider.load();

      final saved = await provider.submit();

      expect(saved, isFalse);
      expect(provider.fieldErrors['name'], 'The name field is required.');
      expect(provider.formError, isNull);
    });
  });
}

/// Records the relation writes (P9) so a test can assert WHICH endpoint the
/// submission went to and with whose coordinates — the whole point of the
/// override. Everything else defers to [FakeSource].
class _RelationRecordingSource extends FakeSource {
  _RelationRecordingSource({required super.components, super.writeResult});

  final List<String> relationCalls = [];
  ({String resourceKey, Object recordId})? lastParent;
  Object? lastChildId;
  Map<String, dynamic>? lastRelationPayload;

  @override
  Future<WriteResult> createRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Map<String, dynamic> values,
  ) {
    relationCalls.add('create');
    lastParent = (resourceKey: resourceKey, recordId: id);
    lastRelationPayload = values;
    return Future.value(writeResult);
  }

  @override
  Future<WriteResult> updateRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
    Map<String, dynamic> values,
  ) {
    relationCalls.add('update');
    lastParent = (resourceKey: resourceKey, recordId: id);
    lastChildId = childId;
    lastRelationPayload = values;
    return Future.value(writeResult);
  }
}

import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a record with no actions key parses as an empty list', () {
    // Every payload written before this feature existed must keep parsing:
    // absence is an empty list, never a null the caller has to guard.
    final record = ResourceRecord.fromJson({'id': 1, 'name': 'x'}, 'id');

    expect(record.actions, isEmpty);
  });

  test('actions parse in the order the server published them', () {
    final record = ResourceRecord.fromJson(
      {'id': 1},
      'id',
      actions: const [
        {
          'name': 'approve',
          'label': 'Approve',
          'color': 'success',
          'icon': 'heroicon-o-check',
          'confirmation': null,
        },
        {
          'name': 'archive',
          'label': 'Archive',
          'color': 'danger',
          'icon': null,
          'confirmation': {
            'heading': 'Archive this?',
            'description': 'It stops being served.',
            'submit': 'Archive',
            'cancel': 'Cancel',
          },
        },
      ],
    );

    expect(record.actions.map((a) => a.name), ['approve', 'archive']);
    expect(record.actions.first.confirmation, isNull);
    expect(record.actions.last.confirmation!.heading, 'Archive this?');
    expect(
      record.actions.last.confirmation!.description,
      'It stops being served.',
    );
  });

  test('a malformed action entry is skipped, not fatal', () {
    // The read path degrades rather than throwing on a payload it did not
    // expect — the same rule the schema parser follows.
    final record = ResourceRecord.fromJson(
      {'id': 1},
      'id',
      actions: const [
        {'label': 'Nameless'},
        {'name': 'good', 'label': 'Good'},
      ],
    );

    expect(record.actions.map((a) => a.name), ['good']);
  });

  test(
    'a throwing label degrades to the action name, not a dropped action',
    () {
      // The server keeps the action runnable even when its label closure
      // throws — see the wire-contract note. The client mirrors that: a
      // missing/non-string label is not a reason to drop the action.
      final action = RecordAction.fromJson({'name': 'approve'});

      expect(action, isNotNull);
      expect(action!.label, 'approve');
      expect(action.color, isNull);
      expect(action.icon, isNull);
    },
  );

  test('empty submit/cancel strings still mean "confirm", never "skip it"', () {
    // The server fails closed: a confirmation whose evaluation throws is
    // emitted non-null with empty submit/cancel, precisely so no client
    // treats the empty strings as "no confirmation" and runs a destructive
    // action promptless.
    final action = RecordAction.fromJson({
      'name': 'archive',
      'label': 'Archive',
      'confirmation': {
        'heading': 'Are you sure?',
        'description': null,
        'submit': '',
        'cancel': '',
      },
    });

    expect(action!.confirmation, isNotNull);
    expect(action.confirmation!.heading, 'Are you sure?');
    expect(action.confirmation!.submit, isEmpty);
    expect(action.confirmation!.cancel, isEmpty);
  });
}

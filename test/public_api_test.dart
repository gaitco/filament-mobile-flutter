// Deliberately imports ONLY the barrel — no `src`-style deep imports — so
// anything a host cannot reach through `package:filament_mobile/filament_mobile.dart`
// fails to compile here rather than in the host's codebase.
//
// The write pilot hit exactly that: `ResourceDataSource.create()` returns a
// sealed `WriteResult`, the README tells hosts to `switch` over its five
// subtypes, and `data/write_result.dart` was missing from the barrel — so no
// host could name the type it is handed. Every test in the package passed,
// because every test imports by path.
import 'package:filament_mobile/filament_mobile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a host can name and switch over every write outcome', () {
    // Written as a host would: the sealed type and all five subtypes by name.
    final outcomes = <WriteResult>[
      const WriteSuccess({'id': 1}),
      const WriteInvalid({
        'title': ['required'],
      }),
      const WriteDenied('denied'),
      const WriteGone('gone'),
      const WriteFailed('failed'),
    ];

    final labels = [
      for (final outcome in outcomes)
        switch (outcome) {
          WriteSuccess(:final data) => 'success ${data['id']}',
          WriteInvalid(:final errors) => 'invalid ${errors.keys.first}',
          WriteDenied(:final message) => message,
          WriteGone(:final message) => message,
          WriteFailed(:final message) => message,
        },
    ];

    expect(labels, ['success 1', 'invalid title', 'denied', 'gone', 'failed']);
  });

  test('a host can name the transport types the write port hands it', () {
    const response = FilamentResponse(statusCode: 422, body: {});
    expect(response.statusCode, 422);
    expect(
      const FilamentTransportException('translated').toString(),
      'translated',
    );
  });
}

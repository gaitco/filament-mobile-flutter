import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no file under lib/schema imports Flutter', () {
    final dartFiles = Directory('lib/schema')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    expect(dartFiles, isNotEmpty, reason: 'lib/schema has no Dart files');

    for (final file in dartFiles) {
      expect(
        file.readAsStringSync(),
        isNot(contains('package:flutter/')),
        reason: '${file.path} imports Flutter — schema/ must stay pure Dart',
      );
    }
  });
}

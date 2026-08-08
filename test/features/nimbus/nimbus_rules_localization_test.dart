import 'dart:convert';
import 'dart:io';

// flutter_test is provided by the Flutter test runner in this fork.
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every supported locale defines the complete rules namespace', () {
    final files =
        Directory(
            'assets/translations',
          ).listSync().whereType<File>().where((file) => file.path.endsWith('.i18n.json')).toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final base = _rules(File('assets/translations/en.i18n.json'));

    expect(files, hasLength(11));
    for (final file in files) {
      final rules = _rules(file);
      expect(rules.keys.toSet(), base.keys.toSet(), reason: '${file.path} must define every nimbus.rules key');
      for (final entry in rules.entries) {
        expect(entry.value, isA<String>(), reason: '${file.path}:${entry.key} must be a string');
        expect((entry.value as String).trim(), isNotEmpty, reason: '${file.path}:${entry.key} must not be empty');
      }
    }
  });
}

Map<String, dynamic> _rules(File file) {
  final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final nimbus = root['nimbus'] as Map<String, dynamic>;
  return nimbus['rules'] as Map<String, dynamic>;
}

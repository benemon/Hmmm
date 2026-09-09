import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _allowedPlugins = {
  'path_provider',
  'sqflite',
  'share_plus',
  'pdf',
  'printing',
  'local_auth',
};

void main() {
  test('release manifest requests no network permission and no backup', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, isNot(contains('android.permission.INTERNET')));
    expect(manifest, contains('android:allowBackup="false"'));
  });

  test('runtime dependencies stay within the allowed plugin list', () {
    final lines = File('pubspec.yaml').readAsLinesSync();
    final start = lines.indexOf('dependencies:');
    final end = lines.indexOf('dev_dependencies:');
    final plugins = lines
        .sublist(start + 1, end)
        .where((line) => RegExp(r'^  [a-z_]+:').hasMatch(line))
        .map((line) => line.trim().split(':').first)
        .where((name) => name != 'flutter')
        .toSet();
    expect(plugins, _allowedPlugins);
  });
}

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
  test('release manifest requests no network permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, isNot(contains('android.permission.INTERNET')));
  });

  test('cloud backup excludes every app file; device transfer stays open', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml')
        .readAsStringSync();
    final cloud = RegExp(
      r'<cloud-backup>(.*?)</cloud-backup>',
      dotAll: true,
    ).firstMatch(rules)!.group(1)!;
    expect(cloud, contains('<exclude domain="root" path="." />'));
    expect(cloud, isNot(contains('<include')));
    final legacy = File('android/app/src/main/res/xml/backup_rules.xml')
        .readAsStringSync();
    expect(legacy, contains('<exclude domain="root" path="." />'));
    expect(legacy, isNot(contains('<include')));
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

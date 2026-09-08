import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/dates.dart';

const _periodColumns = ['id', 'start_date', 'end_date'];
const _medicationColumns = [
  'id',
  'name',
  'dose',
  'schedule_type',
  'start_cycle_day',
  'interval_days',
  'duration_days',
  'start_date',
  'end_date',
  'active',
  'notes',
];
const _symptomTypeColumns = ['id', 'name', 'builtin'];
const _symptomEntryColumns = ['id', 'date', 'type_id', 'severity', 'note'];

class JsonBackupRepository {
  const JsonBackupRepository(this.database);

  final Database database;

  Future<String> export({required DateTime exportedAt}) =>
      exportJson(database, exportedAt: exportedAt);

  Future<void> restore(String source) => importJson(database, source);
}

Future<String> exportJson(
  Database database, {
  required DateTime exportedAt,
}) async {
  final settingsRows = await database.query(
    'settings',
    columns: ['key', 'value'],
    orderBy: 'key ASC',
  );
  return jsonEncode({
    'formatVersion': 1,
    'exportedAt': dateToIso(exportedAt),
    'periods': await database.query(
      'periods',
      columns: _periodColumns,
      orderBy: 'id ASC',
    ),
    'medications': await database.query(
      'medications',
      columns: _medicationColumns,
      orderBy: 'id ASC',
    ),
    'symptomTypes': await database.query(
      'symptom_types',
      columns: _symptomTypeColumns,
      orderBy: 'id ASC',
    ),
    'symptomEntries': await database.query(
      'symptom_entries',
      columns: _symptomEntryColumns,
      orderBy: 'id ASC',
    ),
    'settings': {
      for (final row in settingsRows)
        row['key'] as String: row['value'] as String,
    },
  });
}

Map<String, Object?> parseJsonExport(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const FormatException('Invalid JSON.');
  }
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Export must be a JSON object.');
  }
  final version = decoded['formatVersion'];
  if (version != 1) {
    throw FormatException('Unsupported format version: $version.');
  }
  _records(decoded, 'periods', _periodColumns);
  _records(decoded, 'medications', _medicationColumns);
  _records(decoded, 'symptomTypes', _symptomTypeColumns);
  _records(decoded, 'symptomEntries', _symptomEntryColumns);
  final settings = decoded['settings'];
  if (settings is! Map<String, Object?> ||
      settings.values.any((value) => value is! String)) {
    throw const FormatException('Invalid settings data.');
  }
  if (decoded['exportedAt'] is! String) {
    throw const FormatException('Invalid export date.');
  }
  return decoded;
}

Future<void> importJson(Database database, String source) async {
  final data = parseJsonExport(source);
  final periods = _records(data, 'periods', _periodColumns);
  final medications = _records(data, 'medications', _medicationColumns);
  final symptomTypes = _records(data, 'symptomTypes', _symptomTypeColumns);
  final symptomEntries = _records(data, 'symptomEntries', _symptomEntryColumns);
  final settings = data['settings']! as Map<String, Object?>;

  await database.transaction((transaction) async {
    await transaction.delete('symptom_entries');
    await transaction.delete('symptom_types');
    await transaction.delete('medications');
    await transaction.delete('periods');
    await transaction.delete('settings');

    for (final row in periods) {
      await transaction.insert('periods', row);
    }
    for (final row in medications) {
      await transaction.insert('medications', row);
    }
    for (final row in symptomTypes) {
      await transaction.insert('symptom_types', row);
    }
    for (final row in symptomEntries) {
      await transaction.insert('symptom_entries', row);
    }
    for (final setting in settings.entries) {
      await transaction.insert('settings', {
        'key': setting.key,
        'value': setting.value,
      });
    }
  });
}

List<Map<String, Object?>> _records(
  Map<String, Object?> data,
  String key,
  List<String> columns,
) {
  final value = data[key];
  if (value is! List<Object?>) {
    throw FormatException('Invalid $key data.');
  }
  final records = <Map<String, Object?>>[];
  for (final item in value) {
    if (item is! Map<String, Object?> ||
        item.keys.toSet().difference(columns.toSet()).isNotEmpty ||
        columns.any((column) => !item.containsKey(column))) {
      throw FormatException('Invalid $key record.');
    }
    records.add({for (final column in columns) column: item[column]});
  }
  return records;
}

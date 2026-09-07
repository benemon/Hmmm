import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

const _builtinSymptomTypes = [
  'migraine',
  'headache',
  'nausea',
  'hot flush',
  'night sweats',
  'insomnia',
  'brain fog',
  'joint pain',
  'fatigue',
  'low mood',
];

Future<Database> openHmmmDatabase({
  DatabaseFactory? factory,
  String? path,
}) async {
  final selectedFactory = factory ?? databaseFactory;
  final databasePath =
      path ??
      '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}hmmm.db';

  return selectedFactory.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(
      version: 2,
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      onCreate: (database, version) async {
        final batch = database.batch();
        batch.execute('''
          CREATE TABLE periods (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_date TEXT NOT NULL,
            end_date TEXT
          )
        ''');
        batch.execute('''
          CREATE TABLE medications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            dose TEXT NOT NULL,
            schedule_type TEXT NOT NULL,
            start_cycle_day INTEGER,
            duration_days INTEGER,
            start_date TEXT,
            end_date TEXT,
            active INTEGER NOT NULL,
            notes TEXT
          )
        ''');
        batch.execute('''
          CREATE TABLE symptom_types (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            builtin INTEGER NOT NULL
          )
        ''');
        batch.execute('''
          CREATE TABLE symptom_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            type_id INTEGER NOT NULL,
            severity INTEGER NOT NULL,
            note TEXT,
            FOREIGN KEY (type_id) REFERENCES symptom_types(id) ON DELETE CASCADE
          )
        ''');
        batch.execute('''
          CREATE UNIQUE INDEX symptom_entries_date_type
          ON symptom_entries(date, type_id)
        ''');
        batch.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        batch.execute('''
          CREATE TABLE window_adjustments (
            id INTEGER PRIMARY KEY,
            medication_id INTEGER NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
            source_period_start TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('ended_early','skipped')),
            end_date TEXT,
            UNIQUE(medication_id, source_period_start)
          )
        ''');
        for (final name in _builtinSymptomTypes) {
          batch.rawInsert(
            'INSERT INTO symptom_types(name, builtin) VALUES (?, ?)',
            [name, 1],
          );
        }
        await batch.commit(noResult: true);
      },
    ),
  );
}

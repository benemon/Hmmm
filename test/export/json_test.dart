import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/data/database.dart';
import 'package:hmmm/data/medication_repository.dart';
import 'package:hmmm/data/period_repository.dart';
import 'package:hmmm/data/symptom_repository.dart';
import 'package:hmmm/domain/cycle_lengths.dart';
import 'package:hmmm/domain/dates.dart';
import 'package:hmmm/domain/models.dart';
import 'package:hmmm/domain/trends.dart';
import 'package:hmmm/export/json.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  final exportedAt = DateTime(2026, 6, 15);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await openHmmmDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    await _seed(database);
  });

  tearDown(() => database.close());

  test('export, wipe, import, and export is byte-identical', () async {
    final before = await exportJson(database, exportedAt: exportedAt);

    await database.delete('symptom_entries');
    await database.delete('symptom_types');
    await database.delete('medications');
    await database.delete('periods');
    await database.delete('settings');
    await importJson(database, before);

    expect(await exportJson(database, exportedAt: exportedAt), before);
  });

  test('format version 2 is rejected before current data is changed', () async {
    final before = await exportJson(database, exportedAt: exportedAt);
    final versionTwo = before.replaceFirst(
      '"formatVersion":1',
      '"formatVersion":2',
    );

    expect(
      () => importJson(database, versionTwo),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Unsupported format version: 2.',
        ),
      ),
    );
    expect(await exportJson(database, exportedAt: exportedAt), before);
  });

  test('failed restore rolls back the table wipe', () async {
    final before = await exportJson(database, exportedAt: exportedAt);
    final invalid = parseJsonExport(before);
    final entries = invalid['symptomEntries']! as List<Object?>;
    (entries.first as Map<String, Object?>)['type_id'] = 999;

    await expectLater(
      importJson(database, jsonEncode(invalid)),
      throwsException,
    );
    expect(await exportJson(database, exportedAt: exportedAt), before);
  });

  test('export fixture produces the repository domain trend values', () async {
    final source = await exportJson(database, exportedAt: exportedAt);
    final parsed = parseJsonExport(source);
    final parsedPeriods = (parsed['periods']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(
          (row) => Period(
            id: row['id']! as int,
            start: dateFromIso(row['start_date']! as String),
            end: row['end_date'] == null
                ? null
                : dateFromIso(row['end_date']! as String),
          ),
        )
        .toList();
    final parsedEntries = (parsed['symptomEntries']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(
          (row) => SymptomEntry(
            id: row['id']! as int,
            date: dateFromIso(row['date']! as String),
            typeId: row['type_id']! as int,
            severity: row['severity']! as int,
            note: row['note'] as String?,
          ),
        )
        .toList();
    final repositoryPeriods = await PeriodRepository(database).listPeriods();
    final repositoryEntries = await SymptomRepository(database).listEntries();

    expect(
      cycleLengthsToNext(parsedPeriods),
      cycleLengthsToNext(repositoryPeriods),
    );
    expect(
      _cycleDayValues(symptomCountsByCycleDay(parsedEntries, parsedPeriods)),
      _cycleDayValues(
        symptomCountsByCycleDay(repositoryEntries, repositoryPeriods),
      ),
    );
  });
}

Future<void> _seed(Database database) async {
  final periods = PeriodRepository(database);
  final symptoms = SymptomRepository(database);
  final medications = MedicationRepository(database);
  final today = DateTime(2026, 6, 15);
  for (final period in [
    Period(start: DateTime(2026, 4, 1), end: DateTime(2026, 4, 5)),
    Period(start: DateTime(2026, 4, 29), end: DateTime(2026, 5, 3)),
    Period(start: DateTime(2026, 5, 30)),
  ]) {
    await periods.insert(period, today: today);
  }
  await medications.insert(
    Medication(
      name: 'Progesterone',
      dose: '200 mg',
      schedule: CyclicalMedicationSchedule(
        startCycleDay: 15,
        durationDays: 12,
        effectiveStart: DateTime(2026, 1, 1),
      ),
      active: true,
      notes: 'At night',
    ),
  );
  for (final date in [DateTime(2026, 4, 1), DateTime(2026, 5, 1)]) {
    await symptoms.upsertEntry(
      SymptomEntry(date: date, typeId: 1, severity: 2, note: 'Recorded'),
      today: today,
    );
  }
  await database.insert('settings', {'key': 'require_unlock', 'value': 'true'});
}

List<Object> _cycleDayValues(List<SymptomCycleDayCounts> rows) => [
  for (final row in rows)
    [
      row.typeId,
      row.totalCount,
      ...row.countsByCycleDay.entries.map(
        (entry) => '${entry.key}:${entry.value}',
      ),
      'none:${row.noCycleCount}',
    ],
];

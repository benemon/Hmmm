import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/data/database.dart';
import 'package:hmmm/data/medication_repository.dart';
import 'package:hmmm/data/period_repository.dart';
import 'package:hmmm/data/settings_repository.dart';
import 'package:hmmm/data/symptom_repository.dart';
import 'package:hmmm/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await openHmmmDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() => database.close());

  test('schema v1 exists and built-in symptom types are seeded', () async {
    final tableRows = await database.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table'",
    );
    final tables = tableRows.map((row) => row['name']).toSet();
    expect(
      tables,
      containsAll([
        'periods',
        'medications',
        'symptom_types',
        'symptom_entries',
        'settings',
      ]),
    );

    final types = await SymptomRepository(database).listTypes();
    expect(types.map((type) => type.name), [
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
    ]);
    expect(types.every((type) => type.builtin), isTrue);

    final indexes = await database.rawQuery(
      "PRAGMA index_list('symptom_entries')",
    );
    expect(
      indexes,
      contains(containsPair('name', 'symptom_entries_date_type')),
    );
  });

  test('app lock defaults off and is stored in settings', () async {
    final repository = SettingsRepository(database);

    await repository.load();

    expect(repository.requireUnlock, isFalse);
    expect(await database.query('settings'), [
      {'key': 'require_unlock', 'value': 'false'},
    ]);
  });

  test('period insert, read, update, and delete round trip', () async {
    final repository = PeriodRepository(database);
    final today = DateTime(2026, 6, 15);

    final inserted = await repository.insert(
      Period(
        start: DateTime(2026, 5, 10, 19, 30),
        end: DateTime(2026, 5, 14, 8),
      ),
      today: today,
    );
    expect(inserted.id, isNotNull);
    expect(await repository.listPeriods(), [inserted]);
    expect(
      await database.query('periods', columns: ['start_date', 'end_date']),
      [
        {'start_date': '2026-05-10', 'end_date': '2026-05-14'},
      ],
    );

    final updated = Period(
      id: inserted.id,
      start: inserted.start,
      end: DateTime(2026, 5, 15),
    );
    await repository.update(updated, today: today);
    expect(await repository.listPeriods(), [updated]);

    await repository.delete(inserted.id!);
    expect(await repository.listPeriods(), isEmpty);
  });

  test('period validation errors surface through the repository', () async {
    final repository = PeriodRepository(database);
    final today = DateTime(2026, 6, 15);
    await repository.insert(
      Period(start: DateTime(2026, 5, 10), end: DateTime(2026, 5, 14)),
      today: today,
    );

    await expectLater(
      repository.insert(
        Period(start: DateTime(2026, 5, 13), end: DateTime(2026, 5, 18)),
        today: today,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('medication insert, read, update, and delete round trip', () async {
    final repository = MedicationRepository(database);
    final inserted = await repository.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(
          startCycleDay: 15,
          durationDays: 12,
          effectiveStart: DateTime(2026, 1, 2, 18),
          effectiveEnd: DateTime(2026, 6, 3, 9),
        ),
        active: true,
        notes: 'At night',
      ),
    );

    expect(await repository.listMedications(), [inserted]);
    expect(
      await database.query(
        'medications',
        columns: [
          'schedule_type',
          'start_cycle_day',
          'duration_days',
          'start_date',
          'end_date',
        ],
      ),
      [
        {
          'schedule_type': 'cyclical',
          'start_cycle_day': 15,
          'duration_days': 12,
          'start_date': '2026-01-02',
          'end_date': '2026-06-03',
        },
      ],
    );

    final updated = Medication(
      id: inserted.id,
      name: 'Oestrogen',
      dose: '50 micrograms',
      schedule: ContinuousMedicationSchedule(
        start: DateTime(2026, 4, 1, 12),
        end: DateTime(2026, 8, 31, 20),
      ),
      active: false,
    );
    await repository.update(updated);
    expect(await repository.listMedications(), [updated]);
    expect(
      await database.query(
        'medications',
        columns: ['schedule_type', 'start_date', 'end_date'],
      ),
      [
        {
          'schedule_type': 'continuous',
          'start_date': '2026-04-01',
          'end_date': '2026-08-31',
        },
      ],
    );

    await repository.delete(inserted.id!);
    expect(await repository.listMedications(), isEmpty);
  });

  test('custom symptom type insert and read', () async {
    final repository = SymptomRepository(database);
    final inserted = await repository.insertType(
      const SymptomType(name: 'dizziness', builtin: false),
    );
    expect((await repository.listTypes()).last, inserted);
    expect(inserted.builtin, isFalse);
  });

  test('symptom entries round trip and upsert by date and type', () async {
    final repository = SymptomRepository(database);
    final type = (await repository.listTypes()).first;
    final today = DateTime(2026, 6, 15);
    final inserted = await repository.upsertEntry(
      SymptomEntry(
        date: DateTime(2026, 6, 10, 22),
        typeId: type.id!,
        severity: 1,
        note: 'Morning',
      ),
      today: today,
    );

    expect(inserted, isNotNull);
    expect(await repository.listEntries(), [inserted]);
    expect(await database.query('symptom_entries', columns: ['date']), [
      {'date': '2026-06-10'},
    ]);

    final upserted = await repository.upsertEntry(
      SymptomEntry(
        date: inserted!.date,
        typeId: inserted.typeId,
        severity: 3,
        note: 'Evening',
      ),
      today: today,
    );
    expect(upserted!.id, inserted.id);
    expect(upserted.severity, 3);
    expect(await repository.listEntries(), hasLength(1));

    final cleared = await repository.upsertEntry(
      SymptomEntry(date: inserted.date, typeId: inserted.typeId, severity: 0),
      today: today,
    );
    expect(cleared, isNull);
    expect(await repository.listEntries(), isEmpty);
  });

  test('future symptom validation surfaces through the repository', () async {
    final repository = SymptomRepository(database);
    final type = (await repository.listTypes()).first;

    await expectLater(
      repository.upsertEntry(
        SymptomEntry(
          date: DateTime(2026, 6, 16),
          typeId: type.id!,
          severity: 2,
        ),
        today: DateTime(2026, 6, 15),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}

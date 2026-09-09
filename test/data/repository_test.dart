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

  test('schema v2 exists and built-in symptom types are seeded', () async {
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
        'window_adjustments',
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
    final adjustmentColumns = await database.rawQuery(
      "PRAGMA table_info('window_adjustments')",
    );
    expect(
      adjustmentColumns.map((column) => column['name']),
      containsAll(['source_period_start', 'start_date', 'end_date']),
    );
    final medicationColumns = await database.rawQuery(
      "PRAGMA table_info('medications')",
    );
    expect(
      medicationColumns.map((column) => column['name']),
      contains('interval_days'),
    );
  });

  test('settings defaults are stored', () async {
    final repository = SettingsRepository(database);

    await repository.load();

    expect(repository.requireUnlock, isFalse);
    expect(repository.themeMode, AppThemeMode.system);
    expect(
      await database.query('settings'),
      containsAll([
        {'key': 'require_unlock', 'value': 'false'},
        {'key': 'theme_mode', 'value': 'system'},
      ]),
    );
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

  test('fixed-interval medication stores its anchor and interval', () async {
    final repository = MedicationRepository(database);
    final inserted = await repository.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: FixedIntervalMedicationSchedule(
          anchor: DateTime(2026, 3, 4, 18),
          intervalDays: 28,
          durationDays: 12,
          effectiveEnd: DateTime(2026, 6, 15, 9),
        ),
        active: false,
      ),
    );

    expect(await repository.listMedications(), [inserted]);
    expect(
      await database.query(
        'medications',
        columns: [
          'schedule_type',
          'start_cycle_day',
          'interval_days',
          'duration_days',
          'start_date',
          'end_date',
        ],
      ),
      [
        {
          'schedule_type': 'fixed_interval',
          'start_cycle_day': null,
          'interval_days': 28,
          'duration_days': 12,
          'start_date': '2026-03-04',
          'end_date': '2026-06-15',
        },
      ],
    );
  });

  test(
    'window adjustment upsert stores combined record and delete cascades',
    () async {
      final repository = MedicationRepository(database);
      var notifications = 0;
      repository.addListener(() => notifications++);
      final medication = await repository.insert(
        Medication(
          name: 'Progesterone',
          dose: '200 mg',
          schedule: CyclicalMedicationSchedule(
            startCycleDay: 15,
            durationDays: 12,
          ),
          active: true,
        ),
      );
      final sourcePeriodStart = DateTime(2026, 6, 1);
      await repository.setAdjustment(
        WindowAdjustment(
          medicationId: medication.id!,
          sourcePeriodStart: sourcePeriodStart,
          kind: WindowAdjustmentKind.endedEarly,
          endDate: DateTime(2026, 6, 18),
        ),
      );
      final adjustmentId = (await database.query(
        'window_adjustments',
        columns: ['id'],
      )).single['id'];

      await repository.setAdjustment(
        WindowAdjustment(
          medicationId: medication.id!,
          sourcePeriodStart: sourcePeriodStart,
          kind: WindowAdjustmentKind.endedEarly,
          startDate: DateTime(2026, 6, 16),
          endDate: DateTime(2026, 6, 18),
        ),
      );

      expect(await repository.listAdjustments(), [
        WindowAdjustment(
          medicationId: medication.id!,
          sourcePeriodStart: sourcePeriodStart,
          kind: WindowAdjustmentKind.endedEarly,
          startDate: DateTime(2026, 6, 16),
          endDate: DateTime(2026, 6, 18),
        ),
      ]);
      expect(
        (await database.query(
          'window_adjustments',
          columns: ['id'],
        )).single['id'],
        adjustmentId,
      );
      expect(notifications, 3);

      await repository.setAdjustment(
        WindowAdjustment(
          medicationId: medication.id!,
          sourcePeriodStart: sourcePeriodStart,
          kind: WindowAdjustmentKind.skipped,
          startDate: DateTime(2026, 6, 16),
          endDate: DateTime(2026, 6, 18),
        ),
      );
      expect(
        (await repository.listAdjustments()).single.kind,
        WindowAdjustmentKind.skipped,
      );
      expect(
        (await repository.listAdjustments()).single.startDate,
        DateTime(2026, 6, 16),
      );
      expect(notifications, 4);

      await repository.clearAdjustment(medication.id!, sourcePeriodStart);
      expect(await repository.listAdjustments(), isEmpty);
      expect(notifications, 5);

      await repository.setAdjustment(
        WindowAdjustment(
          medicationId: medication.id!,
          sourcePeriodStart: sourcePeriodStart,
          kind: WindowAdjustmentKind.skipped,
        ),
      );
      await repository.delete(medication.id!);
      expect(await repository.listAdjustments(), isEmpty);
    },
  );

  test('custom symptom type insert and read', () async {
    final repository = SymptomRepository(database);
    final inserted = await repository.insertType(
      const SymptomType(name: 'dizziness', builtin: false),
    );
    expect((await repository.listTypes()).last, inserted);
    expect(inserted.builtin, isFalse);
  });

  test('entryCountsByType groups entries by symptom type', () async {
    final repository = SymptomRepository(database);
    final today = DateTime(2026, 6, 15);
    for (final entry in [
      SymptomEntry(date: DateTime(2026, 6, 10), typeId: 1, severity: 1),
      SymptomEntry(date: DateTime(2026, 6, 11), typeId: 1, severity: 2),
      SymptomEntry(date: DateTime(2026, 6, 12), typeId: 2, severity: 3),
    ]) {
      await repository.upsertEntry(entry, today: today);
    }

    expect(await repository.entryCountsByType(), {1: 2, 2: 1});
  });

  test('deleting a symptom type cascades only its entries', () async {
    final repository = SymptomRepository(database);
    final custom = await repository.insertType(
      const SymptomType(name: 'dizziness', builtin: false),
    );
    final today = DateTime(2026, 6, 15);
    await repository.upsertEntry(
      SymptomEntry(
        date: DateTime(2026, 6, 10),
        typeId: custom.id!,
        severity: 2,
      ),
      today: today,
    );
    await repository.upsertEntry(
      SymptomEntry(date: DateTime(2026, 6, 11), typeId: 1, severity: 1),
      today: today,
    );

    await repository.deleteType(custom.id!);

    expect(await repository.listTypes(), isNot(contains(custom)));
    final entries = await repository.listEntries();
    expect(entries, hasLength(1));
    expect(entries.single.typeId, 1);
  });

  test('symptom entries round trip and upsert by date and type', () async {
    final repository = SymptomRepository(database);
    final type = (await repository.listTypes()).first;
    final today = DateTime(2026, 6, 15);
    await repository.upsertEntry(
      SymptomEntry(
        date: DateTime(2026, 6, 10, 22),
        typeId: type.id!,
        severity: 1,
        note: 'Morning',
      ),
      today: today,
    );

    final inserted = (await repository.listEntries()).single;
    expect(await database.query('symptom_entries', columns: ['date']), [
      {'date': '2026-06-10'},
    ]);

    await repository.upsertEntry(
      SymptomEntry(
        date: inserted.date,
        typeId: inserted.typeId,
        severity: 3,
        note: 'Evening',
      ),
      today: today,
    );
    final upserted = (await repository.listEntries()).single;
    expect(upserted.id, inserted.id);
    expect(upserted.severity, 3);

    await repository.upsertEntry(
      SymptomEntry(date: inserted.date, typeId: inserted.typeId, severity: 0),
      today: today,
    );
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

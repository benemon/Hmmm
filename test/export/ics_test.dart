import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/data/database.dart';
import 'package:hmmm/data/medication_repository.dart';
import 'package:hmmm/domain/hrt_window.dart';
import 'package:hmmm/domain/models.dart';
import 'package:hmmm/export/ics.dart';
import 'package:hmmm/ui/settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('all-day events use exclusive DTEND dates and CRLF lines', () {
    final output = buildIcs(
      periods: [
        Period(start: DateTime(2026, 5, 10), end: DateTime(2026, 5, 14)),
      ],
      windowsByMedication: [
        IcsMedicationWindows(
          name: 'progesterone',
          windows: [
            MedicationWindow(
              start: DateTime(2026, 5, 20),
              end: DateTime(2026, 5, 31),
              sourcePeriodStart: DateTime(2026, 5, 10),
            ),
          ],
        ),
      ],
      symptomDaysByType: [
        IcsSymptomDays(name: 'migraine', dates: [DateTime(2026, 5, 25)]),
      ],
      range: DateRange(start: DateTime(2026, 5, 1), end: DateTime(2026, 5, 31)),
      exportedAt: DateTime(2026, 6, 1),
    );

    expect(output, contains('VERSION:2.0\r\n'));
    expect(output, contains('DTSTAMP:20260601T000000Z\r\n'));
    expect(output, contains('PRODID:-//Hmmm//Hmmm 1.0//EN\r\n'));
    expect(
      output,
      contains(
        'SUMMARY:Period\r\n'
        'DTSTART;VALUE=DATE:20260510\r\n'
        'DTEND;VALUE=DATE:20260515\r\n',
      ),
    );
    expect(
      output,
      contains(
        'SUMMARY:progesterone\r\n'
        'DTSTART;VALUE=DATE:20260520\r\n'
        'DTEND;VALUE=DATE:20260601\r\n',
      ),
    );
    expect(
      output,
      contains(
        'SUMMARY:migraine\r\n'
        'DTSTART;VALUE=DATE:20260525\r\n'
        'DTEND;VALUE=DATE:20260526\r\n',
      ),
    );
    expect(output.replaceAll('\r\n', ''), isNot(contains('\n')));
  });

  test('UIDs are stable and use a cyclical window source period', () {
    final arguments = (
      periods: <Period>[],
      windows: [
        IcsMedicationWindows(
          name: 'Progesterone',
          windows: [
            MedicationWindow(
              start: DateTime(2026, 5, 24),
              end: DateTime(2026, 6, 4),
              sourcePeriodStart: DateTime(2026, 5, 10),
            ),
          ],
        ),
      ],
      symptoms: <IcsSymptomDays>[],
      range: DateRange(start: DateTime(2026, 5, 20), end: DateTime(2026, 6, 4)),
    );

    final first = buildIcs(
      periods: arguments.periods,
      windowsByMedication: arguments.windows,
      symptomDaysByType: arguments.symptoms,
      range: arguments.range,
      exportedAt: DateTime(2026, 6, 1),
    );
    final second = buildIcs(
      periods: arguments.periods,
      windowsByMedication: arguments.windows,
      symptomDaysByType: arguments.symptoms,
      range: arguments.range,
      exportedAt: DateTime(2026, 6, 1),
    );

    expect(first, second);
    expect(
      first,
      contains('UID:hmmm-medication-progesterone-2026-05-10@hmmm.local\r\n'),
    );
  });

  test('shared adjusted-window assembly omits a skipped ICS event', () async {
    final database = await openHmmmDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    final repository = MedicationRepository(database);
    final medication = await repository.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(startCycleDay: 1, durationDays: 4),
        active: true,
      ),
    );
    final period = Period(start: DateTime(2026, 6, 1));
    await repository.setAdjustment(
      WindowAdjustment(
        medicationId: medication.id!,
        sourcePeriodStart: period.start,
        kind: WindowAdjustmentKind.skipped,
      ),
    );
    final range = DateRange(
      start: DateTime(2026, 6, 1),
      end: DateTime(2026, 6, 30),
    );
    final windows = await repository.loadAdjustedWindows(
      medications: [medication],
      periods: [period],
      range: range,
      today: DateTime(2026, 6, 15),
    );

    final output = buildIcs(
      periods: const [],
      windowsByMedication: [
        IcsMedicationWindows(
          name: medication.name,
          windows: windows.windowsByMedicationId[medication.id!]!,
        ),
      ],
      symptomDaysByType: const [],
      range: range,
      exportedAt: DateTime(2026, 6, 15),
    );

    expect(output, isNot(contains('SUMMARY:Progesterone')));
    expect(output, isNot(contains('hmmm-medication-progesterone')));
    repository.dispose();
    await database.close();
  });

  test('shifted ICS event moves dates but keeps its source UID', () async {
    final database = await openHmmmDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    final repository = MedicationRepository(database);
    final medication = await repository.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(startCycleDay: 1, durationDays: 4),
        active: true,
      ),
    );
    final period = Period(start: DateTime(2026, 6, 1));
    await repository.setAdjustment(
      WindowAdjustment(
        medicationId: medication.id!,
        sourcePeriodStart: period.start,
        kind: WindowAdjustmentKind.startedOn,
        startDate: DateTime(2026, 6, 3),
      ),
    );
    final range = DateRange(
      start: DateTime(2026, 6, 1),
      end: DateTime(2026, 6, 30),
    );
    final windows = await repository.loadAdjustedWindows(
      medications: [medication],
      periods: [period],
      range: range,
      today: DateTime(2026, 6, 15),
    );

    final output = buildIcs(
      periods: const [],
      windowsByMedication: [
        IcsMedicationWindows(
          name: medication.name,
          windows: windows.windowsByMedicationId[medication.id!]!,
        ),
      ],
      symptomDaysByType: const [],
      range: range,
      exportedAt: DateTime(2026, 6, 15),
    );

    expect(
      output,
      contains('UID:hmmm-medication-progesterone-2026-06-01@hmmm.local'),
    );
    expect(output, contains('DTSTART;VALUE=DATE:20260603'));
    expect(output, contains('DTEND;VALUE=DATE:20260607'));
    repository.dispose();
    await database.close();
  });

  test('fixed-interval UID uses the unadjusted anchor-derived start', () async {
    final database = await openHmmmDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    final repository = MedicationRepository(database);
    final medication = await repository.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: FixedIntervalMedicationSchedule(
          anchor: DateTime(2026, 3, 4),
          intervalDays: 28,
          durationDays: 12,
        ),
        active: true,
      ),
    );
    await repository.setAdjustment(
      WindowAdjustment(
        medicationId: medication.id!,
        sourcePeriodStart: DateTime(2026, 4, 1),
        kind: WindowAdjustmentKind.startedOn,
        startDate: DateTime(2026, 4, 3),
      ),
    );
    final range = DateRange(
      start: DateTime(2026, 4, 1),
      end: DateTime(2026, 4, 30),
    );
    final windows = await repository.loadAdjustedWindows(
      medications: [medication],
      periods: const [],
      range: range,
      today: DateTime(2026, 4, 2),
    );
    final output = buildIcs(
      periods: const [],
      windowsByMedication: [
        IcsMedicationWindows(
          name: medication.name,
          windows: windows.windowsByMedicationId[medication.id!]!,
        ),
      ],
      symptomDaysByType: const [],
      range: range,
      exportedAt: DateTime(2026, 4, 2),
    );

    expect(
      output,
      contains('UID:hmmm-medication-progesterone-2026-04-01@hmmm.local'),
    );
    expect(output, contains('DTSTART;VALUE=DATE:20260403'));
    repository.dispose();
    await database.close();
  });

  test('effective export range includes a course starting after today', () {
    final today = DateTime(2026, 6, 15);
    final period = Period(start: DateTime(2026, 6, 2));
    final medication = Medication(
      id: 1,
      name: 'Progesterone',
      dose: '200 mg',
      schedule: CyclicalMedicationSchedule(startCycleDay: 15, durationDays: 12),
      active: true,
    );
    final rangeEnd = latestDerivedWindowEnd(
      medications: [medication],
      periods: [period],
      adjustments: const [],
      today: today,
    );
    final range = rangeForMonths(today, 1, rangeEnd);
    final windows = deriveAdjustedWindows(
      medication,
      [period],
      range,
      const [],
      today: today,
    );

    final output = buildIcs(
      periods: [period],
      windowsByMedication: [
        IcsMedicationWindows(name: medication.name, windows: windows),
      ],
      symptomDaysByType: const [],
      range: range,
      exportedAt: today,
    );

    expect(range.end, DateTime(2026, 6, 27));
    expect(output, contains('DTSTART;VALUE=DATE:20260616'));
    expect(output, contains('DTEND;VALUE=DATE:20260628'));
  });
}

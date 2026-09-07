import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/data/database.dart';
import 'package:hmmm/data/medication_repository.dart';
import 'package:hmmm/data/period_repository.dart';
import 'package:hmmm/data/settings_repository.dart';
import 'package:hmmm/data/symptom_repository.dart';
import 'package:hmmm/domain/models.dart';
import 'package:hmmm/export/json.dart';
import 'package:hmmm/main.dart';
import 'package:hmmm/app_authenticator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late PeriodRepository periods;
  late MedicationRepository medications;
  late SymptomRepository symptoms;
  late SettingsRepository settings;
  final today = DateTime(2026, 6, 15);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await openHmmmDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    periods = PeriodRepository(database);
    medications = MedicationRepository(database);
    symptoms = SymptomRepository(database);
    settings = SettingsRepository(database);
    await settings.load();
  });

  tearDown(() async {
    periods.dispose();
    medications.dispose();
    symptoms.dispose();
    await database.close();
  });

  testWidgets('calendar renders a seeded month and opens its day sheet', (
    tester,
  ) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 9), end: DateTime(2026, 6, 12)),
      today: today,
    );
    await _pumpApp(
      tester,
      periods,
      medications,
      symptoms,
      settings,
      database,
      today,
    );

    expect(find.text('June 2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-10')));
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('day-detail-2026-06-10')), findsOneWidget);
    expect(find.text('Period recorded'), findsWidgets);
  });

  testWidgets('calendar keeps stopped medication history visible', (
    tester,
  ) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 5)),
      today: today,
    );
    await medications.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(
          startCycleDay: 1,
          durationDays: 3,
          effectiveEnd: DateTime(2026, 6, 1),
        ),
        active: false,
      ),
    );
    await _pumpApp(
      tester,
      periods,
      medications,
      symptoms,
      settings,
      database,
      today,
    );

    expect(find.text('Progesterone (stopped)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-02')));
    await _pumpFrames(tester);

    expect(find.text('Progesterone  200 mg'), findsOneWidget);
  });

  testWidgets('symptom chip cycles through clear and persists after re-pump', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      periods,
      medications,
      symptoms,
      settings,
      database,
      today,
    );
    await tester.tap(find.byKey(const ValueKey('day-2026-06-10')));
    await _pumpFrames(tester);
    final chip = find.byKey(const ValueKey('symptom-chip-2026-06-10-1'));

    await tester.tap(chip);
    await _pumpFrames(tester);
    expect((await symptoms.listEntries()).single.severity, 1);

    await tester.tapAt(const Offset(10, 10));
    await _pumpFrames(tester);
    await _pumpApp(
      tester,
      periods,
      medications,
      symptoms,
      settings,
      database,
      today,
    );
    await tester.tap(find.byKey(const ValueKey('day-2026-06-10')));
    await _pumpFrames(tester);
    for (var tap = 0; tap < 3; tap++) {
      await tester.tap(chip);
      await _pumpFrames(tester);
    }

    expect(await symptoms.listEntries(), isEmpty);
  });

  testWidgets('period started then period ended writes a closed period', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      periods,
      medications,
      symptoms,
      settings,
      database,
      today,
    );
    await tester.tap(find.byKey(const ValueKey('day-2026-06-10')));
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('period-start-2026-06-10')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('period-end-2026-06-10')));
    await _pumpFrames(tester);

    final saved = (await periods.listPeriods()).single;
    expect(saved.start, DateTime(2026, 6, 10));
    expect(saved.end, DateTime(2026, 6, 10));
  });

  testWidgets('overlapping period add shows repository validation message', (
    tester,
  ) async {
    await periods.insert(
      Period(start: today, end: today),
      today: today,
    );
    await _pumpApp(
      tester,
      periods,
      medications,
      symptoms,
      settings,
      database,
      today,
    );

    await tester.tap(find.text('Settings'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Period records'));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('add-period')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('apply-period')));
    await _pumpFrames(tester);

    expect(
      find.text('Period dates overlap an existing period.'),
      findsOneWidget,
    );
  });

  testWidgets('medication add and stop flow persists effective end', (
    tester,
  ) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 5)),
      today: today,
    );
    await _pumpApp(
      tester,
      periods,
      medications,
      symptoms,
      settings,
      database,
      today,
    );

    await tester.tap(find.text('Settings'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Medications'));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('add-medication')));
    await _pumpFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey('medication-name')),
      'Progesterone',
    );
    await tester.enterText(
      find.byKey(const ValueKey('medication-dose')),
      '200 mg',
    );
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await _pumpFrames(tester);

    final inserted = (await medications.listMedications()).single;
    expect(inserted.active, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpApp(
      tester,
      periods,
      medications,
      symptoms,
      settings,
      database,
      today,
    );
    await tester.tap(find.text('Settings'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Medications'));
    await _pumpFrames(tester);
    expect(find.textContaining('from cycle day 15, 12 days'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('medication-actions-${inserted.id}')));
    await _pumpFrames(tester);
    await tester.tap(find.text('Stop'));
    await _pumpFrames(tester);
    expect(
      find.text('Stop Progesterone? Historical windows are kept.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('confirm-stop-medication')));
    await _pumpFrames(tester);

    final persisted = (await MedicationRepository(
      database,
    ).listMedications()).single;
    expect(persisted.active, isFalse);
    expect(
      (persisted.schedule as CyclicalMedicationSchedule).effectiveEnd,
      today,
    );
    expect(
      find.textContaining('from cycle day 15, 12 days (stopped 15 Jun 2026)'),
      findsOneWidget,
    );
  });

  testWidgets(
    'trends renders fixture counts and symptom entries are auditable',
    (tester) async {
      for (final period in [
        Period(start: DateTime(2026, 4, 1), end: DateTime(2026, 4, 5)),
        Period(start: DateTime(2026, 4, 29), end: DateTime(2026, 5, 3)),
        Period(start: DateTime(2026, 5, 30)),
      ]) {
        await periods.insert(period, today: today);
      }
      for (final entry in [
        SymptomEntry(
          date: DateTime(2026, 3, 31),
          typeId: 1,
          severity: 1,
          note: 'Before first period',
        ),
        SymptomEntry(date: DateTime(2026, 4, 1), typeId: 1, severity: 2),
        SymptomEntry(date: DateTime(2026, 4, 2), typeId: 1, severity: 3),
        SymptomEntry(date: DateTime(2026, 5, 1), typeId: 1, severity: 1),
        SymptomEntry(date: DateTime(2026, 4, 2), typeId: 2, severity: 1),
      ]) {
        await symptoms.upsertEntry(entry, today: today);
      }
      await _pumpApp(
        tester,
        periods,
        medications,
        symptoms,
        settings,
        database,
        today,
      );

      await tester.tap(find.text('Trends'));
      await _pumpFrames(tester);

      expect(find.text('3 recorded'), findsOneWidget);
      expect(find.text('3 mo: n=2, min 28, max 31, mean 29.5'), findsOneWidget);
      expect(find.text('5 entries over 3 months'), findsOneWidget);
      expect(find.text('d1×1 d2×1 d3×1 no cycle×1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('trend-symptom-1')));
      await _pumpFrames(tester);

      expect(find.text('31 Mar 2026'), findsOneWidget);
      expect(find.text('severity 1\nBefore first period'), findsOneWidget);
      expect(find.text('1 May 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await _pumpFrames(tester);
      await tester.scrollUntilVisible(
        find.text('Monthly counts'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _pumpFrames(tester);

      expect(find.text('5 entries over 12 months'), findsOneWidget);
      expect(find.byKey(const ValueKey('monthly-count-1-11')), findsOneWidget);
    },
  );
}

Future<void> _pumpApp(
  WidgetTester tester,
  PeriodRepository periods,
  MedicationRepository medications,
  SymptomRepository symptoms,
  SettingsRepository settings,
  Database database,
  DateTime today,
) async {
  await tester.pumpWidget(
    HmmmApp(
      periodRepository: periods,
      medicationRepository: medications,
      symptomRepository: symptoms,
      settingsRepository: settings,
      backupRepository: JsonBackupRepository(database),
      authenticator: _FakeAuthenticator(),
      today: today,
    ),
  );
  await _pumpFrames(tester);
}

class _FakeAuthenticator implements AppAuthenticator {
  @override
  Future<bool> authenticate() async => true;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

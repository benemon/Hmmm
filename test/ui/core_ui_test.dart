import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:hmmm/ui/calendar.dart';
import 'package:hmmm/ui/day_detail.dart';
import 'package:hmmm/ui/theme.dart';
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

  Future<void> pumpApp(
    WidgetTester tester, {
    SettingsRepository? withSettings,
  }) async {
    await tester.pumpWidget(
      HmmmApp(
        periodRepository: periods,
        medicationRepository: medications,
        symptomRepository: symptoms,
        settingsRepository: withSettings ?? settings,
        backupRepository: JsonBackupRepository(database),
        authenticator: _FakeAuthenticator(),
        today: today,
      ),
    );
    await _pumpFrames(tester);
  }

  testWidgets('calendar renders a seeded month and opens its day sheet', (
    tester,
  ) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 9), end: DateTime(2026, 6, 12)),
      today: today,
    );
    await pumpApp(tester);

    expect(find.byKey(const ValueKey('month-2026-06')), findsOneWidget);
    final semanticsHandle = tester.ensureSemantics();
    final day = find.byKey(const ValueKey('day-2026-06-10'));
    expect(tester.getSemantics(day).label, '10 June 2026. Period day 2.');
    semanticsHandle.dispose();
    await tester.tap(day);
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('day-detail-2026-06-10')), findsOneWidget);
    expect(find.text('9 Jun 2026 – 12 Jun 2026'), findsOneWidget);
    expect(find.text('Wednesday · cycle day 2'), findsOneWidget);
    expect(find.text('4 recorded days, end recorded'), findsOneWidget);
  });

  testWidgets('closed-period day offers delete without a start action', (
    tester,
  ) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 9), end: DateTime(2026, 6, 12)),
      today: today,
    );
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('day-2026-06-10')));
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('period-start-2026-06-10')), findsNothing);
    expect(
      find.byKey(const ValueKey('period-delete-2026-06-10')),
      findsOneWidget,
    );
  });

  testWidgets('home navigation renders uppercase labels', (tester) async {
    await pumpApp(tester);

    expect(find.text('CALENDAR'), findsOneWidget);
  });

  testWidgets('navigation theme resolves selected and unselected ink colors', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final theme = hmmmTheme(brightness);
      final navigation = theme.navigationBarTheme;
      final selected = {WidgetState.selected};
      final unselected = <WidgetState>{};

      expect(
        navigation.iconTheme!.resolve(selected)!.color,
        theme.colorScheme.onSurface,
      );
      expect(
        navigation.iconTheme!.resolve(unselected)!.color,
        theme.colorScheme.onSurfaceVariant,
      );
      expect(
        navigation.labelTextStyle!.resolve(selected)!.color,
        theme.colorScheme.onSurface,
      );
      expect(
        navigation.labelTextStyle!.resolve(unselected)!.color,
        theme.colorScheme.onSurfaceVariant,
      );
    }
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
    await pumpApp(tester);

    expect(find.text('Progesterone (stopped)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-02')));
    await _pumpFrames(tester);

    expect(find.text('Progesterone'), findsWidgets);
    expect(find.text('200 mg'), findsOneWidget);
  });

  testWidgets('course ended early and restored updates calendar bands', (
    tester,
  ) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 5)),
      today: today,
    );
    final medication = await medications.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(startCycleDay: 1, durationDays: 4),
        active: true,
      ),
    );
    await pumpApp(tester);
    final laterBand = find.byKey(
      ValueKey('medication-band-2026-06-04-${medication.id}'),
    );
    expect(laterBand, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('day-2026-06-02')));
    await _pumpFrames(tester);
    final actions = find.byKey(
      ValueKey('course-actions-${medication.id}-2026-06-01'),
    );
    expect(
      find.text('day 1–4 of the 1 Jun cycle · starts 1 Jun'),
      findsOneWidget,
    );
    await tester.tap(actions);
    await _pumpFrames(tester);
    await tester.tap(find.text('Course ended 2 Jun 2026'));
    await _pumpFrames(tester);

    expect(find.text('ended early 2 Jun 2026'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await _pumpFrames(tester);
    expect(
      find.byKey(ValueKey('medication-band-2026-06-02-${medication.id}')),
      findsOneWidget,
    );
    expect(laterBand, findsNothing);

    await tester.tap(find.byKey(const ValueKey('day-2026-06-02')));
    await _pumpFrames(tester);
    await tester.tap(actions);
    await _pumpFrames(tester);
    await tester.tap(find.text('Restore full course'));
    await _pumpFrames(tester);
    await tester.tapAt(const Offset(10, 10));
    await _pumpFrames(tester);

    expect(laterBand, findsOneWidget);
  });

  testWidgets('skipped course remains discoverable and restorable', (
    tester,
  ) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 5)),
      today: today,
    );
    final medication = await medications.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(startCycleDay: 1, durationDays: 4),
        active: true,
      ),
    );
    await medications.setAdjustment(
      WindowAdjustment(
        medicationId: medication.id!,
        sourcePeriodStart: DateTime(2026, 6, 1),
        kind: WindowAdjustmentKind.skipped,
      ),
    );
    await pumpApp(tester);
    final band = find.byKey(
      ValueKey('medication-band-2026-06-03-${medication.id}'),
    );
    expect(band, findsNothing);

    await tester.tap(find.byKey(const ValueKey('day-2026-06-03')));
    await _pumpFrames(tester);
    expect(find.text('skipped'), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('course-actions-${medication.id}-2026-06-01')),
    );
    await _pumpFrames(tester);
    await tester.tap(find.text('Restore full course'));
    await _pumpFrames(tester);
    await tester.tapAt(const Offset(10, 10));
    await _pumpFrames(tester);

    expect(band, findsOneWidget);
  });

  testWidgets('long-press drag records the dropped course start', (
    tester,
  ) async {
    for (final start in [DateTime(2026, 5, 1), DateTime(2026, 6, 1)]) {
      await periods.insert(
        Period(start: start, end: DateTime(start.year, start.month, 5)),
        today: today,
      );
    }
    final medication = await medications.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(startCycleDay: 1, durationDays: 4),
        active: true,
      ),
    );
    await pumpApp(tester);
    final grabbedDay = find.byKey(const ValueKey('day-2026-06-02'));
    final targetDay = find.byKey(const ValueKey('day-2026-06-04'));
    final gesture = await tester.startGesture(tester.getCenter(grabbedDay));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('course-drag-ghost')), findsOneWidget);
    await gesture.moveTo(tester.getCenter(targetDay));
    await tester.pump();
    expect(
      find.text('starts 3 Jun · 33 days since last course started'),
      findsOneWidget,
    );
    await gesture.up();
    await _pumpFrames(tester);

    expect(await medications.listAdjustments(), [
      WindowAdjustment(
        medicationId: medication.id!,
        sourcePeriodStart: DateTime(2026, 6, 1),
        kind: WindowAdjustmentKind.startedOn,
        startDate: DateTime(2026, 6, 3),
      ),
    ]);
    expect(
      find.byKey(ValueKey('medication-band-2026-06-01-${medication.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('medication-band-2026-06-06-${medication.id}')),
      findsOneWidget,
    );
  });

  testWidgets('drag-out and Escape cancel a course nudge', (tester) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 5)),
      today: today,
    );
    await medications.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(startCycleDay: 1, durationDays: 4),
        active: true,
      ),
    );
    await pumpApp(tester);
    final day = find.byKey(const ValueKey('day-2026-06-02'));
    var gesture = await tester.startGesture(tester.getCenter(day));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(const Offset(4, 4));
    await tester.pump();
    await gesture.up();
    await _pumpFrames(tester);
    expect(await medications.listAdjustments(), isEmpty);

    gesture = await tester.startGesture(tester.getCenter(day));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('course-drag-ghost')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await gesture.up();
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('course-drag-ghost')), findsNothing);
    expect(await medications.listAdjustments(), isEmpty);
  });

  testWidgets('Course started picker records, displays, and restores a shift', (
    tester,
  ) async {
    for (final start in [DateTime(2026, 5, 1), DateTime(2026, 6, 1)]) {
      await periods.insert(
        Period(start: start, end: DateTime(start.year, start.month, 5)),
        today: today,
      );
    }
    final medication = await medications.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(startCycleDay: 1, durationDays: 4),
        active: true,
      ),
    );
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('day-2026-06-02')));
    await _pumpFrames(tester);
    final actions = find.byKey(
      ValueKey('course-actions-${medication.id}-2026-06-01'),
    );
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Course started…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.tap(find.text('OK'));
    await _pumpFrames(tester);

    expect(await medications.listAdjustments(), [
      WindowAdjustment(
        medicationId: medication.id!,
        sourcePeriodStart: DateTime(2026, 6, 1),
        kind: WindowAdjustmentKind.startedOn,
        startDate: DateTime(2026, 6, 3),
      ),
    ]);
    await tester.tapAt(const Offset(10, 10));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-03')));
    await _pumpFrames(tester);

    final started = find.text('started 3 Jun 2026');
    expect(started, findsOneWidget);
    expect(
      tester.widget<Text>(started).style!.color,
      Theme.of(tester.element(started)).colorScheme.onSurface,
    );
    expect(
      find.text(
        'day 1–4 of the 1 Jun cycle · starts 1 Jun · '
        '33 days since last course started',
      ),
      findsOneWidget,
    );

    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore full course'));
    await _pumpFrames(tester);
    expect(await medications.listAdjustments(), isEmpty);
  });

  testWidgets('symptom chip cycles through clear and persists after re-pump', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-10')));
    await _pumpFrames(tester);
    final chip = find.byKey(const ValueKey('symptom-chip-2026-06-10-1'));
    await tester.ensureVisible(chip);
    expect(find.text('SYMPTOMS  0 of 10 recorded'), findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('0/3')),
      findsOneWidget,
    );

    await tester.tap(chip);
    await _pumpFrames(tester);
    expect((await symptoms.listEntries()).single.severity, 1);
    expect(
      find.descendant(of: chip, matching: find.text('1/3')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(10, 10));
    await _pumpFrames(tester);
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-10')));
    await _pumpFrames(tester);
    await tester.ensureVisible(chip);
    for (final severity in [2, 3, 0]) {
      await tester.tap(chip);
      await _pumpFrames(tester);
      expect(
        find.descendant(of: chip, matching: find.text('$severity/3')),
        findsOneWidget,
      );
    }

    expect(await symptoms.listEntries(), isEmpty);
  });

  testWidgets('day sheet shows the severity affordance', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-10')));
    await _pumpFrames(tester);

    expect(
      find.text('tap to set severity 0–3 · hold for note'),
      findsOneWidget,
    );
  });

  testWidgets('calendar switches from grid to agenda at 1.3 text scale', (
    tester,
  ) async {
    await symptoms.upsertEntry(
      SymptomEntry(date: DateTime(2026, 6, 11), typeId: 1, severity: 2),
      today: today,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: hmmmTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: CalendarScreen(
            periodRepository: periods,
            medicationRepository: medications,
            symptomRepository: symptoms,
            today: today,
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('calendar-agenda')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-grid')), findsNothing);
    expect(find.byKey(const ValueKey('calendar-weekdays')), findsNothing);
    expect(find.byKey(const ValueKey('day-2026-06-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('day-2026-06-10')), findsNothing);
  });

  testWidgets('agenda mode at 200% renders without layout exceptions', (
    tester,
  ) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 9), end: DateTime(2026, 6, 12)),
      today: today,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: hmmmTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: CalendarScreen(
            periodRepository: periods,
            medicationRepository: medications,
            symptomRepository: symptoms,
            today: today,
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('calendar-agenda')), findsOneWidget);
    final row = find.byKey(const ValueKey('day-2026-06-10'));
    expect(row, findsOneWidget);
    final rowContainer = tester.widget<Container>(
      find.descendant(of: row, matching: find.byType(Container)).first,
    );
    expect(rowContainer.constraints?.minHeight, 144);
    expect(tester.getSize(row).height, greaterThanOrEqualTo(144));
    expect(tester.takeException(), isNull);

    for (var drag = 0; drag < 3; drag++) {
      await tester.drag(
        find.byKey(const ValueKey('calendar-agenda')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle();
    final jumpToToday = find.byKey(const ValueKey('jump-to-today'));
    expect(tester.widget<IconButton>(jumpToToday).onPressed, isNotNull);

    await tester.tap(jumpToToday);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(jumpToToday).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('today disables next day and paging cannot reach tomorrow', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-15')));
    await _pumpFrames(tester);

    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('next-day')))
          .onPressed,
      isNull,
    );
    await tester.drag(
      find.byKey(const ValueKey('day-detail-pages')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('day-detail-2026-06-15')), findsOneWidget);
    expect(find.byKey(const ValueKey('day-detail-2026-06-16')), findsNothing);
  });

  testWidgets('future initial day can page back but not forward', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-16')));
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('day-detail-2026-06-16')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('previous-day')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('next-day')))
          .onPressed,
      isNull,
    );
    expect(find.text('future'), findsWidgets);
    expect(find.text('Period started'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('previous-day')));
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('day-detail-2026-06-15')), findsOneWidget);
  });

  testWidgets('severity chip grows above its minimum at 200% text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hmmmTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: DayDetailSheet(
              initialDate: today,
              today: today,
              periodRepository: periods,
              medicationRepository: medications,
              symptomRepository: symptoms,
            ),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    final chip = find.byKey(const ValueKey('symptom-chip-2026-06-15-1'));
    await tester.ensureVisible(chip);

    expect(tester.getSize(chip).height, greaterThan(Dim.minTarget));
    expect(tester.takeException(), isNull);
  });

  testWidgets('recorded symptom chips are first by severity then type id', (
    tester,
  ) async {
    await symptoms.upsertEntry(
      SymptomEntry(date: DateTime(2026, 6, 10), typeId: 2, severity: 1),
      today: today,
    );
    await symptoms.upsertEntry(
      SymptomEntry(date: DateTime(2026, 6, 10), typeId: 3, severity: 3),
      today: today,
    );
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-10')));
    await _pumpFrames(tester);

    final severityThree = find.byKey(
      const ValueKey('symptom-chip-2026-06-10-3'),
    );
    final severityOne = find.byKey(const ValueKey('symptom-chip-2026-06-10-2'));
    final unrecorded = find.byKey(const ValueKey('symptom-chip-2026-06-10-1'));
    final firstPosition = tester.getTopLeft(severityThree);
    final secondPosition = tester.getTopLeft(severityOne);
    final thirdPosition = tester.getTopLeft(unrecorded);

    expect(firstPosition.dy, secondPosition.dy);
    expect(firstPosition.dx, lessThan(secondPosition.dx));
    expect(secondPosition.dy, lessThan(thirdPosition.dy));
  });

  testWidgets('period started then period ended writes a closed period', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-10')));
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('period-start-2026-06-10')));
    await _pumpFrames(tester);
    expect(find.text('started 10 Jun 2026 · open'), findsOneWidget);
    expect(find.text('6 recorded days, no end recorded'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('period-end-2026-06-10')));
    await _pumpFrames(tester);

    final saved = (await periods.listPeriods()).single;
    expect(saved.start, DateTime(2026, 6, 10));
    expect(saved.end, DateTime(2026, 6, 10));
  });

  testWidgets('erroneous period is deletable from the day sheet', (
    tester,
  ) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 8), end: DateTime(2026, 6, 11)),
      today: today,
    );
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('day-2026-06-10')));
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('period-delete-2026-06-10')));
    await _pumpFrames(tester);
    expect(find.text('Delete period record?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-delete-period')));
    await _pumpFrames(tester);

    expect(await periods.listPeriods(), isEmpty);
  });

  testWidgets('overlapping period add shows repository validation message', (
    tester,
  ) async {
    await periods.insert(
      Period(start: today, end: today),
      today: today,
    );
    await pumpApp(tester);

    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Records'));
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

  testWidgets('medication dose entry and stop flow persist', (tester) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 5)),
      today: today,
    );
    await pumpApp(tester);

    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Records'));
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
      find.byKey(const ValueKey('medication-dose-amount')),
      '200',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('medication-dose-unit')),
        matching: find.text('mg'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await _pumpFrames(tester);

    final inserted = (await medications.listMedications()).single;
    expect(inserted.active, isTrue);
    expect(inserted.dose, '200 mg');

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpApp(tester);
    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Records'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Medications'));
    await _pumpFrames(tester);
    expect(find.textContaining('cycle day 15, 12 days'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('medication-actions-${inserted.id}')));
    await _pumpFrames(tester);
    await tester.tap(find.text('Stop'));
    await _pumpFrames(tester);
    expect(find.text('Stop Progesterone?'), findsOneWidget);
    expect(
      find.text('Historical medication windows are kept.'),
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
      find.textContaining('cycle day 15, 12 days · (stopped 15 Jun 2026)'),
      findsOneWidget,
    );
  });

  testWidgets('fixed-interval summary and form reflow at 200 percent', (
    tester,
  ) async {
    final medication = await medications.insert(
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
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester);
    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Records'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Medications'));
    await _pumpFrames(tester);

    expect(
      find.text(
        '200 mg · calendar lane L1 · 12 days every 28 days from 4 Mar 2026',
      ),
      findsOneWidget,
    );
    final laneSemantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(
            find.byKey(ValueKey('medication-lane-${medication.id}')),
          )
          .label,
      'calendar lane 1',
    );
    laneSemantics.dispose();
    await tester.tap(find.byKey(ValueKey('medication-${medication.id}')));
    await _pumpFrames(tester);

    expect(find.text('Cycle day'), findsOneWidget);
    expect(find.text('Interval'), findsOneWidget);
    expect(find.text('Continuous'), findsOneWidget);
    for (
      var drag = 0;
      drag < 4 &&
          find
              .byKey(const ValueKey('medication-derivation'))
              .evaluate()
              .isEmpty;
      drag++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pump();
    }
    expect(
      find.text('derived from the anchor date at a fixed interval'),
      findsOneWidget,
    );
    final semanticsHandle = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('medication-derivation')))
          .label,
      '12 days every 28 days from 4 Mar 2026',
    );
    for (
      var drag = 0;
      drag < 4 && find.text('DURATION (DAYS)').evaluate().isEmpty;
      drag++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pump();
    }
    expect(find.text('ANCHOR DATE'), findsOneWidget);
    expect(find.text('EVERY (DAYS)'), findsOneWidget);
    expect(find.text('DURATION (DAYS)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semanticsHandle.dispose();
  });

  testWidgets('medication without a derivable window has no calendar lane', (
    tester,
  ) async {
    final medication = await medications.insert(
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
    await pumpApp(tester);
    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Records'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Medications'));
    await _pumpFrames(tester);

    expect(find.text('200 mg · cycle day 15, 12 days'), findsOneWidget);
    expect(find.textContaining('calendar lane'), findsNothing);
    expect(
      find.byKey(ValueKey('medication-lane-${medication.id}')),
      findsNothing,
    );
  });

  testWidgets('day sheet states fixed-interval course number and basis', (
    tester,
  ) async {
    await medications.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: FixedIntervalMedicationSchedule(
          anchor: DateTime(2026, 2, 2),
          intervalDays: 28,
          durationDays: 12,
        ),
        active: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: hmmmTheme(Brightness.light),
        home: Scaffold(
          body: DayDetailSheet(
            initialDate: DateTime(2026, 3, 30),
            today: today,
            periodRepository: periods,
            medicationRepository: medications,
            symptomRepository: symptoms,
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(
      find.text(
        'course 3 · started 30 Mar 2026 by interval · '
        '28 days since last course started',
      ),
      findsOneWidget,
    );
  });

  testWidgets('medication with windows can be deleted', (tester) async {
    await periods.insert(
      Period(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 5)),
      today: today,
    );
    final medication = await medications.insert(
      Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(startCycleDay: 1, durationDays: 3),
        active: true,
      ),
    );
    await pumpApp(tester);
    expect(find.text('Progesterone'), findsOneWidget);

    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Records'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Medications'));
    await _pumpFrames(tester);
    await tester.tap(
      find.byKey(ValueKey('medication-actions-${medication.id}')),
    );
    await _pumpFrames(tester);
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await _pumpFrames(tester);
    expect(find.text('Delete Progesterone?'), findsOneWidget);
    expect(
      find.text(
        'All its derived windows are removed from the calendar and exports.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('confirm-delete-medication')));
    await _pumpFrames(tester);

    expect(await medications.listMedications(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpApp(tester);
    expect(find.text('Progesterone'), findsNothing);
  });

  testWidgets('symptom types can be added and custom types deleted', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Records'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Symptom types'));
    await _pumpFrames(tester);

    final builtinRow = find.byKey(const ValueKey('symptom-type-1'));
    expect(builtinRow, findsOneWidget);
    expect(
      find.descendant(of: builtinRow, matching: find.byType(IconButton)),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('add-symptom-type')));
    await _pumpFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey('symptom-type-name')),
      'dizziness',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-add-symptom-type')));
    await _pumpFrames(tester);

    final custom = (await symptoms.listTypes()).last;
    expect(custom.name, 'dizziness');
    await symptoms.upsertEntry(
      SymptomEntry(
        date: DateTime(2026, 6, 10),
        typeId: custom.id!,
        severity: 2,
      ),
      today: today,
    );
    await symptoms.upsertEntry(
      SymptomEntry(date: DateTime(2026, 6, 11), typeId: 1, severity: 1),
      today: today,
    );
    await _pumpFrames(tester);
    final deleteButton = find.byKey(
      ValueKey('delete-symptom-type-${custom.id}'),
    );
    await tester.scrollUntilVisible(
      deleteButton,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -100));
    await _pumpFrames(tester);
    await tester.tap(deleteButton);
    await _pumpFrames(tester);
    expect(find.text('Delete dizziness?'), findsOneWidget);
    expect(find.text('1 recorded entry is removed.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-delete-symptom-type')));
    await _pumpFrames(tester);

    expect(
      (await symptoms.listTypes()).map((type) => type.name),
      isNot(contains('dizziness')),
    );
    final entries = await symptoms.listEntries();
    expect(entries, hasLength(1));
    expect(entries.single.typeId, 1);
  });

  testWidgets('unparseable medication dose keeps the free-text path', (
    tester,
  ) async {
    final medication = await medications.insert(
      Medication(
        name: 'Oestrogen',
        dose: 'two squirts',
        schedule: ContinuousMedicationSchedule(start: DateTime(2026, 6, 1)),
        active: true,
      ),
    );
    await pumpApp(tester);
    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Records'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Medications'));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(ValueKey('medication-${medication.id}')));
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('medication-dose')), findsOneWidget);
    expect(find.byKey(const ValueKey('medication-dose-amount')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('medication-dose')))
          .controller!
          .text,
      'two squirts',
    );
    await tester.tap(find.byKey(const ValueKey('save-medication')));
    await _pumpFrames(tester);

    expect((await medications.listMedications()).single.dose, 'two squirts');
  });

  testWidgets('settings routes records and exports through subscreens', (
    tester,
  ) async {
    await periods.insert(Period(start: DateTime(2026, 6, 2)), today: today);
    await medications.insert(
      Medication(
        name: 'Oestrogen',
        dose: '2 pumps',
        schedule: ContinuousMedicationSchedule(start: DateTime(2026, 3, 4)),
        active: true,
      ),
    );
    await medications.insert(
      Medication(
        name: 'Previous medication',
        dose: '1 patch',
        schedule: ContinuousMedicationSchedule(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 2, 28),
        ),
        active: false,
      ),
    );
    await symptoms.insertType(
      const SymptomType(name: 'dizziness', builtin: false),
    );
    await pumpApp(tester);

    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('settings-records')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-export-print')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-theme')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-require-unlock')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('settings-list')),
        matching: find.byType(ListTile),
      ),
      findsNWidgets(4),
    );
    expect(find.text('Medications'), findsNothing);
    expect(find.text('Period records'), findsNothing);
    expect(find.text('Symptom types'), findsNothing);
    expect(find.text('Print report'), findsNothing);
    expect(find.text('Export calendar'), findsNothing);
    expect(find.text('Export data'), findsNothing);
    expect(find.text('Import data'), findsNothing);
    expect(
      find.text('2 medications · 1 period · 11 symptom types'),
      findsOneWidget,
    );
    expect(find.text('ics · json · pdf'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('system'), findsOneWidget);

    final semanticsHandle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('settings-records'))).label,
      'Records, 2 medications · 1 period · 11 symptom types',
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('settings-export-print')))
          .label,
      'Export & print, ics · json · pdf',
    );

    await tester.tap(find.byKey(const ValueKey('settings-records')));
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('records-screen')), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Records')).flagsCollection.namesRoute,
      isTrue,
    );
    expect(find.text('2 · 1 active'), findsOneWidget);
    expect(find.text('1 · newest 2 Jun 2026, open'), findsOneWidget);
    expect(find.text('11 · 1 custom'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('settings-export-print')));
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('export-print-screen')), findsOneWidget);
    expect(find.text('Export & print'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.text('Export & print'))
          .flagsCollection
          .namesRoute,
      isTrue,
    );
    expect(find.text('PDF · choose 1/3/6/12 months'), findsOneWidget);
    expect(find.text('JSON · replaces everything'), findsOneWidget);
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title as Text).data),
      ['Print report', 'Export calendar', 'Export data', 'Import data'],
    );
    semanticsHandle.dispose();
  });

  testWidgets('settings import keeps its two-step confirmation', (
    tester,
  ) async {
    final source = await JsonBackupRepository(database)
        .export(exportedAt: today);
    await pumpApp(tester);
    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Export & print'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Import data'));
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('import-json-text')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('import-json-text')),
      source,
    );
    await tester.tap(find.text('Continue'));
    await _pumpFrames(tester);

    expect(find.text('Replace all data?'), findsOneWidget);
    expect(find.byKey(const ValueKey('confirm-import-json')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _pumpFrames(tester);
    expect(find.text('Export & print'), findsOneWidget);
  });

  testWidgets('export range descriptions include a future derived course', (
    tester,
  ) async {
    await periods.insert(Period(start: DateTime(2026, 6, 2)), today: today);
    await medications.insert(
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
    await pumpApp(tester);

    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Export & print'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Export calendar'));
    await _pumpFrames(tester);

    expect(find.text('1 Jun 2026 – 27 Jun 2026'), findsOneWidget);
    expect(find.text('1 Apr 2026 – 27 Jun 2026'), findsOneWidget);
    expect(find.text('1 Jan 2026 – 27 Jun 2026'), findsOneWidget);
    expect(find.text('1 Jul 2025 – 27 Jun 2026'), findsOneWidget);
  });

  testWidgets('dark theme selection persists across an app restart', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester);
    await tester.tap(find.text('SETTINGS'));
    await _pumpFrames(tester);
    await tester.scrollUntilVisible(
      find.text('Theme'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Theme'));
    await _pumpFrames(tester);

    expect(find.text('System'), findsOneWidget);
    expect(find.text('follow the device setting'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('always light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('always dark'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await _pumpFrames(tester);

    expect(
      Theme.of(tester.element(find.text('dark'))).brightness,
      Brightness.dark,
    );
    expect(
      await database.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['theme_mode'],
      ),
      [
        {'value': 'dark'},
      ],
    );

    final restartedSettings = SettingsRepository(database);
    addTearDown(restartedSettings.dispose);
    await restartedSettings.load();
    await pumpApp(tester, withSettings: restartedSettings);

    expect(restartedSettings.themeMode, AppThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(NavigationBar))).brightness,
      Brightness.dark,
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
      await pumpApp(tester);

      await tester.tap(find.text('TRENDS'));
      await _pumpFrames(tester);
      final semanticsHandle = tester.ensureSemantics();

      expect(find.text('3 recorded · 2 complete intervals'), findsOneWidget);
      expect(find.text('29.5'), findsWidgets);
      expect(
        find.text('5 entries over 3 months · 2 of 10 types'),
        findsOneWidget,
      );
      expect(find.text('open'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('cycle-day-matrix')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _pumpFrames(tester);
      final zero = find.byKey(const ValueKey('cycle-day-count-1-4'));
      expect(
        find.descendant(of: zero, matching: find.text('·')),
        findsOneWidget,
      );
      final noCycle = find.byKey(const ValueKey('cycle-day-no-cycle-1'));
      expect(
        find.descendant(of: noCycle, matching: find.text('1')),
        findsOneWidget,
      );
      semanticsHandle.dispose();
      await tester.tap(find.byKey(const ValueKey('trend-symptom-1')));
      await _pumpFrames(tester);

      expect(find.text('31 Mar 2026 · 1/3 · no cycle'), findsOneWidget);
      expect(find.text('Before first period'), findsOneWidget);
      expect(find.text('1 May 2026 · 1/3 · cycle day 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await _pumpFrames(tester);
      await tester.scrollUntilVisible(
        find.text('Monthly counts'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _pumpFrames(tester);

      expect(find.text('5 entries over 12 months to Jun 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('monthly-count-1-11')), findsOneWidget);
    },
  );
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

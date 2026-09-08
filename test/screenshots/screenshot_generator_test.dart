// Renders every screen with seeded fixture data and writes PNGs to
// design/screenshots/. Not part of the normal suite: run with
//   flutter test test/screenshots --dart-define=screenshots=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/data/database.dart';
import 'package:hmmm/data/medication_repository.dart';
import 'package:hmmm/data/period_repository.dart';
import 'package:hmmm/data/settings_repository.dart';
import 'package:hmmm/data/symptom_repository.dart';
import 'package:hmmm/domain/models.dart';
import 'package:hmmm/main.dart';
import 'package:hmmm/app_authenticator.dart';
import 'package:hmmm/export/json.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _enabled = bool.fromEnvironment('screenshots');
const _scalePercent = int.fromEnvironment('scale', defaultValue: 100);

void main() {
  if (!_enabled) {
    test('screenshot generator disabled', () {});
    return;
  }

  late Database database;
  late PeriodRepository periods;
  late MedicationRepository medications;
  late SymptomRepository symptoms;
  late SettingsRepository settings;
  final today = DateTime(2026, 6, 15);
  final outDir = Directory('design/screenshots');

  setUpAll(() async {
    sqfliteFfiInit();
    WidgetsApp.debugAllowBannerOverride = false;
    final iconLoader = FontLoader('MaterialIcons');
    final iconBytes = File(
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf',
    ).readAsBytesSync();
    iconLoader.addFont(Future.value(ByteData.view(iconBytes.buffer)));
    await iconLoader.load();
    for (final (family, files) in [
      (
        'Public Sans',
        [
          'PublicSans-Regular.ttf',
          'PublicSans-Medium.ttf',
          'PublicSans-SemiBold.ttf',
        ],
      ),
      ('DM Mono', ['DMMono-Regular.ttf', 'DMMono-Medium.ttf']),
    ]) {
      final loader = FontLoader(family);
      for (final file in files) {
        final bytes = File('assets/fonts/$file').readAsBytesSync();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await loader.load();
    }
    outDir.createSync(recursive: true);
  });

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

    for (final period in [
      Period(start: DateTime(2026, 3, 20), end: DateTime(2026, 3, 24)),
      Period(start: DateTime(2026, 4, 16), end: DateTime(2026, 4, 20)),
      Period(start: DateTime(2026, 5, 15), end: DateTime(2026, 5, 19)),
      Period(start: DateTime(2026, 6, 9), end: DateTime(2026, 6, 13)),
    ]) {
      await periods.insert(period, today: today);
    }
    await medications.insert(
      Medication(
        name: 'Oestrogel',
        dose: '2 pumps',
        schedule: ContinuousMedicationSchedule(start: DateTime(2026, 3, 1)),
        active: true,
      ),
    );
    final utrogestan = await medications.insert(
      Medication(
        name: 'Utrogestan',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(
          startCycleDay: 15,
          durationDays: 12,
        ),
        active: true,
      ),
    );
    await medications.insert(
      Medication(
        name: 'Testosterone',
        dose: '20 mg',
        schedule: FixedIntervalMedicationSchedule(
          anchor: DateTime(2026, 3, 4),
          intervalDays: 28,
          durationDays: 12,
        ),
        active: true,
      ),
    );
    await medications.setAdjustment(
      WindowAdjustment(
        medicationId: utrogestan.id!,
        sourcePeriodStart: DateTime(2026, 4, 16),
        kind: WindowAdjustmentKind.endedEarly,
        endDate: DateTime(2026, 5, 6),
      ),
    );
    await symptoms.insertType(
      const SymptomType(name: 'palpitations', builtin: false),
    );
    for (final (date, typeId, severity, note) in [
      (DateTime(2026, 6, 10), 1, 3, 'woke at 4am'),
      (DateTime(2026, 6, 10), 6, 2, null),
      (DateTime(2026, 6, 11), 1, 2, null),
      (DateTime(2026, 6, 11), 4, 1, null),
      (DateTime(2026, 6, 11), 9, 2, null),
      (DateTime(2026, 6, 11), 2, 1, null),
      (DateTime(2026, 6, 12), 5, 1, null),
      (DateTime(2026, 5, 16), 1, 2, null),
      (DateTime(2026, 5, 17), 10, 1, null),
      (DateTime(2026, 4, 18), 1, 1, null),
      (DateTime(2026, 3, 12), 3, 2, null),
    ]) {
      await symptoms.upsertEntry(
        SymptomEntry(
          date: date,
          typeId: typeId,
          severity: severity,
          note: note,
        ),
        today: today,
      );
    }
  });

  tearDown(() async {
    periods.dispose();
    medications.dispose();
    symptoms.dispose();
    await database.close();
  });

  const shotKey = ValueKey('shot-boundary');

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final boundary =
        tester.renderObject(find.byKey(shotKey)) as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data;
    });
    File('${outDir.path}/$name-s$_scalePercent.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    if (const bool.fromEnvironment('dumpErrors')) return;
    for (
      var e = tester.takeException();
      e != null;
      e = tester.takeException()
    ) {
      // ignore: avoid_print
      print(
        'LAYOUT-FINDING [$name]: ${e is FlutterError ? e.diagnostics.map((d) => d.toString()).join(' | ') : e.toString().replaceAll('\n', ' | ')}',
      );
    }
  }

  Future<void> pumpApp(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2.0;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    if (_scalePercent != 100) {
      tester.platformDispatcher.textScaleFactorTestValue = _scalePercent / 100;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: HmmmApp(
          periodRepository: periods,
          medicationRepository: medications,
          symptomRepository: symptoms,
          settingsRepository: settings,
          backupRepository: JsonBackupRepository(database),
          authenticator: const _OpenAuthenticator(),
          today: today,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final mode = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('calendar $mode', (tester) async {
      await pumpApp(tester, brightness);
      await capture(tester, '01-calendar-$mode');
    });

    testWidgets('day sheet $mode', (tester) async {
      await pumpApp(tester, brightness);
      final day = find.byKey(const ValueKey('day-2026-06-11'));
      if (_scalePercent >= 130) {
        for (
          var drag = 0;
          drag < 10 && day.hitTestable().evaluate().isEmpty;
          drag++
        ) {
          await tester.drag(
            find.byKey(const ValueKey('calendar-agenda')),
            const Offset(0, -300),
          );
          await tester.pumpAndSettle();
        }
      }
      expect(day.hitTestable(), findsOneWidget);
      await tester.tap(day);
      await capture(tester, '02-day-sheet-$mode');
    });

    testWidgets('trends $mode', (tester) async {
      await pumpApp(tester, brightness);
      await tester.tap(find.text('TRENDS'));
      await capture(tester, '03-trends-$mode');
    });

    testWidgets('settings $mode', (tester) async {
      await pumpApp(tester, brightness);
      await tester.tap(find.text('SETTINGS'));
      await capture(tester, '04-settings-$mode');
    });

    testWidgets('settings records $mode', (tester) async {
      await pumpApp(tester, brightness);
      await tester.tap(find.text('SETTINGS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Records'));
      await capture(tester, '04-records-$mode');
    });

    testWidgets('settings export and print $mode', (tester) async {
      await pumpApp(tester, brightness);
      await tester.tap(find.text('SETTINGS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export & print'));
      await capture(tester, '04-export-print-$mode');
    });

    testWidgets('medications $mode', (tester) async {
      await pumpApp(tester, brightness);
      await tester.tap(find.text('SETTINGS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medications'));
      await capture(tester, '05-medications-$mode');
    });

    testWidgets('interval medication form $mode', (tester) async {
      await pumpApp(tester, brightness);
      await tester.tap(find.text('SETTINGS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medications'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-medication')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Interval'));
      await capture(tester, '06-interval-medication-form-$mode');
    });

    testWidgets('period records $mode', (tester) async {
      await pumpApp(tester, brightness);
      await tester.tap(find.text('SETTINGS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Period records'));
      await capture(tester, '07-period-records-$mode');
    });

    testWidgets('symptom types $mode', (tester) async {
      await pumpApp(tester, brightness);
      await tester.tap(find.text('SETTINGS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Symptom types'));
      await capture(tester, '08-symptom-types-$mode');
    });
  }
}

class _OpenAuthenticator implements AppAuthenticator {
  const _OpenAuthenticator();

  @override
  Future<bool> authenticate() async => true;
}

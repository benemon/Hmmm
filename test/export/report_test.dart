import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:hmmm/domain/cycle_lengths.dart';
import 'package:hmmm/domain/hrt_window.dart';
import 'package:hmmm/domain/models.dart';
import 'package:hmmm/domain/trends.dart';
import 'package:hmmm/export/report.dart';
import 'package:hmmm/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'report assembles a PDF and retains domain-calculated numbers',
    () async {
      final periods = [
        Period(start: DateTime(2026, 4, 1), end: DateTime(2026, 4, 5)),
        Period(start: DateTime(2026, 4, 29), end: DateTime(2026, 5, 3)),
        Period(start: DateTime(2026, 5, 30)),
      ];
      final medications = [
        Medication(
          id: 1,
          name: 'Progesterone',
          dose: '200 mg',
          schedule: CyclicalMedicationSchedule(
            startCycleDay: 15,
            durationDays: 12,
          ),
          active: true,
        ),
      ];
      const types = [SymptomType(id: 1, name: 'migraine', builtin: true)];
      final entries = [
        SymptomEntry(date: DateTime(2026, 4, 2), typeId: 1, severity: 2),
        SymptomEntry(date: DateTime(2026, 5, 1), typeId: 1, severity: 1),
      ];
      final today = DateTime(2026, 6, 15);
      final range = DateRange(
        start: DateTime(2026, 4, 1),
        end: DateTime(2026, 6, 15),
      );
      final windowsByMedicationId = {
        1: deriveWindows(medications.single, periods, range, today: today),
      };
      final data = assembleReportData(
        periods: periods,
        medications: medications,
        symptomTypes: types,
        symptomEntries: entries,
        windowsByMedicationId: windowsByMedicationId,
        range: range,
        today: today,
      );

      expect(data.windowsByMedicationId, windowsByMedicationId);
      expect(data.cycleLengths, cycleLengthsToNext(periods));
      expect(
        _cycleDayValues(data.symptomCycleDayCounts),
        _cycleDayValues(symptomCountsByCycleDay(entries, periods)),
      );
      expect(
        data.monthlySymptomCounts.countsByTypeId,
        symptomCountsByMonth(entries, today).countsByTypeId,
      );
      final summaries = cycleLengthSummaries(periods, today);
      expect(
        data.cycleSummaries.map(
          (item) => (item.months, item.sampleCount, item.mean),
        ),
        summaries.map((item) => (item.months, item.sampleCount, item.mean)),
      );

      final bytes = await buildReportPdf(data);
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    },
  );

  test('report uses the shared marker texture metrics', () {
    expect(reportTextureMetrics(MarkerTexture.dotted, 24), (
      MarkerTextureMetrics.dottedMark,
      MarkerTextureMetrics.dottedGap,
    ));
    expect(reportTextureMetrics(MarkerTexture.dashed, 24), (
      MarkerTextureMetrics.dashedMark,
      MarkerTextureMetrics.dashedGap,
    ));
    expect(reportTextureMetrics(MarkerTexture.dashed, 24), (8.0, 4.0));
  });

  test(
    'letterhead substitutions remove placeholders and retain facts',
    () async {
      final data = assembleReportData(
        periods: const [],
        medications: [
          Medication(
            id: 1,
            name: 'Progesterone',
            dose: '200 mg',
            schedule: FixedIntervalMedicationSchedule(
              anchor: DateTime(2026, 3, 4),
              intervalDays: 28,
              durationDays: 12,
            ),
            active: true,
          ),
        ],
        symptomTypes: const [],
        symptomEntries: const [],
        windowsByMedicationId: const {1: []},
        range: DateRange(
          start: DateTime(2026, 4, 1),
          end: DateTime(2026, 6, 15),
        ),
        today: DateTime(2026, 6, 15),
      );
      final letterhead = reportLetterheadSvg(
        data: data,
        template: await rootBundle.loadString('assets/brand/letterhead.svg'),
      );

      expect(letterhead, contains('15 Jun 26'));
      expect(letterhead, contains('1 Apr 26-15 Jun 26'));
      expect(letterhead, contains('L1 Progesterone 200 mg'));
      expect(letterhead, isNot(contains('{{EXPORT_DATE}}')));
      expect(letterhead, isNot(contains('{{RANGE}}')));
      expect(letterhead, isNot(contains('{{MED_1}}')));
      expect(letterhead, isNot(contains('{{MED_2}}')));
      expect(await buildReportPdf(data), isNotEmpty);
    },
  );

  test('report accepts a shifted course adjustment', () async {
    final medication = Medication(
      id: 1,
      name: 'Progesterone',
      dose: '200 mg',
      schedule: CyclicalMedicationSchedule(startCycleDay: 1, durationDays: 4),
      active: true,
    );
    final adjustment = WindowAdjustment(
      medicationId: 1,
      sourcePeriodStart: DateTime(2026, 6, 1),
      kind: WindowAdjustmentKind.startedOn,
      startDate: DateTime(2026, 6, 3),
    );
    final range = DateRange(
      start: DateTime(2026, 6, 1),
      end: DateTime(2026, 6, 15),
    );
    final windows = deriveAdjustedWindows(
      medication,
      [Period(start: DateTime(2026, 6, 1))],
      range,
      [adjustment],
      today: DateTime(2026, 6, 15),
    );
    final data = assembleReportData(
      periods: [Period(start: DateTime(2026, 6, 1))],
      medications: [medication],
      symptomTypes: const [],
      symptomEntries: const [],
      windowsByMedicationId: {1: windows},
      windowAdjustments: [adjustment],
      range: range,
      today: DateTime(2026, 6, 15),
    );

    expect(windows.single.start, DateTime(2026, 6, 3));
    expect(await buildReportPdf(data), isNotEmpty);
  });
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

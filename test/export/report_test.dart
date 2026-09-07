import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/domain/cycle_lengths.dart';
import 'package:hmmm/domain/hrt_window.dart';
import 'package:hmmm/domain/models.dart';
import 'package:hmmm/domain/trends.dart';
import 'package:hmmm/export/report.dart';

void main() {
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
      final data = assembleReportData(
        periods: periods,
        medications: medications,
        symptomTypes: types,
        symptomEntries: entries,
        range: DateRange(
          start: DateTime(2026, 4, 1),
          end: DateTime(2026, 6, 15),
        ),
        today: today,
      );

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

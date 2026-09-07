import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/domain/calendar.dart';
import 'package:hmmm/domain/hrt_window.dart';
import 'package:hmmm/domain/models.dart';

void main() {
  final today = DateTime(2026, 6, 15);

  test('day inside a period carries continuous band boundaries', () {
    final marker = buildDayCellMarkerData(
      date: DateTime(2026, 6, 11),
      today: today,
      periods: [
        Period(start: DateTime(2026, 6, 10), end: DateTime(2026, 6, 13)),
      ],
      windowsByMedicationId: const {},
      laneByMedicationId: const {},
      entries: const [],
    );

    expect(marker.inPeriod, isTrue);
    expect(marker.startsPeriod, isFalse);
    expect(marker.endsPeriod, isFalse);
  });

  test('overlapping medication windows use ascending id lane order', () {
    final lanes = laneAssignments([
      for (final id in [9, 2])
        Medication(
          id: id,
          name: 'Medication $id',
          dose: '1',
          schedule: CyclicalMedicationSchedule(
            startCycleDay: 1,
            durationDays: 1,
          ),
          active: true,
        ),
    ]);
    final marker = buildDayCellMarkerData(
      date: DateTime(2026, 6, 11),
      today: today,
      periods: const [],
      windowsByMedicationId: {
        9: [
          MedicationWindow(
            start: DateTime(2026, 6, 10),
            end: DateTime(2026, 6, 12),
          ),
        ],
        2: [
          MedicationWindow(
            start: DateTime(2026, 6, 11),
            end: DateTime(2026, 6, 14),
          ),
        ],
      },
      laneByMedicationId: lanes,
      entries: const [],
    );

    expect(lanes, {2: 0, 9: 1});
    expect(
      marker.medicationMarkers.map(
        (marker) => (marker.medicationId, marker.laneIndex),
      ),
      [(2, 0), (9, 1)],
    );
  });

  test('five symptoms show four glyphs and a one-item overflow', () {
    final marker = buildDayCellMarkerData(
      date: DateTime(2026, 6, 11),
      today: today,
      periods: const [],
      windowsByMedicationId: const {},
      laneByMedicationId: const {},
      entries: [
        for (var typeId = 1; typeId <= 5; typeId++)
          SymptomEntry(
            date: DateTime(2026, 6, 11),
            typeId: typeId,
            severity: 1,
          ),
      ],
    );

    expect(marker.visibleSymptomTypeIds, [1, 2, 3, 4]);
    expect(marker.symptomOverflowCount, 1);
  });

  test('cycle day is one-based from the most recent period start', () {
    final periods = [
      Period(start: DateTime(2026, 5, 1), end: DateTime(2026, 5, 5)),
      Period(start: DateTime(2026, 5, 29), end: DateTime(2026, 6, 2)),
    ];

    expect(cycleDayForDate(DateTime(2026, 5, 29), periods), 1);
    expect(cycleDayForDate(DateTime(2026, 6, 2), periods), 5);
    expect(cycleDayForDate(DateTime(2026, 4, 30), periods), isNull);
  });

  test('symptom severity cycles from three back to none', () {
    expect(
      [for (var value = 0; value <= 3; value++) nextSymptomSeverity(value)],
      [1, 2, 3, 0],
    );
  });
}

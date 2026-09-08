import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/domain/dates.dart';
import 'package:hmmm/domain/hrt_window.dart';
import 'package:hmmm/domain/models.dart';

void main() {
  group('cyclical medication windows', () {
    test('regular 28-day history matches the hand-computed oracle', () {
      final periods = [
        Period(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 5)),
        Period(start: DateTime(2026, 1, 29), end: DateTime(2026, 2, 2)),
        Period(start: DateTime(2026, 2, 26), end: DateTime(2026, 3, 2)),
        Period(start: DateTime(2026, 3, 26), end: DateTime(2026, 3, 30)),
      ];

      final windows = deriveWindows(
        _cyclicalMedication(startCycleDay: 15, durationDays: 12),
        periods,
        DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 4, 30)),
        today: DateTime(2026, 6, 15),
      );

      expect(_windowDates(windows), [
        [
          '2026-01-15',
          '2026-01-16',
          '2026-01-17',
          '2026-01-18',
          '2026-01-19',
          '2026-01-20',
          '2026-01-21',
          '2026-01-22',
          '2026-01-23',
          '2026-01-24',
          '2026-01-25',
          '2026-01-26',
        ],
        [
          '2026-02-12',
          '2026-02-13',
          '2026-02-14',
          '2026-02-15',
          '2026-02-16',
          '2026-02-17',
          '2026-02-18',
          '2026-02-19',
          '2026-02-20',
          '2026-02-21',
          '2026-02-22',
          '2026-02-23',
        ],
        [
          '2026-03-12',
          '2026-03-13',
          '2026-03-14',
          '2026-03-15',
          '2026-03-16',
          '2026-03-17',
          '2026-03-18',
          '2026-03-19',
          '2026-03-20',
          '2026-03-21',
          '2026-03-22',
          '2026-03-23',
        ],
        [
          '2026-04-09',
          '2026-04-10',
          '2026-04-11',
          '2026-04-12',
          '2026-04-13',
          '2026-04-14',
          '2026-04-15',
          '2026-04-16',
          '2026-04-17',
          '2026-04-18',
          '2026-04-19',
          '2026-04-20',
        ],
      ]);
      expect(windows.map((window) => dateToIso(window.sourcePeriodStart!)), [
        '2026-01-01',
        '2026-01-29',
        '2026-02-26',
        '2026-03-26',
      ]);
    });

    test('21-day cycle leaves overlapping windows unmerged', () {
      final periods = [
        Period(start: DateTime(2026, 1, 1)),
        Period(start: DateTime(2026, 2, 15)),
        Period(start: DateTime(2026, 3, 8)),
        Period(start: DateTime(2026, 4, 22)),
      ];

      final windows = deriveWindows(
        _cyclicalMedication(startCycleDay: 15, durationDays: 28),
        periods,
        DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 6, 30)),
        today: DateTime(2026, 6, 15),
      );

      expect(windows, [
        MedicationWindow(
          start: DateTime(2026, 1, 15),
          end: DateTime(2026, 2, 11),
          sourcePeriodStart: DateTime(2026, 1, 1),
        ),
        MedicationWindow(
          start: DateTime(2026, 3, 1),
          end: DateTime(2026, 3, 28),
          sourcePeriodStart: DateTime(2026, 2, 15),
        ),
        MedicationWindow(
          start: DateTime(2026, 3, 22),
          end: DateTime(2026, 4, 18),
          sourcePeriodStart: DateTime(2026, 3, 8),
        ),
        MedicationWindow(
          start: DateTime(2026, 5, 6),
          end: DateTime(2026, 6, 2),
          sourcePeriodStart: DateTime(2026, 4, 22),
        ),
      ]);
      expect(windows[1].end.isAfter(windows[2].start), isTrue);
    });

    test('ongoing period still produces a window', () {
      final windows = deriveWindows(
        _cyclicalMedication(startCycleDay: 15, durationDays: 12),
        [Period(start: DateTime(2026, 5, 10))],
        DateRange(start: DateTime(2026, 5, 1), end: DateTime(2026, 6, 30)),
        today: DateTime(2026, 6, 15),
      );

      expect(_windowDates(windows), [
        [
          '2026-05-24',
          '2026-05-25',
          '2026-05-26',
          '2026-05-27',
          '2026-05-28',
          '2026-05-29',
          '2026-05-30',
          '2026-05-31',
          '2026-06-01',
          '2026-06-02',
          '2026-06-03',
          '2026-06-04',
        ],
      ]);
      expect(windows.single.sourcePeriodStart, DateTime(2026, 5, 10));
    });

    test('single-period history produces one window', () {
      final windows = deriveWindows(
        _cyclicalMedication(startCycleDay: 3, durationDays: 4),
        [Period(start: DateTime(2026, 7, 2), end: DateTime(2026, 7, 6))],
        DateRange(start: DateTime(2026, 7, 1), end: DateTime(2026, 7, 31)),
        today: DateTime(2026, 6, 15),
      );

      expect(_windowDates(windows), [
        ['2026-07-04', '2026-07-05', '2026-07-06', '2026-07-07'],
      ]);
    });

    test('empty history produces no windows', () {
      final windows = deriveWindows(
        _cyclicalMedication(startCycleDay: 15, durationDays: 12),
        const [],
        DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 12, 31)),
        today: DateTime(2026, 6, 15),
      );

      expect(windows, isEmpty);
    });

    test('range clips windows at both edges and keeps their sources', () {
      final windows = deriveWindows(
        _cyclicalMedication(startCycleDay: 1, durationDays: 20),
        [
          Period(start: DateTime(2026, 1, 1)),
          Period(start: DateTime(2026, 2, 1)),
        ],
        DateRange(start: DateTime(2026, 1, 10), end: DateTime(2026, 2, 10)),
        today: DateTime(2026, 6, 15),
      );

      expect(_windowDates(windows), [
        [
          '2026-01-10',
          '2026-01-11',
          '2026-01-12',
          '2026-01-13',
          '2026-01-14',
          '2026-01-15',
          '2026-01-16',
          '2026-01-17',
          '2026-01-18',
          '2026-01-19',
          '2026-01-20',
        ],
        [
          '2026-02-01',
          '2026-02-02',
          '2026-02-03',
          '2026-02-04',
          '2026-02-05',
          '2026-02-06',
          '2026-02-07',
          '2026-02-08',
          '2026-02-09',
          '2026-02-10',
        ],
      ]);
      expect(windows.map((window) => dateToIso(window.sourcePeriodStart!)), [
        '2026-01-01',
        '2026-02-01',
      ]);
    });

    test('effective range includes period starts on both boundaries', () {
      final windows = deriveWindows(
        Medication(
          name: 'Progesterone',
          dose: '200 mg',
          schedule: CyclicalMedicationSchedule(
            startCycleDay: 1,
            durationDays: 2,
            effectiveStart: DateTime(2026, 2, 1),
            effectiveEnd: DateTime(2026, 3, 1),
          ),
          active: true,
        ),
        [
          Period(start: DateTime(2026, 1, 31)),
          Period(start: DateTime(2026, 2, 1)),
          Period(start: DateTime(2026, 3, 1)),
          Period(start: DateTime(2026, 3, 2)),
        ],
        DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 4, 1)),
        today: DateTime(2026, 6, 15),
      );

      expect(windows.map((window) => window.sourcePeriodStart), [
        DateTime(2026, 2, 1),
        DateTime(2026, 3, 1),
      ]);
    });

    test('effective range supports either unbounded side', () {
      final periods = [
        Period(start: DateTime(2026, 1, 1)),
        Period(start: DateTime(2026, 2, 1)),
        Period(start: DateTime(2026, 3, 1)),
      ];
      final range = DateRange(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 3, 31),
      );
      expect(
        deriveWindows(
          _cyclicalMedication(
            startCycleDay: 1,
            durationDays: 1,
            effectiveStart: DateTime(2026, 2, 1),
          ),
          periods,
          range,
          today: DateTime(2026, 6, 15),
        ).map((window) => window.sourcePeriodStart),
        [DateTime(2026, 2, 1), DateTime(2026, 3, 1)],
      );
      expect(
        deriveWindows(
          _cyclicalMedication(
            startCycleDay: 1,
            durationDays: 1,
            effectiveEnd: DateTime(2026, 2, 1),
          ),
          periods,
          range,
          today: DateTime(2026, 6, 15),
        ).map((window) => window.sourcePeriodStart),
        [DateTime(2026, 1, 1), DateTime(2026, 2, 1)],
      );
    });

    test('stopped medication keeps prior windows and derives no later one', () {
      final medication = Medication(
        name: 'Progesterone',
        dose: '200 mg',
        schedule: CyclicalMedicationSchedule(
          startCycleDay: 15,
          durationDays: 12,
          effectiveEnd: DateTime(2026, 2, 1),
        ),
        active: false,
      );

      final windows = deriveWindows(
        medication,
        [
          Period(start: DateTime(2026, 2, 1)),
          Period(start: DateTime(2026, 3, 1)),
        ],
        DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 4, 30)),
        today: DateTime(2026, 6, 15),
      );

      expect(windows, hasLength(1));
      expect(windows.single.sourcePeriodStart, DateTime(2026, 2, 1));
      expect(windows.single.end, DateTime(2026, 2, 26));
    });
  });

  group('continuous medication windows', () {
    test('open end is clamped to the query range', () {
      final medication = Medication(
        name: 'Oestrogen',
        dose: '50 micrograms',
        schedule: ContinuousMedicationSchedule(start: DateTime(2026, 2, 3)),
        active: true,
      );

      final windows = deriveWindows(
        medication,
        const [],
        DateRange(start: DateTime(2026, 2, 1), end: DateTime(2026, 2, 8)),
        today: DateTime(2026, 6, 15),
      );

      expect(_windowDates(windows), [
        [
          '2026-02-03',
          '2026-02-04',
          '2026-02-05',
          '2026-02-06',
          '2026-02-07',
          '2026-02-08',
        ],
      ]);
      expect(windows.single.sourcePeriodStart, isNull);
    });
  });

  group('fixed-interval medication windows', () {
    test('anchor plus 28 days produces hand-computed 12-day courses', () {
      final windows = deriveWindows(
        _fixedIntervalMedication(),
        const [],
        DateRange(start: DateTime(2026, 3, 1), end: DateTime(2026, 9, 30)),
        today: DateTime(2026, 4, 2),
      );

      expect(_windowDates(windows), [
        [
          '2026-03-04',
          '2026-03-05',
          '2026-03-06',
          '2026-03-07',
          '2026-03-08',
          '2026-03-09',
          '2026-03-10',
          '2026-03-11',
          '2026-03-12',
          '2026-03-13',
          '2026-03-14',
          '2026-03-15',
        ],
        [
          '2026-04-01',
          '2026-04-02',
          '2026-04-03',
          '2026-04-04',
          '2026-04-05',
          '2026-04-06',
          '2026-04-07',
          '2026-04-08',
          '2026-04-09',
          '2026-04-10',
          '2026-04-11',
          '2026-04-12',
        ],
        [
          '2026-04-29',
          '2026-04-30',
          '2026-05-01',
          '2026-05-02',
          '2026-05-03',
          '2026-05-04',
          '2026-05-05',
          '2026-05-06',
          '2026-05-07',
          '2026-05-08',
          '2026-05-09',
          '2026-05-10',
        ],
      ]);
      expect(windows.map((window) => window.sourcePeriodStart), [
        DateTime(2026, 3, 4),
        DateTime(2026, 4, 1),
        DateTime(2026, 4, 29),
      ]);
    });

    test('horizon includes the immediate next course and drops k plus 2', () {
      final windows = deriveWindows(
        _fixedIntervalMedication(),
        const [],
        DateRange(start: DateTime(2026, 3, 1), end: DateTime(2027, 12, 31)),
        today: DateTime(2026, 4, 2),
      );

      expect(windows, hasLength(3));
      expect(windows.last.sourcePeriodStart, DateTime(2026, 4, 29));
      expect(
        windows.map((window) => window.sourcePeriodStart),
        isNot(contains(DateTime(2026, 5, 27))),
      );
    });

    test('effective end keeps history and stops later course starts', () {
      final windows = deriveWindows(
        _fixedIntervalMedication(effectiveEnd: DateTime(2026, 4, 1)),
        const [],
        DateRange(start: DateTime(2026, 3, 1), end: DateTime(2026, 6, 30)),
        today: DateTime(2026, 5, 1),
      );

      expect(windows.map((window) => window.sourcePeriodStart), [
        DateTime(2026, 3, 4),
        DateTime(2026, 4, 1),
      ]);
    });

    test('shift and skip adjustments use anchor-derived source dates', () {
      final medication = _fixedIntervalMedication(id: 7);
      final windows = deriveAdjustedWindows(
        medication,
        const [],
        DateRange(start: DateTime(2026, 3, 1), end: DateTime(2026, 4, 28)),
        [
          WindowAdjustment(
            medicationId: 7,
            sourcePeriodStart: DateTime(2026, 3, 4),
            kind: WindowAdjustmentKind.skipped,
          ),
          WindowAdjustment(
            medicationId: 7,
            sourcePeriodStart: DateTime(2026, 4, 1),
            kind: WindowAdjustmentKind.startedOn,
            startDate: DateTime(2026, 4, 3),
          ),
        ],
        today: DateTime(2026, 4, 2),
      );

      expect(windows, hasLength(1));
      expect(windows.single.sourcePeriodStart, DateTime(2026, 4, 1));
      expect(windows.single.start, DateTime(2026, 4, 3));
      expect(windows.single.end, DateTime(2026, 4, 14));
    });
  });

  group('window adjustments', () {
    final source = DateTime(2026, 6, 1);
    late MedicationWindow window;

    setUp(() {
      window = MedicationWindow(
        start: DateTime(2026, 6, 15),
        end: DateTime(2026, 6, 26),
        sourcePeriodStart: source,
      );
    });

    test('started-on adjustment shifts later and preserves duration', () {
      final adjusted = applyWindowAdjustments(
        medicationId: 1,
        windows: [window],
        adjustments: [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: source,
            kind: WindowAdjustmentKind.startedOn,
            startDate: DateTime(2026, 6, 20),
          ),
        ],
      );

      expect(adjusted.single.start, DateTime(2026, 6, 20));
      expect(adjusted.single.end, DateTime(2026, 7, 1));
    });

    test('started-on adjustment shifts earlier and preserves duration', () {
      final adjusted = applyWindowAdjustments(
        medicationId: 1,
        windows: [window],
        adjustments: [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: source,
            kind: WindowAdjustmentKind.startedOn,
            startDate: DateTime(2026, 6, 10),
          ),
        ],
      );

      expect(adjusted.single.start, DateTime(2026, 6, 10));
      expect(adjusted.single.end, DateTime(2026, 6, 21));
    });

    test('started-on and ended-early adjustments compose', () {
      final adjusted = applyWindowAdjustments(
        medicationId: 1,
        windows: [window],
        adjustments: [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: source,
            kind: WindowAdjustmentKind.endedEarly,
            startDate: DateTime(2026, 6, 20),
            endDate: DateTime(2026, 6, 23),
          ),
        ],
      );

      expect(adjusted.single.start, DateTime(2026, 6, 20));
      expect(adjusted.single.end, DateTime(2026, 6, 23));
    });

    test('skip takes precedence over a started-on adjustment', () {
      final adjusted = applyWindowAdjustments(
        medicationId: 1,
        windows: [window],
        adjustments: [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: source,
            kind: WindowAdjustmentKind.skipped,
            startDate: DateTime(2026, 6, 20),
          ),
        ],
      );

      expect(adjusted, isEmpty);
    });

    test('started-on adjustment leaves other windows untouched', () {
      final other = MedicationWindow(
        start: DateTime(2026, 7, 15),
        end: DateTime(2026, 7, 26),
        sourcePeriodStart: DateTime(2026, 7, 1),
      );
      final adjusted = applyWindowAdjustments(
        medicationId: 1,
        windows: [window, other],
        adjustments: [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: source,
            kind: WindowAdjustmentKind.startedOn,
            startDate: DateTime(2026, 6, 20),
          ),
        ],
      );

      expect(adjusted.last, other);
    });

    test('started-on adjustment is applied before range clipping', () {
      final adjusted = deriveAdjustedWindows(
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
        [Period(start: source)],
        DateRange(start: DateTime(2026, 6, 1), end: DateTime(2026, 6, 30)),
        [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: source,
            kind: WindowAdjustmentKind.startedOn,
            startDate: DateTime(2026, 5, 25),
          ),
        ],
        today: DateTime(2026, 6, 15),
      );

      expect(adjusted.single.start, DateTime(2026, 6, 1));
      expect(adjusted.single.end, DateTime(2026, 6, 5));
    });

    test('ended early shortens a window to a mid-window date', () {
      final adjusted = applyWindowAdjustments(
        medicationId: 1,
        windows: [window],
        adjustments: [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: source,
            kind: WindowAdjustmentKind.endedEarly,
            endDate: DateTime(2026, 6, 18),
          ),
        ],
      );

      expect(adjusted.single.end, DateTime(2026, 6, 18));
    });

    test('ended early before the window start becomes a one-day course', () {
      final adjusted = applyWindowAdjustments(
        medicationId: 1,
        windows: [window],
        adjustments: [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: source,
            kind: WindowAdjustmentKind.endedEarly,
            endDate: DateTime(2026, 6, 10),
          ),
        ],
      );

      expect(adjusted.single.start, DateTime(2026, 6, 15));
      expect(adjusted.single.end, DateTime(2026, 6, 15));
    });

    test('ended early beyond the original end is a no-op', () {
      final adjusted = applyWindowAdjustments(
        medicationId: 1,
        windows: [window],
        adjustments: [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: source,
            kind: WindowAdjustmentKind.endedEarly,
            endDate: DateTime(2026, 7, 1),
          ),
        ],
      );

      expect(adjusted, [window]);
    });

    test('skipped removes the window', () {
      final adjusted = applyWindowAdjustments(
        medicationId: 1,
        windows: [window],
        adjustments: [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: source,
            kind: WindowAdjustmentKind.skipped,
          ),
        ],
      );

      expect(adjusted, isEmpty);
    });

    test('an adjustment for a different source period changes nothing', () {
      final adjusted = applyWindowAdjustments(
        medicationId: 1,
        windows: [window],
        adjustments: [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: DateTime(2026, 5, 1),
            kind: WindowAdjustmentKind.skipped,
          ),
        ],
      );

      expect(adjusted, [window]);
    });

    test('continuous windows are unaffected', () {
      final continuous = MedicationWindow(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 30),
      );
      final adjusted = applyWindowAdjustments(
        medicationId: 1,
        windows: [continuous],
        adjustments: [
          WindowAdjustment(
            medicationId: 1,
            sourcePeriodStart: source,
            kind: WindowAdjustmentKind.skipped,
          ),
        ],
      );

      expect(adjusted, [continuous]);
    });
  });
}

Medication _cyclicalMedication({
  required int startCycleDay,
  required int durationDays,
  DateTime? effectiveStart,
  DateTime? effectiveEnd,
}) => Medication(
  name: 'Progesterone',
  dose: '200 mg',
  schedule: CyclicalMedicationSchedule(
    startCycleDay: startCycleDay,
    durationDays: durationDays,
    effectiveStart: effectiveStart,
    effectiveEnd: effectiveEnd,
  ),
  active: true,
);

Medication _fixedIntervalMedication({int? id, DateTime? effectiveEnd}) =>
    Medication(
      id: id,
      name: 'Progesterone',
      dose: '200 mg',
      schedule: FixedIntervalMedicationSchedule(
        anchor: DateTime(2026, 3, 4),
        intervalDays: 28,
        durationDays: 12,
        effectiveEnd: effectiveEnd,
      ),
      active: effectiveEnd == null,
    );

List<List<String>> _windowDates(List<MedicationWindow> windows) => windows
    .map(
      (window) => [
        for (
          var date = window.start;
          !date.isAfter(window.end);
          date = addCalendarDays(date, 1)
        )
          dateToIso(date),
      ],
    )
    .toList();

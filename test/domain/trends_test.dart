import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/domain/models.dart';
import 'package:hmmm/domain/trends.dart';

void main() {
  test('cycle-day counts use irregular starts and keep no-cycle entries', () {
    final periods = [
      Period(start: DateTime(2026, 1, 30)),
      Period(start: DateTime(2026, 2, 26)),
      Period(start: DateTime(2026, 4, 2)),
    ];
    final entries = [
      _entry(DateTime(2026, 1, 29), 1),
      _entry(DateTime(2026, 1, 30), 1),
      _entry(DateTime(2026, 2, 1), 1),
      _entry(DateTime(2026, 2, 26), 1),
      _entry(DateTime(2026, 3, 1), 1),
      _entry(DateTime(2026, 4, 3), 1),
      _entry(DateTime(2026, 3, 28), 2),
    ];

    final rows = symptomCountsByCycleDay(entries, periods);

    expect(rows, hasLength(2));
    expect(rows.first.typeId, 1);
    expect(rows.first.totalCount, 6);
    expect(rows.first.countsByCycleDay, {1: 2, 2: 1, 3: 1, 4: 1});
    expect(rows.first.noCycleCount, 1);
    expect(rows.last.countsByCycleDay, {31: 1});
  });

  test('monthly counts span twelve months and exclude later dates', () {
    final entries = [
      _entry(DateTime(2025, 2, 28), 1),
      _entry(DateTime(2025, 3, 31), 1),
      _entry(DateTime(2025, 4, 1), 1),
      _entry(DateTime(2026, 2, 15), 1),
      _entry(DateTime(2026, 2, 16), 1),
      _entry(DateTime(2026, 2, 15), 2),
    ];

    final result = symptomCountsByMonth(entries, DateTime(2026, 2, 15));

    expect(result.months.first, DateTime(2025, 3));
    expect(result.months.last, DateTime(2026, 2));
    expect(result.countsByTypeId[1], [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]);
    expect(result.countsByTypeId[2], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]);
  });

  test(
    'observation month span includes months between first and last entry',
    () {
      expect(
        symptomObservationMonthSpan([
          _entry(DateTime(2025, 12, 31), 1),
          _entry(DateTime(2026, 2, 1), 1),
        ]),
        3,
      );
      expect(symptomObservationMonthSpan(const []), 0);
    },
  );
}

SymptomEntry _entry(DateTime date, int typeId) =>
    SymptomEntry(date: date, typeId: typeId, severity: 1);

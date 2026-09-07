import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/domain/cycle_lengths.dart';
import 'package:hmmm/domain/models.dart';

void main() {
  test('regular periods have regular start-to-start cycle lengths', () {
    final periods = [
      Period(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 5)),
      Period(start: DateTime(2026, 1, 29), end: DateTime(2026, 2, 2)),
      Period(start: DateTime(2026, 2, 26), end: DateTime(2026, 3, 2)),
    ];

    expect(cycleLengthsToNext(periods), [28, 28, null]);
  });

  test('irregular periods preserve each start-to-start delta', () {
    final periods = [
      Period(start: DateTime(2026, 1, 3)),
      Period(start: DateTime(2026, 1, 30)),
      Period(start: DateTime(2026, 3, 2)),
    ];

    expect(cycleLengthsToNext(periods), [27, 31, null]);
  });

  test('single period has no following cycle length', () {
    expect(cycleLengthsToNext([Period(start: DateTime(2026, 1, 3))]), [null]);
  });

  test('ongoing last period does not change previous cycle length', () {
    final periods = [
      Period(start: DateTime(2026, 4, 1), end: DateTime(2026, 4, 5)),
      Period(start: DateTime(2026, 5, 2)),
    ];

    expect(cycleLengthsToNext(periods), [31, null]);
  });

  test('window summaries match hand-computed irregular history', () {
    final periods = [
      Period(start: DateTime(2026, 1, 18)),
      Period(start: DateTime(2026, 4, 1)),
      Period(start: DateTime(2026, 7, 1)),
      Period(start: DateTime(2026, 9, 30)),
      Period(start: DateTime(2026, 10, 27)),
      Period(start: DateTime(2026, 11, 28)),
      Period(start: DateTime(2026, 12, 26)),
    ];

    final summaries = cycleLengthSummaries(periods, DateTime(2026, 12, 31));

    expect(
      summaries
          .map(
            (summary) => (
              summary.months,
              summary.sampleCount,
              summary.minimum,
              summary.maximum,
              summary.mean,
            ),
          )
          .toList(),
      [(3, 3, 27, 32, 29.0), (6, 4, 27, 91, 44.5), (12, 6, 27, 91, 57.0)],
    );
  });

  test('window with one period start is insufficient data', () {
    final summaries = cycleLengthSummaries([
      Period(start: DateTime(2026, 1, 1)),
      Period(start: DateTime(2026, 3, 1)),
      Period(start: DateTime(2026, 5, 20)),
    ], DateTime(2026, 6, 15));

    expect(summaries.first.months, 3);
    expect(summaries.first.hasSufficientData, isFalse);
    expect(summaries.first.sampleCount, 0);
    expect(summaries.first.mean, isNull);
    expect(summaries[1].hasSufficientData, isTrue);
  });
}

import 'dates.dart';
import 'models.dart';

List<int?> cycleLengthsToNext(List<Period> sortedPeriods) => [
  for (var index = 0; index < sortedPeriods.length; index++)
    index + 1 < sortedPeriods.length
        ? calendarDaysBetween(
            sortedPeriods[index].start,
            sortedPeriods[index + 1].start,
          )
        : null,
];

class CycleLengthSummary {
  const CycleLengthSummary({
    required this.months,
    required this.sampleCount,
    this.minimum,
    this.maximum,
    this.mean,
  });

  final int months;
  final int sampleCount;
  final int? minimum;
  final int? maximum;
  final double? mean;

  bool get hasSufficientData => sampleCount > 0;
}

List<CycleLengthSummary> cycleLengthSummaries(
  List<Period> sortedPeriods,
  DateTime today,
) => [
  for (final months in const [3, 6, 12])
    _summarizeWindow(sortedPeriods, today, months),
];

CycleLengthSummary _summarizeWindow(
  List<Period> sortedPeriods,
  DateTime today,
  int months,
) {
  final windowStart = _subtractCalendarMonths(today, months);
  final starts = sortedPeriods
      .where(
        (period) =>
            !period.start.isBefore(windowStart) && !period.start.isAfter(today),
      )
      .toList();
  if (starts.length < 2) {
    return CycleLengthSummary(months: months, sampleCount: 0);
  }

  final lengths = cycleLengthsToNext(starts).whereType<int>().toList();
  final total = lengths.fold<int>(0, (sum, length) => sum + length);
  return CycleLengthSummary(
    months: months,
    sampleCount: lengths.length,
    minimum: lengths.reduce((a, b) => a < b ? a : b),
    maximum: lengths.reduce((a, b) => a > b ? a : b),
    mean: total / lengths.length,
  );
}

DateTime _subtractCalendarMonths(DateTime date, int months) {
  final targetMonth = DateTime(date.year, date.month - months);
  final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
  return DateTime(
    targetMonth.year,
    targetMonth.month,
    date.day > lastDay ? lastDay : date.day,
  );
}

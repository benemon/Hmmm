import 'calendar.dart';
import 'models.dart';

class SymptomCycleDayCounts {
  const SymptomCycleDayCounts({
    required this.typeId,
    required this.totalCount,
    required this.countsByCycleDay,
    required this.noCycleCount,
  });

  final int typeId;
  final int totalCount;
  final Map<int, int> countsByCycleDay;
  final int noCycleCount;
}

List<SymptomCycleDayCounts> symptomCountsByCycleDay(
  List<SymptomEntry> entries,
  List<Period> periods,
) {
  final entriesByType = <int, List<SymptomEntry>>{};
  for (final entry in entries) {
    entriesByType.putIfAbsent(entry.typeId, () => []).add(entry);
  }

  final typeIds = entriesByType.keys.toList()..sort();
  return [
    for (final typeId in typeIds)
      _cycleDayCountsForType(typeId, entriesByType[typeId]!, periods),
  ];
}

SymptomCycleDayCounts _cycleDayCountsForType(
  int typeId,
  List<SymptomEntry> entries,
  List<Period> periods,
) {
  final counts = <int, int>{};
  var noCycleCount = 0;
  for (final entry in entries) {
    final cycleDay = cycleDayForDate(entry.date, periods);
    if (cycleDay == null) {
      noCycleCount++;
    } else {
      counts[cycleDay] = (counts[cycleDay] ?? 0) + 1;
    }
  }
  final sortedCounts = <int, int>{
    for (final day in (counts.keys.toList()..sort())) day: counts[day]!,
  };
  return SymptomCycleDayCounts(
    typeId: typeId,
    totalCount: entries.length,
    countsByCycleDay: sortedCounts,
    noCycleCount: noCycleCount,
  );
}

class MonthlySymptomCounts {
  const MonthlySymptomCounts({
    required this.months,
    required this.countsByTypeId,
  });

  final List<DateTime> months;
  final Map<int, List<int>> countsByTypeId;
}

MonthlySymptomCounts symptomCountsByMonth(
  List<SymptomEntry> entries,
  DateTime today,
) {
  final firstMonth = DateTime(today.year, today.month - 11);
  final months = [
    for (var offset = 0; offset < 12; offset++)
      DateTime(firstMonth.year, firstMonth.month + offset),
  ];
  final monthIndexes = {
    for (var index = 0; index < months.length; index++)
      (months[index].year, months[index].month): index,
  };
  final counts = <int, List<int>>{};
  for (final entry in entries) {
    final index = monthIndexes[(entry.date.year, entry.date.month)];
    if (index == null || entry.date.isAfter(today)) continue;
    final row = counts.putIfAbsent(entry.typeId, () => List.filled(12, 0));
    row[index]++;
  }
  return MonthlySymptomCounts(months: months, countsByTypeId: counts);
}

int symptomObservationMonthSpan(List<SymptomEntry> entries) {
  if (entries.isEmpty) return 0;
  var earliest = entries.first.date;
  var latest = entries.first.date;
  for (final entry in entries.skip(1)) {
    if (entry.date.isBefore(earliest)) earliest = entry.date;
    if (entry.date.isAfter(latest)) latest = entry.date;
  }
  return (latest.year - earliest.year) * 12 + latest.month - earliest.month + 1;
}

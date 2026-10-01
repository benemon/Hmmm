import 'dates.dart';
import 'models.dart';

enum PeriodEndState { closed, ongoing, endNotRecorded }

class DerivedPeriod {
  const DerivedPeriod({required this.period, required this.endState});

  final Period period;
  final PeriodEndState endState;

  bool get isOngoing => endState == PeriodEndState.ongoing;

  bool get isEndNotRecorded => endState == PeriodEndState.endNotRecorded;

  DateTime displayEnd(DateTime today) => switch (endState) {
    PeriodEndState.closed => period.end!,
    PeriodEndState.ongoing => dateOnly(today),
    PeriodEndState.endNotRecorded => period.start,
  };

  bool covers(DateTime date, DateTime today) {
    final day = dateOnly(date);
    return !day.isBefore(period.start) && !day.isAfter(displayEnd(today));
  }

  bool endsOn(DateTime date) => switch (endState) {
    PeriodEndState.closed => period.end == date,
    PeriodEndState.ongoing => false,
    PeriodEndState.endNotRecorded => period.start == date,
  };
}

List<DerivedPeriod> derivePeriods(List<Period> sortedPeriods) => [
  for (var index = 0; index < sortedPeriods.length; index++)
    DerivedPeriod(
      period: sortedPeriods[index],
      endState: sortedPeriods[index].end != null
          ? PeriodEndState.closed
          : index == sortedPeriods.length - 1
          ? PeriodEndState.ongoing
          : PeriodEndState.endNotRecorded,
    ),
];

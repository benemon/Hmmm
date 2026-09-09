import 'dates.dart';
import 'hrt_window.dart';
import 'models.dart';

/// Kept Flutter-free; Dim.visibleGlyphLimit is its UI-layer twin.
const visibleDayCellSymptomLimit = 3;

class MedicationDayMarker {
  const MedicationDayMarker({
    required this.medicationId,
    required this.laneIndex,
    required this.startsWindow,
    required this.endsWindow,
  });

  final int medicationId;
  final int laneIndex;
  final bool startsWindow;
  final bool endsWindow;
}

class DayCellMarkerData {
  const DayCellMarkerData({
    required this.inPeriod,
    required this.periodDay,
    required this.startsPeriod,
    required this.endsPeriod,
    required this.medicationMarkers,
    required this.visibleSymptomTypeIds,
    required this.symptomCount,
    required this.symptomOverflowCount,
  });

  final bool inPeriod;
  final int? periodDay;
  final bool startsPeriod;
  final bool endsPeriod;
  final List<MedicationDayMarker> medicationMarkers;
  final List<int> visibleSymptomTypeIds;
  final int symptomCount;
  final int symptomOverflowCount;
}

Map<int, int> laneAssignments(List<Medication> medicationsWithWindows) {
  final ids =
      medicationsWithWindows.map((medication) => medication.id!).toList()
        ..sort();
  return {for (var lane = 0; lane < ids.length; lane++) ids[lane]: lane};
}

int recordedPeriodLength(Period period, DateTime today) =>
    calendarDaysBetween(period.start, period.end ?? today) + 1;

DayCellMarkerData buildDayCellMarkerData({
  required DateTime date,
  required DateTime today,
  required List<Period> periods,
  required Map<int, List<MedicationWindow>> windowsByMedicationId,
  required Map<int, int> laneByMedicationId,
  required List<SymptomEntry> entries,
}) {
  final day = dateOnly(date);
  final currentDate = dateOnly(today);
  Period? period;
  for (final candidate in periods) {
    final end = candidate.end ?? currentDate;
    if (!day.isBefore(candidate.start) && !day.isAfter(end)) {
      period = candidate;
      break;
    }
  }

  final medicationMarkers = <MedicationDayMarker>[];
  for (final lane in laneByMedicationId.entries) {
    for (final window
        in windowsByMedicationId[lane.key] ?? const <MedicationWindow>[]) {
      if (!day.isBefore(window.start) && !day.isAfter(window.end)) {
        medicationMarkers.add(
          MedicationDayMarker(
            medicationId: lane.key,
            laneIndex: lane.value,
            startsWindow: day == window.start,
            endsWindow: day == window.end,
          ),
        );
        break;
      }
    }
  }

  final symptomTypeIds =
      entries
          .where((entry) => entry.date == day)
          .map((entry) => entry.typeId)
          .toList()
        ..sort();
  return DayCellMarkerData(
    inPeriod: period != null,
    periodDay: period == null
        ? null
        : calendarDaysBetween(period.start, day) + 1,
    startsPeriod: period?.start == day,
    endsPeriod: period?.end == day,
    medicationMarkers: medicationMarkers,
    visibleSymptomTypeIds: symptomTypeIds
        .take(visibleDayCellSymptomLimit)
        .toList(),
    symptomCount: symptomTypeIds.length,
    symptomOverflowCount: symptomTypeIds.length > visibleDayCellSymptomLimit
        ? symptomTypeIds.length - visibleDayCellSymptomLimit
        : 0,
  );
}

int? cycleDayForDate(DateTime date, List<Period> periods) {
  final day = dateOnly(date);
  Period? mostRecent;
  for (final period in periods) {
    if (!period.start.isAfter(day) &&
        (mostRecent == null || period.start.isAfter(mostRecent.start))) {
      mostRecent = period;
    }
  }
  return mostRecent == null
      ? null
      : calendarDaysBetween(mostRecent.start, day) + 1;
}

int nextSymptomSeverity(int currentSeverity) =>
    currentSeverity == 3 ? 0 : currentSeverity + 1;

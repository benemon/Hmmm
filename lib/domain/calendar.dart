import 'dates.dart';
import 'hrt_window.dart';
import 'models.dart';
import 'periods.dart';

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

int medicationLaneIndex(
  Map<int, int> laneByMedicationId,
  int medicationId,
  int position,
) => laneByMedicationId[medicationId] ?? position;

class CourseWeekSegment {
  const CourseWeekSegment({
    required this.medicationId,
    required this.laneIndex,
    required this.startColumn,
    required this.endColumn,
    required this.capStart,
    required this.capEnd,
  });

  final int medicationId;
  final int laneIndex;
  final int startColumn;
  final int endColumn;
  final bool capStart;
  final bool capEnd;

  int get length => endColumn - startColumn + 1;
}

List<CourseWeekSegment> courseWeekSegments(List<DayCellMarkerData?> markers) {
  final laneIndices = {
    for (final marker in markers)
      for (final medication in marker?.medicationMarkers ?? const [])
        medication.laneIndex,
  }.toList()..sort();
  final segments = <CourseWeekSegment>[];
  for (final laneIndex in laneIndices) {
    int? startColumn;
    var capStart = false;
    MedicationDayMarker? previous;
    for (var column = 0; column <= markers.length; column++) {
      final current = column == markers.length
          ? null
          : markers[column]?.medicationMarkers
                .where((item) => item.laneIndex == laneIndex)
                .firstOrNull;
      final changed =
          current != null &&
          previous != null &&
          current.medicationId != previous.medicationId;
      if (previous != null && (current == null || changed)) {
        segments.add(
          CourseWeekSegment(
            medicationId: previous.medicationId,
            laneIndex: laneIndex,
            startColumn: startColumn!,
            endColumn: column - 1,
            capStart: capStart,
            capEnd: previous.endsWindow,
          ),
        );
        startColumn = null;
      }
      if (current != null && (previous == null || changed)) {
        startColumn = column;
        capStart = current.startsWindow;
      }
      previous = current;
    }
  }
  return segments;
}

int recordedPeriodLength(DerivedPeriod period, DateTime today) =>
    calendarDaysBetween(period.period.start, period.displayEnd(today)) + 1;

DayCellMarkerData buildDayCellMarkerData({
  required DateTime date,
  required DateTime today,
  required List<DerivedPeriod> periods,
  required Map<int, List<MedicationWindow>> windowsByMedicationId,
  required Map<int, int> laneByMedicationId,
  required List<SymptomEntry> entries,
}) {
  final day = dateOnly(date);
  final currentDate = dateOnly(today);
  DerivedPeriod? period;
  for (final candidate in periods) {
    if (candidate.covers(day, currentDate)) {
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
        : calendarDaysBetween(period.period.start, day) + 1,
    startsPeriod: period?.period.start == day,
    endsPeriod: period?.endsOn(day) ?? false,
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

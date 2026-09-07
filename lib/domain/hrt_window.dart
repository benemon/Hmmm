import 'dates.dart';
import 'models.dart';

class DateRange {
  DateRange({required DateTime start, required DateTime end})
    : start = dateOnly(start),
      end = dateOnly(end) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('Range end must be on or after its start.');
    }
  }

  final DateTime start;
  final DateTime end;
}

class MedicationWindow {
  MedicationWindow({
    required DateTime start,
    required DateTime end,
    DateTime? sourcePeriodStart,
  }) : start = dateOnly(start),
       end = dateOnly(end),
       sourcePeriodStart = sourcePeriodStart == null
           ? null
           : dateOnly(sourcePeriodStart);

  final DateTime start;
  final DateTime end;
  final DateTime? sourcePeriodStart;

  @override
  bool operator ==(Object other) =>
      other is MedicationWindow &&
      start == other.start &&
      end == other.end &&
      sourcePeriodStart == other.sourcePeriodStart;

  @override
  int get hashCode => Object.hash(start, end, sourcePeriodStart);
}

List<MedicationWindow> deriveWindows(
  Medication medication,
  List<Period> periods,
  DateRange range,
) {
  return _clipWindows(_deriveWindows(medication, periods, range), range);
}

List<MedicationWindow> deriveAdjustedWindows(
  Medication medication,
  List<Period> periods,
  DateRange range,
  List<WindowAdjustment> adjustments,
) => _clipWindows(
  applyWindowAdjustments(
    medicationId: medication.id!,
    windows: _deriveWindows(medication, periods, range),
    adjustments: adjustments,
  ),
  range,
);

List<MedicationWindow> applyWindowAdjustments({
  required int medicationId,
  required List<MedicationWindow> windows,
  required List<WindowAdjustment> adjustments,
}) {
  final bySourcePeriod = {
    for (final adjustment in adjustments)
      if (adjustment.medicationId == medicationId)
        adjustment.sourcePeriodStart: adjustment,
  };
  final adjusted = <MedicationWindow>[];
  for (final window in windows) {
    final sourcePeriodStart = window.sourcePeriodStart;
    if (sourcePeriodStart == null) {
      adjusted.add(window);
      continue;
    }
    final adjustment = bySourcePeriod[sourcePeriodStart];
    if (adjustment == null) {
      adjusted.add(window);
      continue;
    }
    if (adjustment.kind == WindowAdjustmentKind.skipped) continue;
    final adjustedEnd = adjustment.endDate!;
    adjusted.add(
      MedicationWindow(
        start: window.start,
        end: adjustedEnd.isBefore(window.start)
            ? window.start
            : adjustedEnd.isAfter(window.end)
            ? window.end
            : adjustedEnd,
        sourcePeriodStart: sourcePeriodStart,
      ),
    );
  }
  return adjusted;
}

List<MedicationWindow> _deriveWindows(
  Medication medication,
  List<Period> periods,
  DateRange range,
) {
  final schedule = medication.schedule;
  if (schedule is ContinuousMedicationSchedule) {
    final end = schedule.end ?? range.end;
    return [MedicationWindow(start: schedule.start, end: end)];
  }

  final cyclical = schedule as CyclicalMedicationSchedule;
  final windows = <MedicationWindow>[];
  for (final period in periods) {
    if (!cyclicalScheduleAppliesToPeriodStart(cyclical, period.start)) {
      continue;
    }
    final start = addCalendarDays(period.start, cyclical.startCycleDay - 1);
    final end = addCalendarDays(start, cyclical.durationDays - 1);
    windows.add(
      MedicationWindow(start: start, end: end, sourcePeriodStart: period.start),
    );
  }
  return windows;
}

List<MedicationWindow> _clipWindows(
  List<MedicationWindow> windows,
  DateRange range,
) => [
  for (final window in windows)
    if (_clipWindow(window.start, window.end, range) case final clipped?)
      MedicationWindow(
        start: clipped.$1,
        end: clipped.$2,
        sourcePeriodStart: window.sourcePeriodStart,
      ),
];

bool cyclicalScheduleAppliesToPeriodStart(
  CyclicalMedicationSchedule schedule,
  DateTime periodStart,
) {
  return (schedule.effectiveStart == null ||
          !periodStart.isBefore(schedule.effectiveStart!)) &&
      (schedule.effectiveEnd == null ||
          !periodStart.isAfter(schedule.effectiveEnd!));
}

bool medicationHasDerivableWindows(
  Medication medication,
  List<Period> periods,
) {
  final schedule = medication.schedule;
  if (schedule is ContinuousMedicationSchedule) return true;
  final cyclical = schedule as CyclicalMedicationSchedule;
  return periods.any(
    (period) => cyclicalScheduleAppliesToPeriodStart(cyclical, period.start),
  );
}

(DateTime, DateTime)? _clipWindow(
  DateTime start,
  DateTime end,
  DateRange range,
) {
  if (end.isBefore(range.start) || start.isAfter(range.end)) {
    return null;
  }
  return (
    start.isBefore(range.start) ? range.start : start,
    end.isAfter(range.end) ? range.end : end,
  );
}

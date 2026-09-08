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

  /// Recorded period start or unadjusted anchor-derived course start.
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
  DateRange range, {
  required DateTime today,
}) {
  return _clipWindows(
    _deriveWindows(medication, periods, range, today: today),
    range,
  );
}

List<MedicationWindow> deriveAdjustedWindows(
  Medication medication,
  List<Period> periods,
  DateRange range,
  List<WindowAdjustment> adjustments, {
  required DateTime today,
}) => _clipWindows(
  applyWindowAdjustments(
    medicationId: medication.id!,
    windows: _deriveWindows(medication, periods, range, today: today),
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
    final durationDays = calendarDaysBetween(window.start, window.end) + 1;
    final adjustedStart = adjustment.startDate ?? window.start;
    final fullEnd = addCalendarDays(adjustedStart, durationDays - 1);
    final recordedEnd = adjustment.endDate;
    final adjustedEnd = recordedEnd == null
        ? fullEnd
        : recordedEnd.isBefore(adjustedStart)
        ? adjustedStart
        : recordedEnd.isAfter(fullEnd)
        ? fullEnd
        : recordedEnd;
    adjusted.add(
      MedicationWindow(
        start: adjustedStart,
        end: adjustedEnd,
        sourcePeriodStart: sourcePeriodStart,
      ),
    );
  }
  return adjusted;
}

List<MedicationWindow> _deriveWindows(
  Medication medication,
  List<Period> periods,
  DateRange range, {
  required DateTime today,
}) {
  final schedule = medication.schedule;
  if (schedule is ContinuousMedicationSchedule) {
    final end = schedule.end ?? range.end;
    return [MedicationWindow(start: schedule.start, end: end)];
  }

  if (schedule is FixedIntervalMedicationSchedule) {
    final horizon = addCalendarDays(dateOnly(today), schedule.intervalDays);
    final windows = <MedicationWindow>[];
    for (
      var start = schedule.anchor;
      !start.isAfter(horizon);
      start = addCalendarDays(start, schedule.intervalDays)
    ) {
      if (schedule.effectiveEnd != null &&
          start.isAfter(schedule.effectiveEnd!)) {
        break;
      }
      windows.add(
        MedicationWindow(
          start: start,
          end: addCalendarDays(start, schedule.durationDays - 1),
          sourcePeriodStart: start,
        ),
      );
    }
    return windows;
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
  List<Period> periods, {
  required DateTime today,
}) {
  final schedule = medication.schedule;
  if (schedule is ContinuousMedicationSchedule) return true;
  if (schedule is FixedIntervalMedicationSchedule) {
    return !schedule.anchor.isAfter(
          addCalendarDays(dateOnly(today), schedule.intervalDays),
        ) &&
        (schedule.effectiveEnd == null ||
            !schedule.anchor.isAfter(schedule.effectiveEnd!));
  }
  final cyclical = schedule as CyclicalMedicationSchedule;
  return periods.any(
    (period) => cyclicalScheduleAppliesToPeriodStart(cyclical, period.start),
  );
}

DateTime? previousAdjustedCourseStart({
  required int medicationId,
  required DateTime sourcePeriodStart,
  required List<MedicationWindow> unadjustedWindows,
  required List<WindowAdjustment> adjustments,
}) {
  MedicationWindow? previous;
  for (final window in unadjustedWindows) {
    final source = window.sourcePeriodStart;
    if (source == null || !source.isBefore(sourcePeriodStart)) continue;
    if (previous == null || source.isAfter(previous.sourcePeriodStart!)) {
      final adjustment = adjustments
          .where(
            (candidate) =>
                candidate.medicationId == medicationId &&
                candidate.sourcePeriodStart == source,
          )
          .firstOrNull;
      if (adjustment?.kind != WindowAdjustmentKind.skipped) previous = window;
    }
  }
  if (previous == null) return null;
  final adjustment = adjustments
      .where(
        (candidate) =>
            candidate.medicationId == medicationId &&
            candidate.sourcePeriodStart == previous!.sourcePeriodStart,
      )
      .firstOrNull;
  return adjustment?.startDate ?? previous.start;
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

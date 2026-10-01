import 'dates.dart';
import 'models.dart';

void validatePeriod(
  Period period,
  List<Period> existing, {
  required DateTime today,
  int? excludingId,
}) {
  final currentDate = dateOnly(today);
  if (period.start.isAfter(currentDate)) {
    throw ArgumentError('Period start cannot be in the future.');
  }
  if (period.end != null && period.end!.isBefore(period.start)) {
    throw ArgumentError('Period end must be on or after its start.');
  }

  final periods = [
    for (final other in existing)
      if (excludingId == null || other.id != excludingId) other,
    period,
  ]..sort((left, right) => left.start.compareTo(right.start));
  for (var index = 0; index + 1 < periods.length; index++) {
    final current = periods[index];
    final next = periods[index + 1];
    if (current.start == next.start ||
        (current.end != null && !current.end!.isBefore(next.start))) {
      throw ArgumentError('Period dates overlap an existing period.');
    }
  }
}

void validateMedication(Medication medication) {
  if (medication.name.trim().isEmpty) {
    throw ArgumentError('Medication name cannot be empty.');
  }
  if (medication.dose.trim().isEmpty) {
    throw ArgumentError('Medication dose cannot be empty.');
  }

  final schedule = medication.schedule;
  if (schedule is CyclicalMedicationSchedule) {
    if (schedule.startCycleDay < 1) {
      throw ArgumentError('Cycle start day must be at least 1.');
    }
    if (schedule.durationDays < 1) {
      throw ArgumentError('Medication duration must be at least 1 day.');
    }
    if (schedule.effectiveStart != null &&
        schedule.effectiveEnd != null &&
        schedule.effectiveEnd!.isBefore(schedule.effectiveStart!)) {
      throw ArgumentError(
        'Medication effective end must be on or after its start.',
      );
    }
  } else if (schedule is FixedIntervalMedicationSchedule) {
    if (schedule.intervalDays < 1) {
      throw ArgumentError('Medication interval must be at least 1 day.');
    }
    if (schedule.durationDays < 1) {
      throw ArgumentError('Medication duration must be at least 1 day.');
    }
  } else if (schedule is ContinuousMedicationSchedule &&
      schedule.end != null &&
      schedule.end!.isBefore(schedule.start)) {
    throw ArgumentError('Medication end must be on or after its start.');
  }
}

void validateSymptomType(SymptomType type) {
  if (type.name.trim().isEmpty) {
    throw ArgumentError('Symptom type name cannot be empty.');
  }
}

void validateSymptomEntry(SymptomEntry entry, {required DateTime today}) {
  if (entry.date.isAfter(dateOnly(today))) {
    throw ArgumentError('Symptom date cannot be in the future.');
  }
  if (entry.severity < 1 || entry.severity > 3) {
    throw ArgumentError('Symptom severity must be between 1 and 3.');
  }
}

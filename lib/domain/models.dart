import 'dates.dart';

class Period {
  Period({this.id, required DateTime start, DateTime? end})
    : start = dateOnly(start),
      end = end == null ? null : dateOnly(end);

  final int? id;
  final DateTime start;
  final DateTime? end;

  @override
  bool operator ==(Object other) =>
      other is Period &&
      id == other.id &&
      start == other.start &&
      end == other.end;

  @override
  int get hashCode => Object.hash(id, start, end);
}

sealed class MedicationSchedule {
  const MedicationSchedule();
}

class CyclicalMedicationSchedule extends MedicationSchedule {
  CyclicalMedicationSchedule({
    required this.startCycleDay,
    required this.durationDays,
    DateTime? effectiveStart,
    DateTime? effectiveEnd,
  }) : effectiveStart = effectiveStart == null
           ? null
           : dateOnly(effectiveStart),
       effectiveEnd = effectiveEnd == null ? null : dateOnly(effectiveEnd);

  final int startCycleDay;
  final int durationDays;
  final DateTime? effectiveStart;
  final DateTime? effectiveEnd;

  @override
  bool operator ==(Object other) =>
      other is CyclicalMedicationSchedule &&
      startCycleDay == other.startCycleDay &&
      durationDays == other.durationDays &&
      effectiveStart == other.effectiveStart &&
      effectiveEnd == other.effectiveEnd;

  @override
  int get hashCode =>
      Object.hash(startCycleDay, durationDays, effectiveStart, effectiveEnd);
}

class ContinuousMedicationSchedule extends MedicationSchedule {
  ContinuousMedicationSchedule({required DateTime start, DateTime? end})
    : start = dateOnly(start),
      end = end == null ? null : dateOnly(end);

  final DateTime start;
  final DateTime? end;

  @override
  bool operator ==(Object other) =>
      other is ContinuousMedicationSchedule &&
      start == other.start &&
      end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}

class Medication {
  const Medication({
    this.id,
    required this.name,
    required this.dose,
    required this.schedule,
    required this.active,
    this.notes,
  });

  final int? id;
  final String name;
  final String dose;
  final MedicationSchedule schedule;
  final bool active;
  final String? notes;

  @override
  bool operator ==(Object other) =>
      other is Medication &&
      id == other.id &&
      name == other.name &&
      dose == other.dose &&
      schedule == other.schedule &&
      active == other.active &&
      notes == other.notes;

  @override
  int get hashCode => Object.hash(id, name, dose, schedule, active, notes);
}

class SymptomType {
  const SymptomType({this.id, required this.name, required this.builtin});

  final int? id;
  final String name;
  final bool builtin;

  @override
  bool operator ==(Object other) =>
      other is SymptomType &&
      id == other.id &&
      name == other.name &&
      builtin == other.builtin;

  @override
  int get hashCode => Object.hash(id, name, builtin);
}

class SymptomEntry {
  SymptomEntry({
    this.id,
    required DateTime date,
    required this.typeId,
    required this.severity,
    this.note,
  }) : date = dateOnly(date);

  final int? id;
  final DateTime date;
  final int typeId;
  final int severity;
  final String? note;

  @override
  bool operator ==(Object other) =>
      other is SymptomEntry &&
      id == other.id &&
      date == other.date &&
      typeId == other.typeId &&
      severity == other.severity &&
      note == other.note;

  @override
  int get hashCode => Object.hash(id, date, typeId, severity, note);
}

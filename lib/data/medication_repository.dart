import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/dates.dart';
import '../domain/hrt_window.dart';
import '../domain/models.dart';
import '../domain/validation.dart';

class MedicationRepository extends ChangeNotifier {
  MedicationRepository(this._database);

  final Database _database;

  Future<List<Medication>> listMedications() async {
    final rows = await _database.rawQuery('''
      SELECT id, name, dose, schedule_type, start_cycle_day, interval_days, duration_days,
             start_date, end_date, active, notes
      FROM medications
      ORDER BY id ASC
    ''');
    return rows.map(_medicationFromRow).toList();
  }

  Future<Medication> insert(Medication medication) async {
    validateMedication(medication);
    final row = _medicationToRow(medication);
    final id = await _database.rawInsert(
      '''
      INSERT INTO medications(
        name, dose, schedule_type, start_cycle_day, interval_days,
        duration_days, start_date, end_date, active, notes
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        row['name'],
        row['dose'],
        row['schedule_type'],
        row['start_cycle_day'],
        row['interval_days'],
        row['duration_days'],
        row['start_date'],
        row['end_date'],
        row['active'],
        row['notes'],
      ],
    );
    notifyListeners();
    return Medication(
      id: id,
      name: medication.name,
      dose: medication.dose,
      schedule: medication.schedule,
      active: medication.active,
      notes: medication.notes,
    );
  }

  Future<void> update(Medication medication) async {
    final id = medication.id;
    if (id == null) {
      throw ArgumentError('Medication id is required for update.');
    }
    validateMedication(medication);
    final row = _medicationToRow(medication);
    await _database.rawUpdate(
      '''
      UPDATE medications SET
        name = ?, dose = ?, schedule_type = ?, start_cycle_day = ?,
        interval_days = ?, duration_days = ?, start_date = ?, end_date = ?,
        active = ?, notes = ?
      WHERE id = ?
      ''',
      [
        row['name'],
        row['dose'],
        row['schedule_type'],
        row['start_cycle_day'],
        row['interval_days'],
        row['duration_days'],
        row['start_date'],
        row['end_date'],
        row['active'],
        row['notes'],
        id,
      ],
    );
    notifyListeners();
  }

  Future<void> delete(int id) async {
    await _database.rawDelete('DELETE FROM medications WHERE id = ?', [id]);
    notifyListeners();
  }

  Future<List<WindowAdjustment>> listAdjustments() async {
    final rows = await _database.rawQuery('''
      SELECT medication_id, source_period_start, kind, start_date, end_date
      FROM window_adjustments
      ORDER BY medication_id ASC, source_period_start ASC
    ''');
    return rows.map(_windowAdjustmentFromRow).toList();
  }

  Future<void> setAdjustment(WindowAdjustment adjustment) async {
    if (adjustment.kind == WindowAdjustmentKind.endedEarly &&
        adjustment.endDate == null) {
      throw ArgumentError('End date is required for an ended course.');
    }
    if (adjustment.kind == WindowAdjustmentKind.startedOn &&
        adjustment.startDate == null) {
      throw ArgumentError('Start date is required for a shifted course.');
    }
    await _database.rawInsert(
      '''
      INSERT INTO window_adjustments(
        medication_id, source_period_start, kind, start_date, end_date
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(medication_id, source_period_start) DO UPDATE SET
        kind = excluded.kind,
        start_date = excluded.start_date,
        end_date = excluded.end_date
      ''',
      [
        adjustment.medicationId,
        dateToIso(adjustment.sourcePeriodStart),
        switch (adjustment.kind) {
          WindowAdjustmentKind.startedOn => 'started_on',
          WindowAdjustmentKind.endedEarly => 'ended_early',
          WindowAdjustmentKind.skipped => 'skipped',
        },
        adjustment.startDate == null ? null : dateToIso(adjustment.startDate!),
        adjustment.endDate == null ? null : dateToIso(adjustment.endDate!),
      ],
    );
    notifyListeners();
  }

  Future<void> clearAdjustment(
    int medicationId,
    DateTime sourcePeriodStart,
  ) async {
    await _database.rawDelete(
      '''
      DELETE FROM window_adjustments
      WHERE medication_id = ? AND source_period_start = ?
      ''',
      [medicationId, dateToIso(sourcePeriodStart)],
    );
    notifyListeners();
  }

  Future<
    ({
      List<WindowAdjustment> adjustments,
      Map<int, List<MedicationWindow>> windowsByMedicationId,
    })
  >
  loadAdjustedWindows({
    required List<Medication> medications,
    required List<Period> periods,
    required DateRange range,
    required DateTime today,
  }) async {
    final adjustments = await listAdjustments();
    return (
      adjustments: adjustments,
      windowsByMedicationId: {
        for (final medication in medications)
          medication.id!: deriveAdjustedWindows(
            medication,
            periods,
            range,
            adjustments,
            today: today,
          ),
      },
    );
  }

  void refresh() => notifyListeners();
}

WindowAdjustment _windowAdjustmentFromRow(Map<String, Object?> row) =>
    WindowAdjustment(
      medicationId: row['medication_id'] as int,
      sourcePeriodStart: dateFromIso(row['source_period_start'] as String),
      kind: switch (row['kind']) {
        'started_on' => WindowAdjustmentKind.startedOn,
        'ended_early' => WindowAdjustmentKind.endedEarly,
        _ => WindowAdjustmentKind.skipped,
      },
      startDate: row['start_date'] == null
          ? null
          : dateFromIso(row['start_date'] as String),
      endDate: row['end_date'] == null
          ? null
          : dateFromIso(row['end_date'] as String),
    );

Medication _medicationFromRow(Map<String, Object?> row) {
  final MedicationSchedule schedule;
  if (row['schedule_type'] == 'cyclical') {
    schedule = CyclicalMedicationSchedule(
      startCycleDay: row['start_cycle_day'] as int,
      durationDays: row['duration_days'] as int,
      effectiveStart: row['start_date'] == null
          ? null
          : dateFromIso(row['start_date'] as String),
      effectiveEnd: row['end_date'] == null
          ? null
          : dateFromIso(row['end_date'] as String),
    );
  } else if (row['schedule_type'] == 'fixed_interval') {
    schedule = FixedIntervalMedicationSchedule(
      anchor: dateFromIso(row['start_date'] as String),
      intervalDays: row['interval_days'] as int,
      durationDays: row['duration_days'] as int,
      effectiveEnd: row['end_date'] == null
          ? null
          : dateFromIso(row['end_date'] as String),
    );
  } else {
    schedule = ContinuousMedicationSchedule(
      start: dateFromIso(row['start_date'] as String),
      end: row['end_date'] == null
          ? null
          : dateFromIso(row['end_date'] as String),
    );
  }
  return Medication(
    id: row['id'] as int,
    name: row['name'] as String,
    dose: row['dose'] as String,
    schedule: schedule,
    active: row['active'] == 1,
    notes: row['notes'] as String?,
  );
}

Map<String, Object?> _medicationToRow(Medication medication) {
  final schedule = medication.schedule;
  if (schedule is CyclicalMedicationSchedule) {
    return {
      'name': medication.name,
      'dose': medication.dose,
      'schedule_type': 'cyclical',
      'start_cycle_day': schedule.startCycleDay,
      'interval_days': null,
      'duration_days': schedule.durationDays,
      'start_date': schedule.effectiveStart == null
          ? null
          : dateToIso(schedule.effectiveStart!),
      'end_date': schedule.effectiveEnd == null
          ? null
          : dateToIso(schedule.effectiveEnd!),
      'active': medication.active ? 1 : 0,
      'notes': medication.notes,
    };
  }
  if (schedule is FixedIntervalMedicationSchedule) {
    return {
      'name': medication.name,
      'dose': medication.dose,
      'schedule_type': 'fixed_interval',
      'start_cycle_day': null,
      'interval_days': schedule.intervalDays,
      'duration_days': schedule.durationDays,
      'start_date': dateToIso(schedule.anchor),
      'end_date': schedule.effectiveEnd == null
          ? null
          : dateToIso(schedule.effectiveEnd!),
      'active': medication.active ? 1 : 0,
      'notes': medication.notes,
    };
  }
  final continuous = schedule as ContinuousMedicationSchedule;
  return {
    'name': medication.name,
    'dose': medication.dose,
    'schedule_type': 'continuous',
    'start_cycle_day': null,
    'interval_days': null,
    'duration_days': null,
    'start_date': dateToIso(continuous.start),
    'end_date': continuous.end == null ? null : dateToIso(continuous.end!),
    'active': medication.active ? 1 : 0,
    'notes': medication.notes,
  };
}

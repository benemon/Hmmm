import 'package:flutter/material.dart';

import '../data/medication_repository.dart';
import '../data/period_repository.dart';
import '../domain/calendar.dart';
import '../domain/hrt_window.dart';
import '../domain/models.dart';
import 'feedback.dart';
import 'format.dart';
import 'theme.dart';

class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({
    super.key,
    required this.medicationRepository,
    required this.periodRepository,
    required this.today,
  });

  final MedicationRepository medicationRepository;
  final PeriodRepository periodRepository;
  final DateTime today;

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  late final Listenable _repositories;

  @override
  void initState() {
    super.initState();
    _repositories = Listenable.merge([
      widget.medicationRepository,
      widget.periodRepository,
    ]);
  }

  Future<_MedicationData> _loadData() async => _MedicationData(
    medications: await widget.medicationRepository.listMedications(),
    periods: await widget.periodRepository.listPeriods(),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repositories,
      builder: (context, child) => FutureBuilder<_MedicationData>(
        future: _loadData(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          final laneById = laneAssignments([
            for (final medication in data?.medications ?? const <Medication>[])
              if (medicationHasDerivableWindows(medication, data!.periods))
                medication,
          ]);
          return Scaffold(
            appBar: AppBar(title: const Text('Medications')),
            body: data == null
                ? const SizedBox.shrink()
                : data.medications.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No medications configured.'),
                  )
                : ListView.separated(
                    itemCount: data.medications.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final medication = data.medications[index];
                      return _MedicationTile(
                        medication: medication,
                        laneIndex: laneById[medication.id!],
                        repository: widget.medicationRepository,
                        today: widget.today,
                        onEdit: () => _openForm(medication),
                      );
                    },
                  ),
            floatingActionButton: FloatingActionButton(
              key: const ValueKey('add-medication'),
              tooltip: 'Add medication',
              onPressed: () => _openForm(null),
              child: const Icon(Icons.add),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openForm(Medication? medication) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => _MedicationFormScreen(
        repository: widget.medicationRepository,
        medication: medication,
        today: widget.today,
      ),
    ),
  );
}

class _MedicationData {
  const _MedicationData({required this.medications, required this.periods});

  final List<Medication> medications;
  final List<Period> periods;
}

enum _MedicationAction { stop, resume, delete }

class _MedicationTile extends StatelessWidget {
  const _MedicationTile({
    required this.medication,
    required this.laneIndex,
    required this.repository,
    required this.today,
    required this.onEdit,
  });

  final Medication medication;
  final int? laneIndex;
  final MedicationRepository repository;
  final DateTime today;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final lane = laneIndex;
    return ListTile(
      key: ValueKey('medication-${medication.id}'),
      leading: lane == null
          ? const SizedBox(width: 20)
          : Container(
              width: 20,
              height: 5,
              color: Markers.of(context).lane(lane),
            ),
      title: Text(medication.name),
      subtitle: Text('${medication.dose}\n${_scheduleSummary(medication)}'),
      isThreeLine: true,
      onTap: onEdit,
      trailing: PopupMenuButton<_MedicationAction>(
        key: ValueKey('medication-actions-${medication.id}'),
        onSelected: (action) => _applyAction(context, action),
        itemBuilder: (context) => [
          if (!medication.active)
            const PopupMenuItem(
              value: _MedicationAction.resume,
              child: Text('Resume'),
            )
          else if (lane != null)
            const PopupMenuItem(
              value: _MedicationAction.stop,
              child: Text('Stop'),
            ),
          const PopupMenuItem(
            value: _MedicationAction.delete,
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyAction(
    BuildContext context,
    _MedicationAction action,
  ) async {
    switch (action) {
      case _MedicationAction.stop:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(
              'Stop ${medication.name}? Historical windows are kept.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('confirm-stop-medication'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Stop'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
        await _update(context, _stoppedMedication(medication, today));
      case _MedicationAction.resume:
        await _update(context, _resumedMedication(medication));
      case _MedicationAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(
              'Delete ${medication.name}? All its derived windows disappear '
              'from the calendar and exports.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('confirm-delete-medication'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true) await repository.delete(medication.id!);
    }
  }

  Future<void> _update(BuildContext context, Medication updated) async {
    try {
      await repository.update(updated);
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }
}

class _MedicationFormScreen extends StatefulWidget {
  const _MedicationFormScreen({
    required this.repository,
    required this.medication,
    required this.today,
  });

  final MedicationRepository repository;
  final Medication? medication;
  final DateTime today;

  @override
  State<_MedicationFormScreen> createState() => _MedicationFormScreenState();
}

enum _ScheduleType { cyclical, continuous }

const _doseUnits = [
  'mg',
  'micrograms',
  'g',
  'ml',
  'tablets',
  'capsules',
  'pumps',
  'sprays',
  'patches',
];

class _MedicationFormScreenState extends State<_MedicationFormScreen> {
  late final _DoseParts? _parsedDose = widget.medication == null
      ? const _DoseParts(amount: '', unit: 'mg')
      : _parseDose(widget.medication!.dose);
  late final bool _usesLegacyDose =
      widget.medication != null && _parsedDose == null;
  late final TextEditingController _nameController = TextEditingController(
    text: widget.medication?.name ?? '',
  );
  late final TextEditingController _doseController = TextEditingController(
    text: widget.medication?.dose ?? '',
  );
  late final TextEditingController _doseAmountController =
      TextEditingController(text: _parsedDose?.amount ?? '');
  late String _doseUnit = _parsedDose?.unit ?? _doseUnits.first;
  late final TextEditingController _cycleDayController = TextEditingController(
    text: _cyclical?.startCycleDay.toString() ?? '15',
  );
  late final TextEditingController _durationController = TextEditingController(
    text: _cyclical?.durationDays.toString() ?? '12',
  );
  late _ScheduleType _scheduleType =
      widget.medication?.schedule is ContinuousMedicationSchedule
      ? _ScheduleType.continuous
      : _ScheduleType.cyclical;
  late DateTime? _effectiveStart = _cyclical?.effectiveStart;
  late DateTime? _effectiveEnd = _cyclical?.effectiveEnd;
  late DateTime _continuousStart = _continuous?.start ?? widget.today;
  late DateTime? _continuousEnd = _continuous?.end;

  CyclicalMedicationSchedule? get _cyclical =>
      widget.medication?.schedule is CyclicalMedicationSchedule
      ? widget.medication!.schedule as CyclicalMedicationSchedule
      : null;

  ContinuousMedicationSchedule? get _continuous =>
      widget.medication?.schedule is ContinuousMedicationSchedule
      ? widget.medication!.schedule as ContinuousMedicationSchedule
      : null;

  @override
  void dispose() {
    _nameController.dispose();
    _doseController.dispose();
    _doseAmountController.dispose();
    _cycleDayController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.medication == null ? 'Add medication' : 'Edit medication',
        ),
        actions: [
          TextButton(
            key: const ValueKey('save-medication'),
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const ValueKey('medication-name'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          if (_usesLegacyDose)
            TextField(
              key: const ValueKey('medication-dose'),
              controller: _doseController,
              decoration: const InputDecoration(labelText: 'Dose'),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('medication-dose-amount'),
                    controller: _doseAmountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('medication-dose-unit'),
                    initialValue: _doseUnit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: [
                      for (final unit in _doseUnits)
                        DropdownMenuItem(value: unit, child: Text(unit)),
                    ],
                    onChanged: (unit) {
                      if (unit != null) setState(() => _doseUnit = unit);
                    },
                  ),
                ),
              ],
            ),
          const SizedBox(height: 20),
          SegmentedButton<_ScheduleType>(
            key: const ValueKey('medication-schedule-type'),
            segments: const [
              ButtonSegment(
                value: _ScheduleType.cyclical,
                label: Text('Cyclical'),
              ),
              ButtonSegment(
                value: _ScheduleType.continuous,
                label: Text('Continuous'),
              ),
            ],
            selected: {_scheduleType},
            onSelectionChanged: (selected) =>
                setState(() => _scheduleType = selected.single),
          ),
          const SizedBox(height: 16),
          if (_scheduleType == _ScheduleType.cyclical) ...[
            TextField(
              key: const ValueKey('medication-cycle-day'),
              controller: _cycleDayController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Start cycle day'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('medication-duration'),
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Duration days'),
            ),
            const SizedBox(height: 8),
            _OptionalDateTile(
              label: 'Effective start',
              value: _effectiveStart,
              today: widget.today,
              onChanged: (value) => setState(() => _effectiveStart = value),
            ),
            _OptionalDateTile(
              label: 'Effective end',
              value: _effectiveEnd,
              today: widget.today,
              onChanged: (value) => setState(() => _effectiveEnd = value),
            ),
          ] else ...[
            _RequiredDateTile(
              label: 'Start',
              value: _continuousStart,
              today: widget.today,
              onChanged: (value) => setState(() => _continuousStart = value),
            ),
            _OptionalDateTile(
              label: 'End',
              value: _continuousEnd,
              today: widget.today,
              onChanged: (value) => setState(() => _continuousEnd = value),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final schedule = switch (_scheduleType) {
      _ScheduleType.cyclical => CyclicalMedicationSchedule(
        startCycleDay: int.tryParse(_cycleDayController.text) ?? 0,
        durationDays: int.tryParse(_durationController.text) ?? 0,
        effectiveStart: _effectiveStart,
        effectiveEnd: _effectiveEnd,
      ),
      _ScheduleType.continuous => ContinuousMedicationSchedule(
        start: _continuousStart,
        end: _continuousEnd,
      ),
    };
    final original = widget.medication;
    try {
      final medication = Medication(
        id: original?.id,
        name: _nameController.text.trim(),
        dose: _dose(),
        schedule: schedule,
        active: original?.active ?? true,
        notes: original?.notes,
      );
      if (original == null) {
        await widget.repository.insert(medication);
      } else {
        await widget.repository.update(medication);
      }
      if (mounted) Navigator.pop(context);
    } on ArgumentError catch (error) {
      if (mounted) showValidationError(context, error);
    }
  }

  String _dose() {
    if (_usesLegacyDose) return _doseController.text;
    final amount = _doseAmountController.text.trim();
    if (amount.isEmpty) throw ArgumentError('Dose amount is required.');
    final value = double.tryParse(amount);
    if (!RegExp(r'^(?:\d+(?:\.\d+)?|\.\d+)$').hasMatch(amount) ||
        value == null ||
        !value.isFinite ||
        value <= 0) {
      throw ArgumentError('Dose amount must be a positive number.');
    }
    return '$amount $_doseUnit';
  }
}

class _DoseParts {
  const _DoseParts({required this.amount, required this.unit});

  final String amount;
  final String unit;
}

_DoseParts? _parseDose(String dose) {
  final match = RegExp(
    r'^(\d+(?:\.\d+)?|\.\d+) (mg|micrograms|g|ml|tablets|capsules|pumps|sprays|patches)$',
  ).firstMatch(dose);
  if (match == null) return null;
  return _DoseParts(amount: match.group(1)!, unit: match.group(2)!);
}

class _RequiredDateTile extends StatelessWidget {
  const _RequiredDateTile({
    required this.label,
    required this.value,
    required this.today,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final DateTime today;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(formatDate(value), style: tabularFigures),
      onTap: () async {
        final selected = await _pickDate(context, value, today);
        if (selected != null) onChanged(selected);
      },
    );
  }
}

class _OptionalDateTile extends StatelessWidget {
  const _OptionalDateTile({
    required this.label,
    required this.value,
    required this.today,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final DateTime today;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value == null ? 'not set' : formatDate(value!),
            style: tabularFigures,
          ),
          if (value != null)
            IconButton(
              tooltip: 'Clear $label',
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      onTap: () async {
        final selected = await _pickDate(context, value ?? today, today);
        if (selected != null) onChanged(selected);
      },
    );
  }
}

Future<DateTime?> _pickDate(
  BuildContext context,
  DateTime initialDate,
  DateTime today,
) => showDatePicker(
  context: context,
  initialDate: initialDate,
  firstDate: DateTime(1900),
  lastDate: today,
);

Medication _stoppedMedication(Medication medication, DateTime today) {
  final schedule = medication.schedule;
  return Medication(
    id: medication.id,
    name: medication.name,
    dose: medication.dose,
    schedule: schedule is CyclicalMedicationSchedule
        ? CyclicalMedicationSchedule(
            startCycleDay: schedule.startCycleDay,
            durationDays: schedule.durationDays,
            effectiveStart: schedule.effectiveStart,
            effectiveEnd: today,
          )
        : ContinuousMedicationSchedule(
            start: (schedule as ContinuousMedicationSchedule).start,
            end: today,
          ),
    active: false,
    notes: medication.notes,
  );
}

Medication _resumedMedication(Medication medication) {
  final schedule = medication.schedule;
  return Medication(
    id: medication.id,
    name: medication.name,
    dose: medication.dose,
    schedule: schedule is CyclicalMedicationSchedule
        ? CyclicalMedicationSchedule(
            startCycleDay: schedule.startCycleDay,
            durationDays: schedule.durationDays,
            effectiveStart: schedule.effectiveStart,
          )
        : ContinuousMedicationSchedule(
            start: (schedule as ContinuousMedicationSchedule).start,
          ),
    active: true,
    notes: medication.notes,
  );
}

String _scheduleSummary(Medication medication) {
  final schedule = medication.schedule;
  if (schedule is CyclicalMedicationSchedule) {
    return 'from cycle day ${schedule.startCycleDay}, '
        '${schedule.durationDays} days${_stoppedSuffix(schedule.effectiveEnd)}';
  }
  final continuous = schedule as ContinuousMedicationSchedule;
  return 'continuous from ${formatDate(continuous.start)}'
      '${_stoppedSuffix(continuous.end)}';
}

String _stoppedSuffix(DateTime? end) =>
    end == null ? '' : ' (stopped ${formatDate(end)})';

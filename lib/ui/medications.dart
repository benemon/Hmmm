import 'package:flutter/material.dart';

import '../data/medication_repository.dart';
import '../data/period_repository.dart';
import '../domain/calendar.dart';
import '../domain/hrt_window.dart';
import '../domain/models.dart';
import 'empty_state.dart';
import 'feedback.dart';
import 'format.dart';
import 'marker_band.dart';
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
              if (medicationHasDerivableWindows(
                medication,
                data!.periods,
                today: widget.today,
              ))
                medication,
          ]);
          return Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Medications'),
                  if (data != null)
                    Text(
                      '${data.medications.length} ${data.medications.length == 1 ? 'medication' : 'medications'}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
            body: data == null
                ? const SizedBox.shrink()
                : data.medications.isEmpty
                ? const RecordEmptyState(
                    count: '0 medications',
                    action: 'Tap Add medication.',
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
            floatingActionButton: FloatingActionButton.extended(
              key: const ValueKey('add-medication'),
              tooltip: 'Add medication',
              onPressed: () => _openForm(null),
              icon: const Icon(Icons.add),
              label: const Text('Add medication'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Dim.radiusControl),
              ),
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
    final laneMarker = lane == null ? null : Markers.of(context).lane(lane);
    return ListTile(
      key: ValueKey('medication-${medication.id}'),
      leading: lane == null
          ? null
          : Semantics(
              key: ValueKey('medication-lane-${medication.id}'),
              container: true,
              label: 'calendar lane ${lane + 1}',
              child: ExcludeSemantics(
                child: SizedBox(
                  width: 20,
                  child: MarkerBand(
                    color: laneMarker!.color,
                    height: Dim.laneBandHeight,
                    texture: laneMarker.texture,
                  ),
                ),
              ),
            ),
      title: Text(medication.name, style: HmmmType.of(context).bodyStrong),
      subtitle: Text(
        _medicationFacts(medication, laneMarker?.label),
        style: HmmmType.of(context).figureSmall
            .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
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
          else
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
            title: Text('Stop ${medication.name}?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(medication.name, style: HmmmType.of(context).figure),
                const SizedBox(height: Dim.s1),
                const Text('Historical medication windows are kept.'),
              ],
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
            title: Text('Delete ${medication.name}?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(medication.name, style: HmmmType.of(context).figure),
                const SizedBox(height: Dim.s1),
                const Text(
                  'All its derived windows are removed from the calendar and exports.',
                ),
              ],
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

enum _ScheduleType { cyclical, fixedInterval, continuous }

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
    text:
        (_cyclical?.durationDays ?? _fixedInterval?.durationDays)?.toString() ??
        '12',
  );
  late final TextEditingController _intervalController = TextEditingController(
    text: _fixedInterval?.intervalDays.toString() ?? '28',
  );
  late _ScheduleType _scheduleType = switch (widget.medication?.schedule) {
    FixedIntervalMedicationSchedule() => _ScheduleType.fixedInterval,
    ContinuousMedicationSchedule() => _ScheduleType.continuous,
    _ => _ScheduleType.cyclical,
  };
  late DateTime? _effectiveStart = _cyclical?.effectiveStart;
  late DateTime? _effectiveEnd = _cyclical?.effectiveEnd;
  late DateTime _intervalAnchor = _fixedInterval?.anchor ?? widget.today;
  late DateTime _continuousStart = _continuous?.start ?? widget.today;
  late DateTime? _continuousEnd = _continuous?.end;

  CyclicalMedicationSchedule? get _cyclical =>
      widget.medication?.schedule is CyclicalMedicationSchedule
      ? widget.medication!.schedule as CyclicalMedicationSchedule
      : null;

  FixedIntervalMedicationSchedule? get _fixedInterval =>
      widget.medication?.schedule is FixedIntervalMedicationSchedule
      ? widget.medication!.schedule as FixedIntervalMedicationSchedule
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
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final inverse = Theme.of(context).colorScheme.surface;
    final verticalSchedule = MediaQuery.textScalerOf(context).scale(1) >= 2;
    final derivation = _derivationLine();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.medication?.name ?? 'Add medication'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Dim.s2),
            child: FilledButton(
              key: const ValueKey('save-medication'),
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Dim.s4, Dim.s4, Dim.s4, Dim.s7),
        children: [
          _LabeledField(
            label: 'NAME',
            child: TextField(
              key: const ValueKey('medication-name'),
              controller: _nameController,
              style: HmmmType.of(context).figure,
              decoration: const InputDecoration(),
            ),
          ),
          const SizedBox(height: Dim.s3),
          if (_usesLegacyDose)
            _LabeledField(
              label: 'DOSE',
              child: TextField(
                key: const ValueKey('medication-dose'),
                controller: _doseController,
                style: HmmmType.of(context).figure,
                decoration: const InputDecoration(),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final fieldWidth = verticalSchedule
                    ? constraints.maxWidth
                    : (constraints.maxWidth - Dim.s3) / 2;
                return Wrap(
                  spacing: Dim.s3,
                  runSpacing: Dim.s3,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: _LabeledField(
                        label: 'AMOUNT',
                        child: TextField(
                          key: const ValueKey('medication-dose-amount'),
                          controller: _doseAmountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: HmmmType.of(context).figure,
                          decoration: const InputDecoration(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: _LabeledField(
                        label: 'UNIT',
                        child: DropdownButtonFormField<String>(
                          key: const ValueKey('medication-dose-unit'),
                          initialValue: _doseUnit,
                          style: HmmmType.of(context).figure,
                          decoration: const InputDecoration(),
                          items: [
                            for (final unit in _doseUnits)
                              DropdownMenuItem(value: unit, child: Text(unit)),
                          ],
                          onChanged: (unit) {
                            if (unit != null) setState(() => _doseUnit = unit);
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          const SizedBox(height: Dim.s5),
          _LabeledField(
            label: 'SCHEDULE',
            child: SizedBox(
              width: double.infinity,
              height: verticalSchedule ? Dim.minTarget * 3 : null,
              child: SegmentedButton<_ScheduleType>(
                key: const ValueKey('medication-schedule-type'),
                direction: verticalSchedule ? Axis.vertical : Axis.horizontal,
                expandedInsets: EdgeInsets.zero,
                segments: const [
                  ButtonSegment(
                    value: _ScheduleType.cyclical,
                    label: Text('Cycle day'),
                  ),
                  ButtonSegment(
                    value: _ScheduleType.fixedInterval,
                    label: Text('Interval'),
                  ),
                  ButtonSegment(
                    value: _ScheduleType.continuous,
                    label: Text('Continuous'),
                  ),
                ],
                selected: {_scheduleType},
                showSelectedIcon: false,
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(
                    Size(0, Dim.minTarget),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? ink
                        : Colors.transparent,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) =>
                        states.contains(WidgetState.selected) ? inverse : ink,
                  ),
                ),
                onSelectionChanged: (selected) =>
                    setState(() => _scheduleType = selected.single),
              ),
            ),
          ),
          const SizedBox(height: Dim.s2),
          Text(
            switch (_scheduleType) {
              _ScheduleType.cyclical =>
                'derived from each recorded period start',
              _ScheduleType.fixedInterval =>
                'derived from the anchor date at a fixed interval',
              _ScheduleType.continuous =>
                'applies continuously between recorded dates',
            },
            style: HmmmType.of(context).figureSmall.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Dim.s1),
          Semantics(
            key: const ValueKey('medication-derivation'),
            label: derivation,
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.arrow_forward,
                    size: MediaQuery.textScalerOf(context).scale(13),
                  ),
                  const SizedBox(width: Dim.s1),
                  Expanded(
                    child: Text(
                      derivation,
                      style: HmmmType.of(context).figureSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Dim.s4),
          if (_scheduleType == _ScheduleType.cyclical) ...[
            _LabeledField(
              label: 'START CYCLE DAY',
              child: TextField(
                key: const ValueKey('medication-cycle-day'),
                controller: _cycleDayController,
                keyboardType: TextInputType.number,
                style: HmmmType.of(context).figure,
                decoration: const InputDecoration(),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: Dim.s3),
            _LabeledField(
              label: 'DURATION DAYS',
              child: TextField(
                key: const ValueKey('medication-duration'),
                controller: _durationController,
                keyboardType: TextInputType.number,
                style: HmmmType.of(context).figure,
                decoration: const InputDecoration(),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: Dim.s3),
            _OptionalDateField(
              label: 'EFFECTIVE START',
              value: _effectiveStart,
              today: widget.today,
              onChanged: (value) => setState(() => _effectiveStart = value),
            ),
            const SizedBox(height: Dim.s3),
            _OptionalDateField(
              label: 'EFFECTIVE END',
              value: _effectiveEnd,
              today: widget.today,
              onChanged: (value) => setState(() => _effectiveEnd = value),
            ),
          ] else if (_scheduleType == _ScheduleType.fixedInterval) ...[
            _RequiredDateField(
              label: 'ANCHOR DATE',
              value: _intervalAnchor,
              today: widget.today,
              onChanged: (value) => setState(() => _intervalAnchor = value),
            ),
            const SizedBox(height: Dim.s3),
            _LabeledField(
              label: 'EVERY (DAYS)',
              child: TextField(
                key: const ValueKey('medication-interval-days'),
                controller: _intervalController,
                keyboardType: TextInputType.number,
                style: HmmmType.of(context).figure,
                decoration: const InputDecoration(),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: Dim.s3),
            _LabeledField(
              label: 'DURATION (DAYS)',
              child: TextField(
                key: const ValueKey('medication-interval-duration'),
                controller: _durationController,
                keyboardType: TextInputType.number,
                style: HmmmType.of(context).figure,
                decoration: const InputDecoration(),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ] else ...[
            _RequiredDateField(
              label: 'START',
              value: _continuousStart,
              today: widget.today,
              onChanged: (value) => setState(() => _continuousStart = value),
            ),
            const SizedBox(height: Dim.s3),
            _OptionalDateField(
              label: 'END',
              value: _continuousEnd,
              today: widget.today,
              onChanged: (value) => setState(() => _continuousEnd = value),
            ),
          ],
        ],
      ),
    );
  }

  String _derivationLine() {
    if (_scheduleType == _ScheduleType.continuous) {
      return 'continuous since ${formatDate(_continuousStart)}'
          '${_continuousEnd == null ? '' : ' to ${formatDate(_continuousEnd!)}'}';
    }
    if (_scheduleType == _ScheduleType.fixedInterval) {
      final interval = int.tryParse(_intervalController.text);
      final duration = int.tryParse(_durationController.text);
      if (interval == null ||
          duration == null ||
          interval < 1 ||
          duration < 1) {
        return 'enter an interval and duration';
      }
      return '$duration days every $interval days from '
          '${formatDate(_intervalAnchor)}';
    }
    final start = int.tryParse(_cycleDayController.text);
    final duration = int.tryParse(_durationController.text);
    if (start == null || duration == null || start < 1 || duration < 1) {
      return 'enter a cycle day and duration';
    }
    return 'cycle day $start to ${start + duration - 1}, '
        '$duration days per recorded cycle';
  }

  Future<void> _save() async {
    final schedule = switch (_scheduleType) {
      _ScheduleType.cyclical => CyclicalMedicationSchedule(
        startCycleDay: int.tryParse(_cycleDayController.text) ?? 0,
        durationDays: int.tryParse(_durationController.text) ?? 0,
        effectiveStart: _effectiveStart,
        effectiveEnd: _effectiveEnd,
      ),
      _ScheduleType.fixedInterval => FixedIntervalMedicationSchedule(
        anchor: _intervalAnchor,
        intervalDays: int.tryParse(_intervalController.text) ?? 0,
        durationDays: int.tryParse(_durationController.text) ?? 0,
        effectiveEnd: _fixedInterval?.effectiveEnd,
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

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: Dim.s1),
        child,
      ],
    );
  }
}

class _RequiredDateField extends StatelessWidget {
  const _RequiredDateField({
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
    return _LabeledField(
      label: label,
      child: _DateControl(
        value: formatDate(value),
        onTap: () async {
          final selected = await pickDate(context, value, today);
          if (selected != null) onChanged(selected);
        },
      ),
    );
  }
}

class _OptionalDateField extends StatelessWidget {
  const _OptionalDateField({
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
    return _LabeledField(
      label: label,
      child: _DateControl(
        value: value == null ? 'not set' : formatDate(value!),
        onTap: () async {
          final selected = await pickDate(context, value ?? today, today);
          if (selected != null) onChanged(selected);
        },
        onClear: value == null ? null : () => onChanged(null),
      ),
    );
  }
}

class _DateControl extends StatelessWidget {
  const _DateControl({required this.value, required this.onTap, this.onClear});

  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Dim.radiusControl),
        child: Container(
          constraints: const BoxConstraints(minHeight: Dim.minTarget),
          padding: EdgeInsets.only(
            left: Dim.s3,
            right: onClear == null ? Dim.s3 : 0,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(Dim.radiusControl),
          ),
          child: Row(
            children: [
              Expanded(child: Text(value, style: HmmmType.of(context).figure)),
              if (onClear != null)
                IconButton(
                  tooltip: 'Clear date',
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Medication _stoppedMedication(Medication medication, DateTime today) {
  final schedule = medication.schedule;
  return Medication(
    id: medication.id,
    name: medication.name,
    dose: medication.dose,
    schedule: switch (schedule) {
      CyclicalMedicationSchedule() => CyclicalMedicationSchedule(
        startCycleDay: schedule.startCycleDay,
        durationDays: schedule.durationDays,
        effectiveStart: schedule.effectiveStart,
        effectiveEnd: today,
      ),
      FixedIntervalMedicationSchedule() => FixedIntervalMedicationSchedule(
        anchor: schedule.anchor,
        intervalDays: schedule.intervalDays,
        durationDays: schedule.durationDays,
        effectiveEnd: today,
      ),
      ContinuousMedicationSchedule() => ContinuousMedicationSchedule(
        start: schedule.start,
        end: today,
      ),
    },
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
    schedule: switch (schedule) {
      CyclicalMedicationSchedule() => CyclicalMedicationSchedule(
        startCycleDay: schedule.startCycleDay,
        durationDays: schedule.durationDays,
        effectiveStart: schedule.effectiveStart,
      ),
      FixedIntervalMedicationSchedule() => FixedIntervalMedicationSchedule(
        anchor: schedule.anchor,
        intervalDays: schedule.intervalDays,
        durationDays: schedule.durationDays,
      ),
      ContinuousMedicationSchedule() => ContinuousMedicationSchedule(
        start: schedule.start,
      ),
    },
    active: true,
    notes: medication.notes,
  );
}

String _medicationFacts(Medication medication, String? laneLabel) {
  final schedule = medication.schedule;
  final facts = [medication.dose];
  if (laneLabel != null) facts.add('calendar lane $laneLabel');
  if (schedule is CyclicalMedicationSchedule) {
    facts.add(
      'cycle day ${schedule.startCycleDay}, ${schedule.durationDays} days',
    );
    if (schedule.effectiveEnd != null) {
      facts.add('(stopped ${formatDate(schedule.effectiveEnd!)})');
    }
  } else if (schedule is FixedIntervalMedicationSchedule) {
    facts.add(
      '${schedule.durationDays} days every ${schedule.intervalDays} days from '
      '${formatDate(schedule.anchor)}',
    );
    if (schedule.effectiveEnd != null) {
      facts.add('(stopped ${formatDate(schedule.effectiveEnd!)})');
    }
  } else {
    final continuous = schedule as ContinuousMedicationSchedule;
    facts.add('continuous since ${formatDate(continuous.start)}');
    if (continuous.end != null) {
      facts.add('(stopped ${formatDate(continuous.end!)})');
    }
  }
  return facts.join(' · ');
}

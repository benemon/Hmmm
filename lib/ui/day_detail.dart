import 'package:flutter/material.dart';

import '../data/medication_repository.dart';
import '../data/period_repository.dart';
import '../data/symptom_repository.dart';
import '../domain/calendar.dart';
import '../domain/dates.dart';
import '../domain/hrt_window.dart';
import '../domain/models.dart';
import 'feedback.dart';
import 'format.dart';
import 'symptom_glyph.dart';
import 'theme.dart';

class DayDetailSheet extends StatefulWidget {
  const DayDetailSheet({
    super.key,
    required this.initialDate,
    required this.today,
    required this.periodRepository,
    required this.medicationRepository,
    required this.symptomRepository,
  });

  final DateTime initialDate;
  final DateTime today;
  final PeriodRepository periodRepository;
  final MedicationRepository medicationRepository;
  final SymptomRepository symptomRepository;

  @override
  State<DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends State<DayDetailSheet> {
  static const _initialPage = 10000;
  late final PageController _pageController = PageController(
    initialPage: _initialPage,
  );
  late final Listenable _repositories;

  @override
  void initState() {
    super.initState();
    _repositories = Listenable.merge([
      widget.periodRepository,
      widget.medicationRepository,
      widget.symptomRepository,
    ]);
  }

  Future<_DayDetailData> _loadData() async {
    final periods = await widget.periodRepository.listPeriods();
    final medications = await widget.medicationRepository.listMedications();
    final types = await widget.symptomRepository.listTypes();
    final entries = await widget.symptomRepository.listEntries();
    final windows = await widget.medicationRepository.loadAdjustedWindows(
      medications: medications,
      periods: periods,
      range: DateRange(start: DateTime(1, 1, 1), end: DateTime(9999, 12, 31)),
    );
    return _DayDetailData(
      periods: periods,
      medications: medications,
      types: types,
      entries: entries,
      adjustments: windows.adjustments,
      windowsByMedicationId: windows.windowsByMedicationId,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.45,
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      builder: (context, scrollController) => CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: true,
            child: ListenableBuilder(
              listenable: _repositories,
              builder: (context, child) => FutureBuilder<_DayDetailData>(
                future: _loadData(),
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  if (data == null) return const SizedBox.shrink();
                  return PageView.builder(
                    controller: _pageController,
                    itemBuilder: (context, index) => _DayPage(
                      date: addCalendarDays(
                        widget.initialDate,
                        index - _initialPage,
                      ),
                      today: widget.today,
                      data: data,
                      periodRepository: widget.periodRepository,
                      medicationRepository: widget.medicationRepository,
                      symptomRepository: widget.symptomRepository,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayDetailData {
  const _DayDetailData({
    required this.periods,
    required this.medications,
    required this.types,
    required this.entries,
    required this.adjustments,
    required this.windowsByMedicationId,
  });

  final List<Period> periods;
  final List<Medication> medications;
  final List<SymptomType> types;
  final List<SymptomEntry> entries;
  final List<WindowAdjustment> adjustments;
  final Map<int, List<MedicationWindow>> windowsByMedicationId;
}

class _DayPage extends StatelessWidget {
  const _DayPage({
    required this.date,
    required this.today,
    required this.data,
    required this.periodRepository,
    required this.medicationRepository,
    required this.symptomRepository,
  });

  final DateTime date;
  final DateTime today;
  final _DayDetailData data;
  final PeriodRepository periodRepository;
  final MedicationRepository medicationRepository;
  final SymptomRepository symptomRepository;

  @override
  Widget build(BuildContext context) {
    final cycleDay = cycleDayForDate(date, data.periods);
    final openPeriod = data.periods
        .where((period) => period.end == null)
        .firstOrNull;
    final closedPeriod = data.periods.where((period) {
      final end = period.end;
      return end != null && !date.isBefore(period.start) && !date.isAfter(end);
    }).firstOrNull;
    final isInOpenPeriod =
        openPeriod != null &&
        !date.isBefore(openPeriod.start) &&
        !date.isAfter(today);
    final entriesByTypeId = {
      for (final entry in data.entries)
        if (entry.date == date) entry.typeId: entry,
    };
    final coveringMedications =
        <
          ({
            Medication medication,
            DateTime? sourcePeriodStart,
            WindowAdjustment? adjustment,
          })
        >[];
    for (final medication in data.medications) {
      final originalWindows = deriveWindows(
        medication,
        data.periods,
        DateRange(start: date, end: date),
      );
      for (final original in originalWindows) {
        final sourcePeriodStart = original.sourcePeriodStart;
        final adjustment = sourcePeriodStart == null
            ? null
            : data.adjustments
                  .where(
                    (candidate) =>
                        candidate.medicationId == medication.id &&
                        candidate.sourcePeriodStart == sourcePeriodStart,
                  )
                  .firstOrNull;
        final adjustedCoversDate =
            data.windowsByMedicationId[medication.id]?.any(
              (window) =>
                  window.sourcePeriodStart == sourcePeriodStart &&
                  !date.isBefore(window.start) &&
                  !date.isAfter(window.end),
            ) ??
            false;
        if (adjustedCoversDate ||
            adjustment?.kind == WindowAdjustmentKind.skipped) {
          coveringMedications.add((
            medication: medication,
            sourcePeriodStart: sourcePeriodStart,
            adjustment: adjustment,
          ));
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatFullDate(date),
            key: ValueKey('day-detail-${dateToIso(date)}'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (cycleDay != null) ...[
            const SizedBox(height: 2),
            Text('cycle day $cycleDay', style: tabularFigures),
          ],
          const SizedBox(height: 20),
          Text(
            closedPeriod != null
                ? 'Period recorded · ${formatDate(closedPeriod.start)} – '
                      '${formatDate(closedPeriod.end!)}'
                : isInOpenPeriod
                ? 'Period ongoing · started ${formatDate(openPeriod.start)}'
                : 'No period recorded',
          ),
          if (closedPeriod != null || isInOpenPeriod)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('period-delete-${dateToIso(date)}'),
                onPressed: () =>
                    _deletePeriod(context, closedPeriod ?? openPeriod!),
                child: const Text('Delete record'),
              ),
            ),
          if (closedPeriod == null &&
              openPeriod == null &&
              !date.isAfter(today)) ...[
            const SizedBox(height: 10),
            FilledButton(
              key: ValueKey('period-start-${dateToIso(date)}'),
              onPressed: () => _startPeriod(context),
              child: const Text('Period started'),
            ),
          ] else if (openPeriod != null && isInOpenPeriod) ...[
            const SizedBox(height: 10),
            FilledButton(
              key: ValueKey('period-end-${dateToIso(date)}'),
              onPressed: () => _endPeriod(context, openPeriod),
              child: const Text('Period ended'),
            ),
          ],
          if (coveringMedications.isNotEmpty) ...[
            const SizedBox(height: 22),
            for (final course in coveringMedications)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  '${course.medication.name}  ${course.medication.dose}'
                  '${_adjustmentLabel(course.adjustment)}',
                ),
                trailing: course.sourcePeriodStart == null
                    ? null
                    : PopupMenuButton<_CourseAction>(
                        key: ValueKey(
                          'course-actions-${course.medication.id}-'
                          '${dateToIso(course.sourcePeriodStart!)}',
                        ),
                        tooltip: 'Course adjustment',
                        onSelected: (action) => _adjustCourse(
                          course.medication.id!,
                          course.sourcePeriodStart!,
                          action,
                        ),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: _CourseAction.endedEarly,
                            child: Text('Course ended on ${formatDate(date)}'),
                          ),
                          const PopupMenuItem(
                            value: _CourseAction.skipped,
                            child: Text('Course skipped'),
                          ),
                          if (course.adjustment != null)
                            const PopupMenuItem(
                              value: _CourseAction.restore,
                              child: Text('Restore full course'),
                            ),
                        ],
                      ),
              ),
          ],
          const SizedBox(height: 22),
          Text('Symptoms', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in data.types)
                _SymptomChip(
                  key: ValueKey('symptom-chip-${dateToIso(date)}-${type.id}'),
                  type: type,
                  entry: entriesByTypeId[type.id],
                  enabled: !date.isAfter(today),
                  onTap: () =>
                      _cycleSymptom(context, type, entriesByTypeId[type.id]),
                  onLongPress: () =>
                      _editNote(context, type, entriesByTypeId[type.id]),
                ),
              ActionChip(
                key: const ValueKey('add-symptom-type'),
                label: const Text('+ symptom type'),
                onPressed: () => _addSymptomType(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deletePeriod(BuildContext context, Period period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete period record?'),
        content: Text(
          '${formatDate(period.start)} – '
          '${period.end == null ? 'ongoing' : formatDate(period.end!)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-period'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await periodRepository.delete(period.id!);
  }

  Future<void> _adjustCourse(
    int medicationId,
    DateTime sourcePeriodStart,
    _CourseAction action,
  ) async {
    if (action == _CourseAction.restore) {
      await medicationRepository.clearAdjustment(
        medicationId,
        sourcePeriodStart,
      );
      return;
    }
    await medicationRepository.setAdjustment(
      WindowAdjustment(
        medicationId: medicationId,
        sourcePeriodStart: sourcePeriodStart,
        kind: action == _CourseAction.endedEarly
            ? WindowAdjustmentKind.endedEarly
            : WindowAdjustmentKind.skipped,
        endDate: action == _CourseAction.endedEarly ? date : null,
      ),
    );
  }

  Future<void> _startPeriod(BuildContext context) async {
    try {
      await periodRepository.insert(Period(start: date), today: today);
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }

  Future<void> _endPeriod(BuildContext context, Period period) async {
    try {
      await periodRepository.update(
        Period(id: period.id, start: period.start, end: date),
        today: today,
      );
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }

  Future<void> _cycleSymptom(
    BuildContext context,
    SymptomType type,
    SymptomEntry? entry,
  ) async {
    try {
      await symptomRepository.upsertEntry(
        SymptomEntry(
          date: date,
          typeId: type.id!,
          severity: nextSymptomSeverity(entry?.severity ?? 0),
          note: entry?.note,
        ),
        today: today,
      );
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }

  Future<void> _editNote(
    BuildContext context,
    SymptomType type,
    SymptomEntry? entry,
  ) async {
    if (date.isAfter(today)) return;
    final controller = TextEditingController(text: entry?.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !context.mounted) return;
    try {
      await symptomRepository.upsertEntry(
        SymptomEntry(
          date: date,
          typeId: type.id!,
          severity: entry?.severity ?? 1,
          note: note.isEmpty ? null : note,
        ),
        today: today,
      );
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }

  Future<void> _addSymptomType(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Symptom type'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !context.mounted) return;
    try {
      await symptomRepository.insertType(
        SymptomType(name: name, builtin: false),
      );
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }
}

enum _CourseAction { endedEarly, skipped, restore }

String _adjustmentLabel(WindowAdjustment? adjustment) {
  if (adjustment == null) return '';
  return adjustment.kind == WindowAdjustmentKind.skipped
      ? ' · skipped'
      : ' · ended ${formatDate(adjustment.endDate!)}';
}

class _SymptomChip extends StatelessWidget {
  const _SymptomChip({
    super.key,
    required this.type,
    required this.entry,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
  });

  final SymptomType type;
  final SymptomEntry? entry;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final severity = entry?.severity ?? 0;
    return Material(
      color: scheme.surface,
      shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SymptomGlyphMark(typeId: type.id!, size: 13),
              const SizedBox(width: 6),
              Text(type.name),
              const SizedBox(width: 8),
              for (var segment = 1; segment <= 3; segment++) ...[
                Container(
                  width: 8,
                  height: 3,
                  color: segment <= severity
                      ? scheme.onSurface
                      : scheme.outlineVariant,
                ),
                if (segment < 3) const SizedBox(width: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatFullDate(DateTime date) =>
    '${_weekdays[date.weekday - 1]} ${date.day} '
    '${monthsFull[date.month - 1]} ${date.year}';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

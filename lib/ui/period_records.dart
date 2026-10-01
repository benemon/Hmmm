import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/period_repository.dart';
import '../domain/calendar.dart';
import '../domain/cycle_lengths.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/periods.dart';
import '../domain/validation.dart';
import 'empty_state.dart';
import 'feedback.dart';
import 'format.dart';
import 'theme.dart';

class PeriodRecordsScreen extends StatelessWidget {
  const PeriodRecordsScreen({
    super.key,
    required this.repository,
    required this.today,
  });

  final PeriodRepository repository;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, child) => FutureBuilder<List<Period>>(
        future: repository.listPeriods(),
        builder: (context, snapshot) {
          final periods = snapshot.data;
          return Scaffold(
            appBar: AppBar(title: const Text('Period records')),
            body: periods == null
                ? const SizedBox.shrink()
                : _PeriodList(
                    periods: periods,
                    repository: repository,
                    today: today,
                    onEdit: (period) => _editPeriod(context, period),
                  ),
            floatingActionButton: FloatingActionButton.extended(
              key: const ValueKey('add-period'),
              tooltip: 'Add period',
              onPressed: () => _editPeriod(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Add record'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Dim.radiusControl),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _editPeriod(BuildContext context, Period? period) async {
    await showPeriodRecordEditor(
      context,
      repository: repository,
      today: today,
      period: period,
    );
  }
}

Future<void> showPeriodRecordEditor(
  BuildContext context, {
  required PeriodRepository repository,
  required DateTime today,
  Period? period,
}) async {
  final draft = await showDialog<_PeriodDraft>(
    context: context,
    builder: (context) => _PeriodDialog(period: period, today: today),
  );
  if (draft == null || !context.mounted) return;
  try {
    if (period == null) {
      await insertPeriodWithEndPrompts(
        context,
        repository: repository,
        today: today,
        start: draft.start,
        end: draft.end,
      );
    } else {
      await repository.update(
        Period(id: period.id, start: draft.start, end: draft.end),
        today: today,
      );
    }
  } on ArgumentError catch (error) {
    if (context.mounted) showValidationError(context, error);
  }
}

Future<void> insertPeriodWithEndPrompts(
  BuildContext context, {
  required PeriodRepository repository,
  required DateTime today,
  required DateTime start,
  DateTime? end,
}) async {
  final existing = await repository.listPeriods();
  validatePeriod(
    Period(start: start, end: end),
    existing,
    today: today,
  );
  if (!context.mounted) return;

  if (end == null) {
    final ongoing = derivePeriods(existing)
        .where((period) => period.isOngoing)
        .firstOrNull;
    if (ongoing != null && start.isAfter(ongoing.period.start)) {
      final lastDate = addCalendarDays(start, -1);
      final resolution = await _askForEndDate(
        context,
        title:
            'End date for the period starting '
            '${formatDate(ongoing.period.start)}?',
        start: ongoing.period.start,
        initialDate: lastDate,
        lastDate: lastDate,
      );
      if (resolution == null || !context.mounted) return;
      if (resolution.end != null) {
        await repository.update(
          Period(
            id: ongoing.period.id,
            start: ongoing.period.start,
            end: resolution.end,
          ),
          today: today,
        );
      }
    } else if (existing.any((period) => period.start.isAfter(start))) {
      final resolution = await _askForEndDate(
        context,
        title: 'End date?',
        start: start,
        initialDate: start,
        lastDate: dateOnly(today),
      );
      if (resolution == null || !context.mounted) return;
      end = resolution.end;
    }
  }

  await repository.insert(
    Period(start: start, end: end),
    today: today,
  );
}

Future<({DateTime? end})?> _askForEndDate(
  BuildContext context, {
  required String title,
  required DateTime start,
  required DateTime initialDate,
  required DateTime lastDate,
}) async {
  final action = await showDialog<_EndPromptAction>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(formatDate(start), style: HmmmType.of(context).figure),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _EndPromptAction.recordAsOneDay),
          child: const Text('Record as 1 day'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _EndPromptAction.chooseEnd),
          child: const Text('Choose end'),
        ),
      ],
    ),
  );
  if (action == null) return null;
  if (action == _EndPromptAction.recordAsOneDay) return (end: null);
  if (!context.mounted) return null;
  final selected = await pickDate(
    context,
    initialDate,
    lastDate,
    firstDate: start,
  );
  return selected == null ? null : (end: selected);
}

enum _EndPromptAction { chooseEnd, recordAsOneDay }

class _PeriodList extends StatelessWidget {
  const _PeriodList({
    required this.periods,
    required this.repository,
    required this.today,
    required this.onEdit,
  });

  final List<Period> periods;
  final PeriodRepository repository;
  final DateTime today;
  final ValueChanged<Period> onEdit;

  @override
  Widget build(BuildContext context) {
    if (periods.isEmpty) {
      return const RecordEmptyState(
        count: '0 periods recorded',
        action: 'Record a period start from any day in the calendar.',
      );
    }
    final derivedPeriods = derivePeriods(periods);
    final cycleLengths = cycleLengthsToNext(periods);
    final newestFirst = [
      for (var index = derivedPeriods.length - 1; index >= 0; index--)
        (period: derivedPeriods[index], cycleLength: cycleLengths[index]),
    ];

    return ListView.separated(
      itemCount: newestFirst.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final record = newestFirst[index];
        final derived = record.period;
        final period = derived.period;
        final duration = recordedPeriodLength(derived, today);
        final rangeEnd = derived.isOngoing ? null : derived.displayEnd(today);
        return Dismissible(
          key: ValueKey('period-${period.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDelete(context, period),
          onDismissed: (_) => repository.delete(period.id!),
          background: Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 96,
              color: Markers.of(context).period,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.delete_outline,
                    color: Markers.of(context).inkOnBand,
                  ),
                  const SizedBox(width: Dim.s2),
                  Text(
                    'Delete',
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: Markers.of(context).inkOnBand),
                  ),
                ],
              ),
            ),
          ),
          child: Semantics(
            customSemanticsActions: {
              const CustomSemanticsAction(label: 'Delete'): () async {
                if (await _confirmDelete(context, period) && context.mounted) {
                  await repository.delete(period.id!);
                }
              },
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Dim.rowMinHeight),
              child: ListTile(
                title: Text(
                  formatPeriodRange(period.start, rangeEnd),
                  style: HmmmType.of(context).figure,
                ),
                subtitle: Text(
                  derived.isEndNotRecorded
                      ? '1 day · end not recorded'
                            '${record.cycleLength == null ? '' : ' · ${record.cycleLength}-day cycle'}'
                      : derived.isOngoing
                      ? '$duration days so far'
                      : '$duration days'
                            '${record.cycleLength == null ? '' : ' · ${record.cycleLength}-day cycle'}',
                  style: HmmmType.of(context).figureSmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => onEdit(period),
                onLongPress: () async {
                  if (await _confirmDelete(context, period) &&
                      context.mounted) {
                    await repository.delete(period.id!);
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context, Period period) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete period?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatPeriodRange(period.start, period.end),
                style: HmmmType.of(context).figure,
              ),
              const SizedBox(height: Dim.s1),
              const Text(
                'Derived medication windows from this start are removed too.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

class _PeriodDraft {
  const _PeriodDraft(this.start, this.end);

  final DateTime start;
  final DateTime? end;
}

class _PeriodDialog extends StatefulWidget {
  const _PeriodDialog({required this.period, required this.today});

  final Period? period;
  final DateTime today;

  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  late DateTime _start = widget.period?.start ?? widget.today;
  late DateTime? _end = widget.period?.end;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.period == null ? 'Add period' : 'Edit period'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start'),
            trailing: Text(
              formatDate(_start),
              style: HmmmType.of(context).figure,
            ),
            onTap: _pickStart,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('End'),
            trailing: Text(
              _end == null ? 'open' : formatDate(_end!),
              style: HmmmType.of(context).figure,
            ),
            onTap: _pickEnd,
          ),
          if (_end != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _end = null),
                child: const Text('Set open'),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('apply-period'),
          onPressed: () => Navigator.pop(context, _PeriodDraft(_start, _end)),
          child: Text(widget.period == null ? 'Add' : 'Apply'),
        ),
      ],
    );
  }

  Future<void> _pickStart() async {
    final selected = await pickDate(context, _start, widget.today);
    if (selected != null) setState(() => _start = selected);
  }

  Future<void> _pickEnd() async {
    final selected = await pickDate(context, _end ?? _start, widget.today);
    if (selected != null) setState(() => _end = selected);
  }
}

import 'package:flutter/material.dart';

import '../data/period_repository.dart';
import '../domain/cycle_lengths.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
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
            floatingActionButton: FloatingActionButton(
              key: const ValueKey('add-period'),
              tooltip: 'Add period',
              onPressed: () => _editPeriod(context, null),
              child: const Icon(Icons.add),
            ),
          );
        },
      ),
    );
  }

  Future<void> _editPeriod(BuildContext context, Period? period) async {
    final draft = await showDialog<_PeriodDraft>(
      context: context,
      builder: (context) => _PeriodDialog(period: period, today: today),
    );
    if (draft == null || !context.mounted) return;
    try {
      if (period == null) {
        await repository.insert(
          Period(start: draft.start, end: draft.end),
          today: today,
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
}

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
    if (periods.isEmpty) return const SizedBox.shrink();
    final cycleLengths = cycleLengthsToNext(periods);
    final newestFirst = [
      for (var index = periods.length - 1; index >= 0; index--)
        (period: periods[index], cycleLength: cycleLengths[index]),
    ];

    return ListView.separated(
      itemCount: newestFirst.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final record = newestFirst[index];
        final period = record.period;
        final duration =
            calendarDaysBetween(period.start, period.end ?? today) + 1;
        return Dismissible(
          key: ValueKey('period-${period.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDelete(context),
          onDismissed: (_) => repository.delete(period.id!),
          child: ListTile(
            title: Text(
              '${formatDate(period.start)} – '
              '${period.end == null ? 'ongoing' : formatDate(period.end!)}',
            ),
            subtitle: Text(
              '$duration days'
              '${record.cycleLength == null ? '' : ' · ${record.cycleLength}-day cycle'}',
              style: tabularFigures,
            ),
            onTap: () => onEdit(period),
            onLongPress: () async {
              if (await _confirmDelete(context) && context.mounted) {
                await repository.delete(period.id!);
              }
            },
          ),
        );
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete period?'),
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
            trailing: Text(formatDate(_start), style: tabularFigures),
            onTap: _pickStart,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('End'),
            trailing: Text(
              _end == null ? 'ongoing' : formatDate(_end!),
              style: tabularFigures,
            ),
            onTap: _pickEnd,
          ),
          if (_end != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _end = null),
                child: const Text('Set ongoing'),
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
    final selected = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(1900),
      lastDate: widget.today,
    );
    if (selected != null) setState(() => _start = selected);
  }

  Future<void> _pickEnd() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _end ?? _start,
      firstDate: DateTime(1900),
      lastDate: widget.today,
    );
    if (selected != null) setState(() => _end = selected);
  }
}

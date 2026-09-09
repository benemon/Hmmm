import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/period_repository.dart';
import '../data/symptom_repository.dart';
import '../domain/calendar.dart';
import '../domain/cycle_lengths.dart';
import '../domain/models.dart';
import '../domain/trends.dart';
import 'empty_state.dart';
import 'format.dart';
import 'period_records.dart';
import 'symptom_glyph.dart';
import 'theme.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({
    super.key,
    required this.periodRepository,
    required this.symptomRepository,
    required this.today,
  });

  final PeriodRepository periodRepository;
  final SymptomRepository symptomRepository;
  final DateTime today;

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  late final Listenable _repositories;

  @override
  void initState() {
    super.initState();
    _repositories = Listenable.merge([
      widget.periodRepository,
      widget.symptomRepository,
    ]);
  }

  Future<_TrendsData> _loadData() async => _TrendsData(
    periods: await widget.periodRepository.listPeriods(),
    types: await widget.symptomRepository.listTypes(),
    entries: await widget.symptomRepository.listEntries(),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repositories,
      builder: (context, child) => FutureBuilder<_TrendsData>(
        future: _loadData(),
        builder: (context, snapshot) => Scaffold(
          appBar: AppBar(title: const Text('Trends')),
          body: snapshot.data == null
              ? const SizedBox.shrink()
              : _TrendsBody(
                  data: snapshot.data!,
                  today: widget.today,
                  periodRepository: widget.periodRepository,
                ),
        ),
      ),
    );
  }
}

class _TrendsData {
  const _TrendsData({
    required this.periods,
    required this.types,
    required this.entries,
  });

  final List<Period> periods;
  final List<SymptomType> types;
  final List<SymptomEntry> entries;
}

class _TrendsBody extends StatelessWidget {
  const _TrendsBody({
    required this.data,
    required this.today,
    required this.periodRepository,
  });

  final _TrendsData data;
  final DateTime today;
  final PeriodRepository periodRepository;

  @override
  Widget build(BuildContext context) {
    final cycleDayRows = symptomCountsByCycleDay(data.entries, data.periods);
    final monthly = symptomCountsByMonth(data.entries, today);
    final typesById = {for (final type in data.types) type.id!: type};
    final observationMonths = symptomObservationMonthSpan(data.entries);
    final cycleLengths = cycleLengthsToNext(data.periods);
    final completeIntervals = cycleLengths.whereType<int>().length;
    final monthlyTotal = monthly.countsByTypeId.values.fold<int>(
      0,
      (total, row) => total + row.fold<int>(0, (sum, count) => sum + count),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(Dim.s4, Dim.s3, Dim.s4, Dim.s7),
      children: [
        _SectionHeading(
          title: 'Cycles',
          basis:
              '${data.periods.length} recorded · '
              '$completeIntervals complete intervals',
        ),
        const SizedBox(height: Dim.s2),
        if (data.periods.isEmpty)
          const RecordEmptyState(
            count: '0 periods recorded',
            action: 'Record a period start from any day in the calendar.',
          )
        else ...[
          _CyclesTable(
            periods: data.periods,
            lengths: cycleLengths,
            today: today,
            onTap: (period) => showPeriodRecordEditor(
              context,
              repository: periodRepository,
              today: today,
              period: period,
            ),
          ),
          const SizedBox(height: Dim.s3),
          _CycleSummaryTable(
            summaries: cycleLengthSummaries(data.periods, today),
          ),
        ],
        const SizedBox(height: Dim.s7),
        _SectionHeading(
          title: 'Symptoms by cycle day',
          basis:
              '${data.entries.length} entries over '
              '$observationMonths '
              '${observationMonths == 1 ? 'month' : 'months'} · '
              '${cycleDayRows.length} of ${data.types.length} types',
        ),
        const SizedBox(height: Dim.s2),
        if (data.entries.isEmpty)
          const RecordEmptyState(
            count: '0 symptoms recorded',
            action: 'Record a symptom from any day in the calendar.',
          )
        else
          _SymptomMatrix(
            key: const ValueKey('cycle-day-matrix'),
            label: 'Symptoms by cycle day',
            columns: [
              for (var day = 1; day <= 35; day++)
                _MatrixColumn(
                  visualLabel: '$day',
                  semanticLabel: 'cycle day $day',
                  width: 26,
                ),
              const _MatrixColumn(
                visualLabel: 'no cycle',
                semanticLabel: 'no cycle',
                width: 64,
              ),
            ],
            rows: cycleDayRows,
            rowKeyPrefix: 'trend-symptom',
            typesById: typesById,
            totalFor: (row) => row.totalCount,
            valuesFor: (row) => [
              for (var day = 1; day <= 35; day++)
                row.countsByCycleDay[day] ?? 0,
              row.noCycleCount,
            ],
            cellKey: (row, column) => column == 35
                ? ValueKey('cycle-day-no-cycle-${row.typeId}')
                : ValueKey('cycle-day-count-${row.typeId}-${column + 1}'),
            onRowTap: (row) =>
                _openEntries(context, typesById[row.typeId]!, row.typeId),
          ),
        const SizedBox(height: Dim.s7),
        _SectionHeading(
          title: 'Monthly counts',
          basis:
              '$monthlyTotal entries over 12 months to '
              '${formatMonthYear(today)}',
        ),
        const SizedBox(height: Dim.s2),
        if (data.entries.isEmpty)
          const RecordEmptyState(
            count: '0 symptoms recorded',
            action: 'Record a symptom from any day in the calendar.',
          )
        else
          _SymptomMatrix(
            label: 'Monthly symptom counts',
            columns: [
              for (final month in monthly.months)
                _MatrixColumn(
                  visualLabel: _formatMonth(month),
                  semanticLabel: formatMonthYear(month),
                  width: 40,
                ),
            ],
            rows: cycleDayRows,
            rowKeyPrefix: 'monthly-symptom',
            typesById: typesById,
            totalFor: (row) =>
                (monthly.countsByTypeId[row.typeId] ?? const <int>[]).fold(
                  0,
                  (sum, count) => sum + count,
                ),
            valuesFor: (row) =>
                monthly.countsByTypeId[row.typeId] ?? List.filled(12, 0),
            cellKey: (row, column) =>
                ValueKey('monthly-count-${row.typeId}-$column'),
            onRowTap: (row) =>
                _openEntries(context, typesById[row.typeId]!, row.typeId),
          ),
      ],
    );
  }

  void _openEntries(BuildContext context, SymptomType type, int typeId) {
    final entries =
        data.entries.where((entry) => entry.typeId == typeId).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _SymptomEntriesScreen(
          type: type,
          entries: entries,
          periods: data.periods,
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.basis});

  final String title;
  final String basis;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Dim.s1),
          Text(
            basis,
            style: HmmmType.of(context).figureSmall
                .copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CyclesTable extends StatelessWidget {
  const _CyclesTable({
    required this.periods,
    required this.lengths,
    required this.today,
    required this.onTap,
  });

  final List<Period> periods;
  final List<int?> lengths;
  final DateTime today;
  final ValueChanged<Period> onTap;

  @override
  Widget build(BuildContext context) {
    final records = periods.indexed.toList().reversed.map((record) {
      final (index, period) = record;
      final days = recordedPeriodLength(period, today);
      return (
        start: formatDate(period.start),
        days: days,
        daysSemantic: '$days days',
        daysVisual: '$days',
        cycle: _cycleValue(period, lengths[index]),
        period: period,
      );
    }).toList();
    return _TableSemantics(
      label: 'Cycles',
      headers: const ['start', 'days', 'cycle'],
      rows: [
        for (final record in records)
          (
            [record.start, record.daysSemantic, record.cycle],
            'Period starting ${record.start}',
          ),
      ],
      onRowTaps: [for (final record in records) () => onTap(record.period)],
      child: Column(
        children: [
          const _CycleRow(start: 'start', days: 'days', cycle: 'cycle'),
          for (final record in records)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: InkWell(
                key: ValueKey('trend-period-${record.period.id}'),
                onTap: () => onTap(record.period),
                child: _CycleRow(
                  start: record.start,
                  days: record.daysVisual,
                  cycle: record.cycle,
                  showChevron: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CycleRow extends StatelessWidget {
  const _CycleRow({
    required this.start,
    required this.days,
    required this.cycle,
    this.showChevron = false,
  });

  final String start;
  final String days;
  final String cycle;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final style = showChevron
        ? HmmmType.of(context).figure
        : Theme.of(context).textTheme.labelSmall;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Dim.tableRowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Dim.s2),
        child: Row(
          children: [
            Expanded(child: Text(start, style: style)),
            SizedBox(
              width: 56,
              child: Text(days, textAlign: TextAlign.right, style: style),
            ),
            SizedBox(
              width: 64,
              child: Text(cycle, textAlign: TextAlign.right, style: style),
            ),
            SizedBox(
              width: 20,
              child: showChevron
                  ? Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CycleSummaryTable extends StatelessWidget {
  const _CycleSummaryTable({required this.summaries});

  final List<CycleLengthSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return _TableSemantics(
      label: 'Cycle length summary',
      headers: const ['window', 'n', 'minimum', 'maximum', 'mean'],
      rows: [
        for (final summary in summaries)
          summary.hasSufficientData
              ? (
                  [
                    '${summary.months} month window',
                    'n ${summary.sampleCount}',
                    'minimum ${summary.minimum}',
                    'maximum ${summary.maximum}',
                    'mean ${_formatMean(summary.mean!)}',
                  ],
                  '${summary.months} month window',
                )
              : (
                  [
                    '${summary.months} month window',
                    'insufficient data (n=0, 2 starts needed)',
                  ],
                  '${summary.months} month window',
                ),
      ],
      child: Column(
        children: [
          const _SummaryRow(
            window: 'window',
            n: 'n',
            minimum: 'min',
            maximum: 'max',
            mean: 'mean',
            header: true,
          ),
          for (final summary in summaries)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: summary.hasSufficientData
                  ? _SummaryRow(
                      window: '${summary.months} mo',
                      n: '${summary.sampleCount}',
                      minimum: '${summary.minimum}',
                      maximum: '${summary.maximum}',
                      mean: _formatMean(summary.mean!),
                    )
                  : _InsufficientSummaryRow(months: summary.months),
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.window,
    required this.n,
    required this.minimum,
    required this.maximum,
    required this.mean,
    this.header = false,
  });

  final String window;
  final String n;
  final String minimum;
  final String maximum;
  final String mean;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final style = header
        ? Theme.of(context).textTheme.labelSmall
        : HmmmType.of(context).figureSmall;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          Expanded(child: Text(window, style: style)),
          SizedBox(
            width: 34,
            child: Text(n, textAlign: TextAlign.right, style: style),
          ),
          SizedBox(
            width: 46,
            child: Text(minimum, textAlign: TextAlign.right, style: style),
          ),
          SizedBox(
            width: 46,
            child: Text(maximum, textAlign: TextAlign.right, style: style),
          ),
          SizedBox(
            width: 52,
            child: Text(mean, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}

class _InsufficientSummaryRow extends StatelessWidget {
  const _InsufficientSummaryRow({required this.months});

  final int months;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text('$months mo', style: HmmmType.of(context).figureSmall),
          ),
          Expanded(
            child: Text(
              'insufficient data (n=0, 2 starts needed)',
              textAlign: TextAlign.right,
              style: HmmmType.of(context).figureSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatrixColumn {
  const _MatrixColumn({
    required this.visualLabel,
    required this.semanticLabel,
    required this.width,
  });

  final String visualLabel;
  final String semanticLabel;
  final double width;
}

class _SymptomMatrix extends StatelessWidget {
  const _SymptomMatrix({
    super.key,
    required this.label,
    required this.columns,
    required this.rows,
    required this.rowKeyPrefix,
    required this.typesById,
    required this.totalFor,
    required this.valuesFor,
    required this.cellKey,
    required this.onRowTap,
  });

  final String label;
  final List<_MatrixColumn> columns;
  final List<SymptomCycleDayCounts> rows;
  final String rowKeyPrefix;
  final Map<int, SymptomType> typesById;
  final int Function(SymptomCycleDayCounts row) totalFor;
  final List<int> Function(SymptomCycleDayCounts row) valuesFor;
  final Key Function(SymptomCycleDayCounts row, int column) cellKey;
  final ValueChanged<SymptomCycleDayCounts> onRowTap;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final stickyWidth = 150 * scale;
    final totalWidth = 38 * scale;
    final rowHeight = math.max(Dim.tableRowMinHeight, 44 * scale);
    final scrollWidth =
        totalWidth +
        columns.fold<double>(
          0,
          (width, column) => width + column.width * scale,
        );
    final semanticRows = [
      for (final row in rows)
        (
          [
            typesById[row.typeId]!.name,
            '${totalFor(row)} entries',
            for (final value in valuesFor(row))
              '$value ${value == 1 ? 'entry' : 'entries'}',
          ],
          typesById[row.typeId]!.name,
        ),
    ];

    return _TableSemantics(
      label: label,
      headers: [
        'symptom',
        'all',
        for (final column in columns) column.semanticLabel,
      ],
      rows: semanticRows,
      onRowTaps: [for (final row in rows) () => onRowTap(row)],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: stickyWidth,
            child: Column(
              children: [
                _MatrixNameCell(
                  height: rowHeight,
                  name: 'symptom',
                  header: true,
                ),
                for (final row in rows)
                  _MatrixNameCell(
                    key: ValueKey('$rowKeyPrefix-${row.typeId}'),
                    height: rowHeight,
                    typeId: row.typeId,
                    name: typesById[row.typeId]!.name,
                    onTap: () => onRowTap(row),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: scrollWidth,
                child: Column(
                  children: [
                    _MatrixNumberRow(
                      height: rowHeight,
                      totalWidth: totalWidth,
                      columns: columns,
                      scale: scale,
                    ),
                    for (final row in rows)
                      _MatrixNumberRow(
                        height: rowHeight,
                        totalWidth: totalWidth,
                        columns: columns,
                        scale: scale,
                        total: totalFor(row),
                        values: valuesFor(row),
                        keys: [
                          for (
                            var column = 0;
                            column < columns.length;
                            column++
                          )
                            cellKey(row, column),
                        ],
                        onTap: () => onRowTap(row),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatrixNameCell extends StatelessWidget {
  const _MatrixNameCell({
    super.key,
    required this.height,
    required this.name,
    this.typeId,
    this.header = false,
    this.onTap,
  });

  final double height;
  final String name;
  final int? typeId;
  final bool header;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cell = Container(
      constraints: BoxConstraints(minHeight: height),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      padding: const EdgeInsets.only(right: Dim.s2),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (typeId != null) ...[
            SymptomGlyphMark(typeId: typeId!, size: Dim.glyphSizeTable),
            const SizedBox(width: Dim.s2),
          ],
          Expanded(
            child: Text(
              name,
              style: header
                  ? Theme.of(context).textTheme.labelSmall
                  : Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
    return onTap == null ? cell : InkWell(onTap: onTap, child: cell);
  }
}

class _MatrixNumberRow extends StatelessWidget {
  const _MatrixNumberRow({
    required this.height,
    required this.totalWidth,
    required this.columns,
    required this.scale,
    this.total,
    this.values,
    this.keys,
    this.onTap,
  });

  final double height;
  final double totalWidth;
  final List<_MatrixColumn> columns;
  final double scale;
  final int? total;
  final List<int>? values;
  final List<Key>? keys;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final header = values == null;
    final row = Container(
      constraints: BoxConstraints(minHeight: height),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          _MatrixNumberCell(
            width: totalWidth,
            value: header ? 'all' : '$total',
            header: header,
            strong: !header,
          ),
          for (var index = 0; index < columns.length; index++)
            _MatrixNumberCell(
              key: keys?[index],
              width: columns[index].width * scale,
              value: header
                  ? columns[index].visualLabel
                  : values![index] == 0
                  ? '·'
                  : '${values![index]}',
              header: header,
              muted: !header && values![index] == 0,
            ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

class _MatrixNumberCell extends StatelessWidget {
  const _MatrixNumberCell({
    super.key,
    required this.width,
    required this.value,
    this.header = false,
    this.strong = false,
    this.muted = false,
  });

  final double width;
  final String value;
  final bool header;
  final bool strong;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    TextStyle style = header
        ? Theme.of(context).textTheme.labelSmall!
        : HmmmType.of(context).figureSmall;
    if (strong) style = style.copyWith(fontWeight: FontWeight.w500);
    if (muted) style = style.copyWith(color: colors.onSurfaceVariant);
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(value, textAlign: TextAlign.right, style: style),
      ),
    );
  }
}

class _SymptomEntriesScreen extends StatelessWidget {
  const _SymptomEntriesScreen({
    required this.type,
    required this.entries,
    required this.periods,
  });

  final SymptomType type;
  final List<SymptomEntry> entries;
  final List<Period> periods;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(type.name),
            Text(
              '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      body: ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final cycleDay = cycleDayForDate(entry.date, periods);
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Dim.rowMinHeight),
            child: ListTile(
              title: Text(
                '${formatDate(entry.date)} · ${entry.severity}/3 · '
                '${cycleDay == null ? 'no cycle' : 'cycle day $cycleDay'}',
                style: HmmmType.of(context).figure,
              ),
              subtitle: entry.note == null
                  ? null
                  : Text(
                      entry.note!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _TableSemantics extends StatelessWidget {
  const _TableSemantics({
    required this.label,
    required this.headers,
    required this.rows,
    required this.child,
    this.onRowTaps,
  });

  final String label;
  final List<String> headers;
  final List<(List<String>, String)> rows;
  final List<VoidCallback>? onRowTaps;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.table,
      label: label,
      child: Stack(
        children: [
          ExcludeSemantics(child: child),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              alwaysIncludeSemantics: true,
              child: Column(
                children: [
                  Expanded(
                    child: _SemanticTableRow(values: headers, header: true),
                  ),
                  for (var index = 0; index < rows.length; index++)
                    Expanded(
                      child: _SemanticTableRow(
                        values: rows[index].$1,
                        label: rows[index].$2,
                        onTap: onRowTaps?[index],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SemanticTableRow extends StatelessWidget {
  const _SemanticTableRow({
    required this.values,
    this.label,
    this.header = false,
    this.onTap,
  });

  final List<String> values;
  final String? label;
  final bool header;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.row,
      label: label,
      button: onTap != null,
      onTap: onTap,
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: Semantics(
                container: true,
                role: header ? SemanticsRole.columnHeader : SemanticsRole.cell,
                label: value,
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}

String _cycleValue(Period period, int? length) {
  if (length != null) return '$length';
  return period.end == null ? 'open' : 'latest';
}

String _formatMean(double mean) => mean == mean.roundToDouble()
    ? mean.toInt().toString()
    : mean.toStringAsFixed(1);

String _formatMonth(DateTime date) =>
    '${date.month}/${(date.year % 100).toString().padLeft(2, '0')}';

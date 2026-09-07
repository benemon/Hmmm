import 'package:flutter/material.dart';

import '../data/period_repository.dart';
import '../data/symptom_repository.dart';
import '../domain/cycle_lengths.dart';
import '../domain/models.dart';
import 'format.dart';
import '../domain/trends.dart';
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
              : _TrendsBody(data: snapshot.data!, today: widget.today),
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
  const _TrendsBody({required this.data, required this.today});

  final _TrendsData data;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final cycleDayRows = symptomCountsByCycleDay(data.entries, data.periods);
    final monthly = symptomCountsByMonth(data.entries, today);
    final typesById = {for (final type in data.types) type.id!: type};
    final observationMonths = symptomObservationMonthSpan(data.entries);
    final monthlyTotal = monthly.countsByTypeId.values.fold<int>(
      0,
      (total, row) => total + row.fold<int>(0, (sum, count) => sum + count),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _SectionHeading(
          title: 'Cycles',
          basis: '${data.periods.length} recorded',
        ),
        const SizedBox(height: 8),
        if (data.periods.isEmpty)
          const Text('No periods recorded.')
        else ...[
          _CyclesTable(periods: data.periods),
          const SizedBox(height: 10),
          for (final summary in cycleLengthSummaries(data.periods, today))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_summaryText(summary), style: tabularFigures),
            ),
        ],
        const SizedBox(height: 28),
        _SectionHeading(
          title: 'Symptoms by cycle day',
          basis:
              '${data.entries.length} entries over '
              '$observationMonths ${observationMonths == 1 ? 'month' : 'months'}',
        ),
        const SizedBox(height: 8),
        if (data.entries.isEmpty)
          const Text('No symptoms recorded.')
        else
          _SymptomCycleDayTable(
            rows: cycleDayRows,
            typesById: typesById,
            entries: data.entries,
          ),
        const SizedBox(height: 28),
        _SectionHeading(
          title: 'Monthly counts',
          basis: '$monthlyTotal entries over 12 months',
        ),
        const SizedBox(height: 8),
        if (data.entries.isEmpty)
          const Text('No symptoms recorded.')
        else
          _MonthlyCountsTable(
            result: monthly,
            rows: cycleDayRows,
            typesById: typesById,
          ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.basis});

  final String title;
  final String basis;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            basis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _CyclesTable extends StatelessWidget {
  const _CyclesTable({required this.periods});

  final List<Period> periods;

  @override
  Widget build(BuildContext context) {
    final lengths = cycleLengthsToNext(periods);
    final records = [
      for (var index = periods.length - 1; index >= 0; index--)
        (period: periods[index], length: lengths[index]),
    ];
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(),
        1: FixedColumnWidth(72),
        2: FixedColumnWidth(72),
      },
      border: TableBorder(
        horizontalInside: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      children: [
        _tableRow(context, const ['Start', 'Length', 'State'], header: true),
        for (final record in records)
          _tableRow(context, [
            formatDate(record.period.start),
            record.length?.toString() ?? '',
            record.period.end == null ? 'ongoing' : '',
          ]),
      ],
    );
  }
}

class _SymptomCycleDayTable extends StatelessWidget {
  const _SymptomCycleDayTable({
    required this.rows,
    required this.typesById,
    required this.entries,
  });

  final List<SymptomCycleDayCounts> rows;
  final Map<int, SymptomType> typesById;
  final List<SymptomEntry> entries;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      children: [
        const _SymptomTableRow(
          name: 'Symptom',
          total: 'Total',
          distribution: 'Cycle day counts',
          header: true,
        ),
        for (final row in rows)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: InkWell(
              key: ValueKey('trend-symptom-${row.typeId}'),
              onTap: () {
                final type = typesById[row.typeId]!;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => _SymptomEntriesScreen(
                      type: type,
                      entries:
                          entries
                              .where((entry) => entry.typeId == row.typeId)
                              .toList()
                            ..sort((a, b) => b.date.compareTo(a.date)),
                    ),
                  ),
                );
              },
              child: _SymptomTableRow(
                typeId: row.typeId,
                name: typesById[row.typeId]!.name,
                total: row.totalCount.toString(),
                distribution: _distributionText(row),
              ),
            ),
          ),
      ],
    );
  }
}

class _SymptomTableRow extends StatelessWidget {
  const _SymptomTableRow({
    this.typeId,
    required this.name,
    required this.total,
    required this.distribution,
    this.header = false,
  });

  final int? typeId;
  final String name;
  final String total;
  final String distribution;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final style = header
        ? Theme.of(context).textTheme.labelMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: typeId == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SymptomGlyphMark(typeId: typeId!, size: 12),
                  ),
          ),
          SizedBox(width: 100, child: Text(name, style: style)),
          SizedBox(
            width: 44,
            child: Text(
              total,
              textAlign: TextAlign.right,
              style: style?.merge(tabularFigures),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(distribution, style: style?.merge(tabularFigures)),
          ),
        ],
      ),
    );
  }
}

class _MonthlyCountsTable extends StatelessWidget {
  const _MonthlyCountsTable({
    required this.result,
    required this.rows,
    required this.typesById,
  });

  final MonthlySymptomCounts result;
  final List<SymptomCycleDayCounts> rows;
  final Map<int, SymptomType> typesById;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 142 + result.months.length * 48,
        child: Table(
          columnWidths: {
            0: const FixedColumnWidth(142),
            for (var index = 1; index <= result.months.length; index++)
              index: const FixedColumnWidth(48),
          },
          border: TableBorder(
            horizontalInside: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          children: [
            TableRow(
              children: [
                _monthlyCell(context, 'Symptom', header: true),
                for (final month in result.months)
                  _monthlyCell(context, _formatMonth(month), header: true),
              ],
            ),
            for (final row in rows)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        SymptomGlyphMark(typeId: row.typeId, size: 12),
                        const SizedBox(width: 7),
                        Expanded(child: Text(typesById[row.typeId]!.name)),
                      ],
                    ),
                  ),
                  for (final count
                      in (result.countsByTypeId[row.typeId] ??
                              List.filled(12, 0))
                          .indexed)
                    _monthlyCell(
                      context,
                      count.$2 == 0 ? '·' : '${count.$2}',
                      key: ValueKey('monthly-count-${row.typeId}-${count.$1}'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SymptomEntriesScreen extends StatelessWidget {
  const _SymptomEntriesScreen({required this.type, required this.entries});

  final SymptomType type;
  final List<SymptomEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(type.name)),
      body: ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return ListTile(
            title: Text(formatDate(entry.date), style: tabularFigures),
            subtitle: Text(
              'severity ${entry.severity}'
              '${entry.note == null ? '' : '\n${entry.note}'}',
            ),
          );
        },
      ),
    );
  }
}

TableRow _tableRow(
  BuildContext context,
  List<String> values, {
  bool header = false,
}) => TableRow(
  children: [
    for (var index = 0; index < values.length; index++)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(
          values[index],
          textAlign: index == 0 ? TextAlign.left : TextAlign.right,
          style:
              (header
                      ? Theme.of(context).textTheme.labelMedium
                      : Theme.of(context).textTheme.bodyMedium)
                  ?.merge(tabularFigures),
        ),
      ),
  ],
);

Widget _monthlyCell(
  BuildContext context,
  String value, {
  bool header = false,
  Key? key,
}) => Padding(
  key: key,
  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
  child: Text(
    value,
    textAlign: TextAlign.right,
    style:
        (header
                ? Theme.of(context).textTheme.labelSmall
                : Theme.of(context).textTheme.bodyMedium)
            ?.merge(tabularFigures),
  ),
);

String _distributionText(SymptomCycleDayCounts row) => [
  for (final count in row.countsByCycleDay.entries)
    'd${count.key}×${count.value}',
  if (row.noCycleCount > 0) 'no cycle×${row.noCycleCount}',
].join(' ');

String _summaryText(CycleLengthSummary summary) {
  if (!summary.hasSufficientData) {
    return '${summary.months} mo: insufficient data';
  }
  return '${summary.months} mo: n=${summary.sampleCount}, '
      'min ${summary.minimum}, max ${summary.maximum}, '
      'mean ${_formatMean(summary.mean!)}';
}

String _formatMean(double mean) => mean == mean.roundToDouble()
    ? mean.toInt().toString()
    : mean.toStringAsFixed(1);

String _formatMonth(DateTime date) =>
    '${date.month}/${(date.year % 100).toString().padLeft(2, '0')}';

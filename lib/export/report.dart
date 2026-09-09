import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/calendar.dart';
import '../domain/cycle_lengths.dart';
import '../domain/dates.dart';
import '../domain/hrt_window.dart';
import '../domain/models.dart';
import '../domain/trends.dart';
import '../ui/format.dart';
import '../ui/symptom_glyph.dart';
import '../ui/theme.dart';

class ReportLegendEntry {
  const ReportLegendEntry({required this.medication, required this.laneIndex});

  final Medication medication;
  final int laneIndex;

  String get label => Markers.print.lane(laneIndex).label;
}

class ReportMatrixRow {
  const ReportMatrixRow({
    required this.typeId,
    required this.name,
    required this.values,
  });

  final int typeId;
  final String name;
  final List<String> values;
}

class ReportMatrixChunk {
  const ReportMatrixChunk({
    required this.headers,
    required this.columnWidths,
    required this.rows,
  });

  final List<String> headers;
  final List<double> columnWidths;
  final List<ReportMatrixRow> rows;

  double get tableWidth => columnWidths.fold(0, (sum, width) => sum + width);
}

class ReportData {
  const ReportData({
    required this.range,
    required this.today,
    required this.periods,
    required this.symptomTypes,
    required this.symptomEntries,
    required this.windowsByMedicationId,
    required this.laneByMedicationId,
    required this.months,
    required this.cycleLengths,
    required this.cycleSummaries,
    required this.symptomCycleDayCounts,
    required this.monthlySymptomCounts,
    required this.legendEntries,
    required this.cycleDayMatrixChunks,
    required this.monthlyMatrixChunks,
    this.windowAdjustments = const [],
  });

  final DateRange range;
  final DateTime today;
  final List<Period> periods;
  final List<SymptomType> symptomTypes;
  final List<SymptomEntry> symptomEntries;
  final Map<int, List<MedicationWindow>> windowsByMedicationId;
  final Map<int, int> laneByMedicationId;
  final List<WindowAdjustment> windowAdjustments;
  final List<DateTime> months;
  final List<int?> cycleLengths;
  final List<CycleLengthSummary> cycleSummaries;
  final List<SymptomCycleDayCounts> symptomCycleDayCounts;
  final MonthlySymptomCounts monthlySymptomCounts;
  final List<ReportLegendEntry> legendEntries;
  final List<ReportMatrixChunk> cycleDayMatrixChunks;
  final List<ReportMatrixChunk> monthlyMatrixChunks;
}

ReportData assembleReportData({
  required List<Period> periods,
  required List<Medication> medications,
  required List<SymptomType> symptomTypes,
  required List<SymptomEntry> symptomEntries,
  required Map<int, List<MedicationWindow>> windowsByMedicationId,
  List<WindowAdjustment> windowAdjustments = const [],
  required DateRange range,
  required DateTime today,
}) {
  final firstMonth = DateTime(range.start.year, range.start.month);
  final lastMonth = DateTime(range.end.year, range.end.month);
  final monthCount =
      (lastMonth.year - firstMonth.year) * 12 +
      lastMonth.month -
      firstMonth.month +
      1;
  final symptomCycleDayCounts = symptomCountsByCycleDay(
    symptomEntries,
    periods,
  );
  final monthlySymptomCounts = symptomCountsByMonth(symptomEntries, today);
  final medicationsWithWindows = [
    for (final medication in medications)
      if (medicationHasDerivableWindows(medication, periods, today: today))
        medication,
  ]..sort((left, right) => left.id!.compareTo(right.id!));
  final lanes = laneAssignments(medicationsWithWindows);
  return ReportData(
    range: range,
    today: dateOnly(today),
    periods: periods,
    symptomTypes: symptomTypes,
    symptomEntries: symptomEntries,
    windowsByMedicationId: windowsByMedicationId,
    laneByMedicationId: lanes,
    windowAdjustments: windowAdjustments,
    months: [
      for (var offset = 0; offset < monthCount; offset++)
        DateTime(firstMonth.year, firstMonth.month + offset),
    ],
    cycleLengths: cycleLengthsToNext(periods),
    cycleSummaries: cycleLengthSummaries(periods, today),
    symptomCycleDayCounts: symptomCycleDayCounts,
    monthlySymptomCounts: monthlySymptomCounts,
    legendEntries: [
      for (final medication in medicationsWithWindows)
        ReportLegendEntry(
          medication: medication,
          laneIndex: lanes[medication.id!]!,
        ),
    ],
    cycleDayMatrixChunks: _cycleDayMatrixChunks(
      symptomTypes,
      symptomCycleDayCounts,
    ),
    monthlyMatrixChunks: _monthlyMatrixChunks(
      symptomTypes,
      monthlySymptomCounts,
    ),
  );
}

Future<Uint8List> buildReportPdf(ReportData data) async {
  WidgetsFlutterBinding.ensureInitialized();
  final fonts = await _ReportFonts.load();
  final letterhead = reportLetterheadSvg(
    data: data,
    template: await rootBundle.loadString('brand/letterhead.svg'),
  );
  final document = pw.Document();
  final theme = pw.ThemeData.withFont(base: fonts.sans, bold: fonts.sansBold);

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_pageMargin),
      theme: theme,
      footer: (context) => _footer(context, fonts),
      build: (context) => [
        _reportHeader(letterhead, data.legendEntries, fonts),
        pw.SizedBox(height: 14),
        for (final month in data.months.reversed) ...[
          _monthGrid(data, month, fonts),
          pw.SizedBox(height: 12),
        ],
        _sectionHeading(
          'Cycles',
          '${data.periods.length} recorded · '
              '${data.cycleLengths.whereType<int>().length} complete intervals',
          fonts,
        ),
        _cycleTable(data, fonts),
        pw.SizedBox(height: 8),
        _cycleSummaryTable(data, fonts),
      ],
    ),
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_pageMargin),
      theme: theme,
      footer: (context) => _footer(context, fonts),
      build: (context) => [
        _sectionHeading(
          'Symptoms by cycle day',
          '${data.symptomEntries.length} entries over '
              '${symptomObservationMonthSpan(data.symptomEntries)} months · '
              '${data.symptomCycleDayCounts.length} of ${data.symptomTypes.length} types',
          fonts,
        ),
        ..._matrixTables(data.cycleDayMatrixChunks, fonts),
        pw.SizedBox(height: 14),
        _sectionHeading(
          'Monthly counts',
          '${_monthlyTotal(data.monthlySymptomCounts)} entries over 12 months '
              'to ${formatMonthYear(data.today)}',
          fonts,
        ),
        ..._matrixTables(data.monthlyMatrixChunks, fonts),
        pw.SizedBox(height: 14),
        _sectionHeading(
          'Medication courses',
          'recorded and derived facts',
          fonts,
        ),
        _medicationCourses(data, fonts),
      ],
    ),
  );
  return document.save();
}

class _ReportFonts {
  const _ReportFonts({
    required this.sans,
    required this.sansBold,
    required this.mono,
    required this.monoMedium,
  });

  final pw.Font sans;
  final pw.Font sansBold;
  final pw.Font mono;
  final pw.Font monoMedium;

  static Future<_ReportFonts> load() async => _ReportFonts(
    sans: pw.Font.ttf(
      await rootBundle.load('assets/fonts/PublicSans-Regular.ttf'),
    ),
    sansBold: pw.Font.ttf(
      await rootBundle.load('assets/fonts/PublicSans-SemiBold.ttf'),
    ),
    mono: pw.Font.ttf(await rootBundle.load('assets/fonts/DMMono-Regular.ttf')),
    monoMedium: pw.Font.ttf(
      await rootBundle.load('assets/fonts/DMMono-Medium.ttf'),
    ),
  );
}

String reportLetterheadSvg({
  required ReportData data,
  required String template,
}) {
  return template
      .replaceFirst(RegExp(r'\s*<g font-family="DM Mono,[\s\S]*?</g>'), '')
      .replaceFirst(
        'height="86" viewBox="0 0 547 86"',
        'height="44" viewBox="0 0 547 44"',
      )
      .replaceAll('{{EXPORT_DATE}}', _letterheadDate(data.today))
      .replaceAll(
        '{{RANGE}}',
        '${_letterheadDate(data.range.start)}-'
            '${_letterheadDate(data.range.end)}',
      )
      .replaceAll('{{MED_1}}', '')
      .replaceAll('{{MED_2}}', '')
      .replaceFirst('font-size="11"', 'font-size="9"');
}

String _letterheadDate(DateTime date) =>
    '${date.day} ${monthsShort[date.month - 1]} '
    '${(date.year % 100).toString().padLeft(2, '0')}';

pw.Widget _reportHeader(
  String letterhead,
  List<ReportLegendEntry> legendEntries,
  _ReportFonts fonts,
) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.SvgImage(
      svg: letterhead,
      customFontLookup: (family, style, weight) {
        if (family.contains('DM Mono')) {
          return weight == '600' ? fonts.monoMedium : fonts.mono;
        }
        if (family.contains('Public Sans')) {
          return weight == '600' ? fonts.sansBold : fonts.sans;
        }
        return null;
      },
    ),
    pw.SizedBox(height: 7),
    pw.Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _legendItem(
          _textureBand(MarkerTexture.solid, width: 20, height: 5),
          'period',
          fonts,
        ),
        for (final entry in legendEntries)
          _legendItem(
            _textureBand(
              Markers.print.lane(entry.laneIndex).texture,
              width: 20,
              height: 3,
            ),
            '${entry.label} ${entry.medication.name} ${entry.medication.dose}',
            fonts,
          ),
        _legendItem(_symptomGlyph(1), 'shapes', fonts),
      ],
    ),
  ],
);

pw.Widget _legendItem(pw.Widget marker, String label, _ReportFonts fonts) =>
    pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        marker,
        pw.SizedBox(width: 6),
        pw.Text(label, style: pw.TextStyle(font: fonts.mono, fontSize: 9)),
      ],
    );

pw.Widget _footer(pw.Context context, _ReportFonts fonts) => pw.Container(
  padding: const pw.EdgeInsets.only(top: 6),
  decoration: const pw.BoxDecoration(
    border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.5)),
  ),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'Recorded facts only. No values are predicted or estimated.',
        style: pw.TextStyle(font: fonts.mono, fontSize: 9),
      ),
      pw.Text(
        'page ${context.pageNumber} of ${context.pagesCount}',
        style: pw.TextStyle(font: fonts.mono, fontSize: 9),
      ),
    ],
  ),
);

pw.Widget _monthGrid(ReportData data, DateTime month, _ReportFonts fonts) {
  final firstOffset = month.weekday - DateTime.monday;
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      children: [
        for (final weekday in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
          pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Text(
              weekday,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: fonts.monoMedium, fontSize: 9),
            ),
          ),
      ],
    ),
  ];
  for (var week = 0; week < 6; week++) {
    rows.add(
      pw.TableRow(
        children: [
          for (var weekday = 0; weekday < 7; weekday++)
            _monthCell(
              data,
              data.laneByMedicationId,
              month,
              week * 7 + weekday - firstOffset + 1,
              daysInMonth,
              fonts,
            ),
        ],
      ),
    );
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        '${monthsFull[month.month - 1]} ${month.year}',
        style: pw.TextStyle(font: fonts.sansBold, fontSize: 12),
      ),
      pw.SizedBox(height: 3),
      pw.Table(
        border: pw.TableBorder.all(width: 0.35, color: _rule),
        children: rows,
      ),
    ],
  );
}

pw.Widget _monthCell(
  ReportData data,
  Map<int, int> lanes,
  DateTime month,
  int dayNumber,
  int daysInMonth,
  _ReportFonts fonts,
) {
  final height = _monthCellHeight(data.legendEntries.length);
  if (dayNumber < 1 || dayNumber > daysInMonth) {
    return pw.SizedBox(height: height);
  }
  final date = DateTime(month.year, month.month, dayNumber);
  if (date.isBefore(data.range.start) || date.isAfter(data.range.end)) {
    return pw.SizedBox(height: height);
  }
  final marker = buildDayCellMarkerData(
    date: date,
    today: data.today,
    periods: data.periods,
    windowsByMedicationId: data.windowsByMedicationId,
    laneByMedicationId: lanes,
    entries: data.symptomEntries,
  );
  return pw.Container(
    height: height,
    padding: const pw.EdgeInsets.all(2),
    decoration: date == data.today
        ? pw.BoxDecoration(border: pw.Border.all(width: 1.2))
        : null,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          '$dayNumber',
          style: pw.TextStyle(font: fonts.monoMedium, fontSize: 9),
        ),
        pw.SizedBox(height: 2),
        marker.inPeriod
            ? _textureBand(MarkerTexture.solid, width: 40, height: 4)
            : pw.SizedBox(height: 4),
        pw.SizedBox(height: 2),
        for (var lane = 0; lane < data.legendEntries.length; lane++) ...[
          marker.medicationMarkers.any((item) => item.laneIndex == lane)
              ? _textureBand(
                  Markers.print.lane(lane).texture,
                  width: 40,
                  height: 3,
                )
              : pw.SizedBox(height: 3),
          pw.SizedBox(height: 1),
        ],
        pw.Spacer(),
        pw.Row(
          children: [
            for (final typeId in marker.visibleSymptomTypeIds) ...[
              _symptomGlyph(typeId),
              pw.SizedBox(width: 2),
            ],
            if (marker.symptomOverflowCount > 0)
              pw.Text(
                '+${marker.symptomOverflowCount}',
                style: pw.TextStyle(font: fonts.mono, fontSize: 9),
              ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _sectionHeading(String title, String basis, _ReportFonts fonts) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(font: fonts.sansBold, fontSize: 12),
          ),
          pw.SizedBox(height: 2),
          pw.Text(basis, style: pw.TextStyle(font: fonts.mono, fontSize: 9)),
        ],
      ),
    );

pw.Widget _cycleTable(ReportData data, _ReportFonts fonts) => _textTable(
  [
    const ['start', 'days', 'cycle'],
    for (var index = data.periods.length - 1; index >= 0; index--)
      [
        formatDate(data.periods[index].start),
        '${recordedPeriodLength(data.periods[index], data.today)}',
        data.cycleLengths[index]?.toString() ??
            (data.periods[index].end == null ? 'open' : 'latest'),
      ],
  ],
  fonts,
  columnWidths: {
    0: const pw.FlexColumnWidth(),
    1: const pw.FixedColumnWidth(64),
    2: const pw.FixedColumnWidth(64),
  },
);

pw.Widget _cycleSummaryTable(ReportData data, _ReportFonts fonts) =>
    _textTable([
      const ['window', 'n', 'min', 'max', 'mean'],
      for (final summary in data.cycleSummaries)
        summary.hasSufficientData
            ? [
                '${summary.months} mo',
                '${summary.sampleCount}',
                '${summary.minimum}',
                '${summary.maximum}',
                _formatMean(summary.mean!),
              ]
            : [
                '${summary.months} mo',
                'insufficient data (n=0, 2 starts needed)',
                '',
                '',
                '',
              ],
    ], fonts);

List<ReportMatrixChunk> _cycleDayMatrixChunks(
  List<SymptomType> symptomTypes,
  List<SymptomCycleDayCounts> counts,
) {
  final names = {for (final type in symptomTypes) type.id!: type.name};
  return [
    for (final (start, end, includeAll, includeNoCycle) in const [
      (1, 12, true, false),
      (13, 24, false, false),
      (25, 35, false, true),
    ])
      ReportMatrixChunk(
        headers: [
          'symptom',
          if (includeAll) 'all',
          for (var day = start; day <= end; day++) '$day',
          if (includeNoCycle) 'no cycle',
        ],
        columnWidths: [
          _matrixNameWidth,
          if (includeAll) _matrixAllWidth,
          for (var day = start; day <= end; day++) _cycleDayWidth,
          if (includeNoCycle) _noCycleWidth,
        ],
        rows: [
          for (final row in counts)
            ReportMatrixRow(
              typeId: row.typeId,
              name: names[row.typeId] ?? '',
              values: [
                if (includeAll) '${row.totalCount}',
                for (var day = start; day <= end; day++)
                  _printCount(row.countsByCycleDay[day] ?? 0),
                if (includeNoCycle) _printCount(row.noCycleCount),
              ],
            ),
        ],
      ),
  ];
}

List<ReportMatrixChunk> _monthlyMatrixChunks(
  List<SymptomType> symptomTypes,
  MonthlySymptomCounts result,
) {
  final names = {for (final type in symptomTypes) type.id!: type.name};
  final typeIds = result.countsByTypeId.keys.toList()..sort();
  return [
    for (final (start, end, includeAll) in const [(0, 6, true), (6, 12, false)])
      ReportMatrixChunk(
        headers: [
          'symptom',
          if (includeAll) 'all',
          for (final month in result.months.sublist(start, end))
            '${month.month}/${(month.year % 100).toString().padLeft(2, '0')}',
        ],
        columnWidths: [
          _matrixNameWidth,
          if (includeAll) _matrixAllWidth,
          for (var month = start; month < end; month++) _monthWidth,
        ],
        rows: [
          for (final typeId in typeIds)
            ReportMatrixRow(
              typeId: typeId,
              name: names[typeId] ?? '',
              values: [
                if (includeAll)
                  '${result.countsByTypeId[typeId]!.fold<int>(0, (sum, value) => sum + value)}',
                for (final count in result.countsByTypeId[typeId]!.sublist(
                  start,
                  end,
                ))
                  _printCount(count),
              ],
            ),
        ],
      ),
  ];
}

List<pw.Widget> _matrixTables(
  List<ReportMatrixChunk> chunks,
  _ReportFonts fonts,
) => [
  for (final chunk in chunks.indexed) ...[
    if (chunk.$1 > 0) pw.SizedBox(height: 7),
    pw.Table(
      border: pw.TableBorder(
        top: const pw.BorderSide(color: _rule, width: 0.5),
        bottom: const pw.BorderSide(color: _rule, width: 0.5),
        horizontalInside: const pw.BorderSide(color: _rule, width: 0.5),
      ),
      columnWidths: {
        for (final width in chunk.$2.columnWidths.indexed)
          width.$1: pw.FixedColumnWidth(width.$2),
      },
      children: [
        pw.TableRow(
          repeat: true,
          children: [
            for (final header in chunk.$2.headers.indexed)
              _matrixCell(
                pw.Text(
                  header.$2,
                  textAlign: header.$1 == 0
                      ? pw.TextAlign.left
                      : pw.TextAlign.right,
                  style: pw.TextStyle(font: fonts.monoMedium, fontSize: 9),
                ),
              ),
          ],
        ),
        for (final row in chunk.$2.rows)
          pw.TableRow(
            children: [
              _matrixCell(
                pw.Row(
                  children: [
                    _symptomGlyph(row.typeId),
                    pw.SizedBox(width: 5),
                    pw.Expanded(
                      child: pw.Text(
                        row.name,
                        style: pw.TextStyle(font: fonts.sans, fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ),
              for (final value in row.values)
                _matrixCell(
                  pw.Text(
                    value,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(font: fonts.mono, fontSize: 9),
                  ),
                ),
            ],
          ),
      ],
    ),
  ],
];

pw.Widget _matrixCell(pw.Widget child) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
  child: child,
);

pw.Widget _textTable(
  List<List<String>> rows,
  _ReportFonts fonts, {
  Map<int, pw.TableColumnWidth>? columnWidths,
}) => pw.Table(
  border: pw.TableBorder(
    top: const pw.BorderSide(color: _rule, width: 0.5),
    bottom: const pw.BorderSide(color: _rule, width: 0.5),
    horizontalInside: const pw.BorderSide(color: _rule, width: 0.5),
  ),
  columnWidths: columnWidths,
  children: [
    for (final row in rows.indexed)
      pw.TableRow(
        repeat: row.$1 == 0,
        children: [
          for (final value in row.$2.indexed)
            pw.Padding(
              padding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: pw.Text(
                value.$2,
                textAlign: value.$1 == 0
                    ? pw.TextAlign.left
                    : pw.TextAlign.right,
                style: pw.TextStyle(
                  font: row.$1 == 0 ? fonts.monoMedium : fonts.mono,
                  fontSize: row.$1 == 0 ? 9 : 10,
                ),
              ),
            ),
        ],
      ),
  ],
);

pw.Widget _medicationCourses(ReportData data, _ReportFonts fonts) {
  final adjustmentsByMedication = <int, List<WindowAdjustment>>{};
  for (final adjustment in data.windowAdjustments) {
    adjustmentsByMedication
        .putIfAbsent(adjustment.medicationId, () => [])
        .add(adjustment);
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final legendEntry in data.legendEntries) ...[
        pw.Row(
          children: [
            _textureBand(
              Markers.print.lane(legendEntry.laneIndex).texture,
              width: 20,
              height: 4,
            ),
            pw.SizedBox(width: 6),
            pw.Text(
              '${legendEntry.label} ${legendEntry.medication.name} · '
              '${legendEntry.medication.dose} · '
              '${_scheduleText(legendEntry.medication.schedule)}',
              style: pw.TextStyle(font: fonts.mono, fontSize: 10),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        for (final window
            in data.windowsByMedicationId[legendEntry.medication.id!] ??
                const <MedicationWindow>[])
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 26, bottom: 2),
            child: pw.Text(
              '${window.sourcePeriodStart == null
                  ? 'continuous'
                  : legendEntry.medication.schedule is FixedIntervalMedicationSchedule
                  ? '${formatDate(window.sourcePeriodStart!)} interval'
                  : '${formatDate(window.sourcePeriodStart!)} cycle'} · '
              '${formatDate(window.start)} - ${formatDate(window.end)}'
              '${_adjustmentSuffix(adjustmentsByMedication[legendEntry.medication.id!] ?? const [], window.sourcePeriodStart)}',
              style: pw.TextStyle(font: fonts.mono, fontSize: 9),
            ),
          ),
        for (final adjustment
            in adjustmentsByMedication[legendEntry.medication.id!] ??
                const <WindowAdjustment>[])
          if (adjustment.kind == WindowAdjustmentKind.skipped)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 26, bottom: 2),
              child: pw.Text(
                '${formatDate(adjustment.sourcePeriodStart)} '
                '${legendEntry.medication.schedule is FixedIntervalMedicationSchedule ? 'interval' : 'cycle'} · skipped',
                style: pw.TextStyle(font: fonts.mono, fontSize: 9),
              ),
            ),
        pw.SizedBox(height: 7),
      ],
    ],
  );
}

pw.Widget _textureBand(
  MarkerTexture texture, {
  required double width,
  required double height,
}) => pw.CustomPaint(
  size: PdfPoint(width, height),
  painter: (canvas, size) {
    final (mark, gap) = MarkerTextureMetrics.forTexture(texture, size.x);
    canvas.setFillColor(PdfColors.black);
    for (var left = 0.0; left < size.x; left += mark + gap) {
      canvas.drawRect(left, 0, (left + mark).clamp(0, size.x) - left, size.y);
      canvas.fillPath();
    }
  },
);

pw.Widget _symptomGlyph(int typeId) => pw.CustomPaint(
  size: const PdfPoint(7, 7),
  painter: (canvas, size) {
    final glyph = SymptomGlyph.forTypeId(typeId);
    final open = switch (glyph) {
      SymptomGlyph.circleOpen ||
      SymptomGlyph.diamondOpen ||
      SymptomGlyph.triangleOpen ||
      SymptomGlyph.squareOpen => true,
      _ => false,
    };
    canvas
      ..setStrokeColor(PdfColors.black)
      ..setFillColor(PdfColors.black)
      ..setLineWidth(1);
    switch (glyph) {
      case SymptomGlyph.circle:
      case SymptomGlyph.circleOpen:
        canvas.drawEllipse(3.5, 3.5, 2.5, 2.5);
      case SymptomGlyph.diamond:
      case SymptomGlyph.diamondOpen:
        canvas
          ..moveTo(3.5, 0.7)
          ..lineTo(6.3, 3.5)
          ..lineTo(3.5, 6.3)
          ..lineTo(0.7, 3.5)
          ..closePath();
      case SymptomGlyph.triangle:
      case SymptomGlyph.triangleOpen:
        canvas
          ..moveTo(3.5, 0.7)
          ..lineTo(6.3, 6.3)
          ..lineTo(0.7, 6.3)
          ..closePath();
      case SymptomGlyph.square:
      case SymptomGlyph.squareOpen:
        canvas.drawRect(0.8, 0.8, 5.4, 5.4);
      case SymptomGlyph.plus:
        canvas
          ..drawRect(2.7, 0.5, 1.6, 6)
          ..drawRect(0.5, 2.7, 6, 1.6);
      case SymptomGlyph.cross:
        canvas
          ..drawLine(1, 1, 6, 6)
          ..drawLine(1, 6, 6, 1)
          ..strokePath();
        return;
    }
    if (open) {
      canvas.strokePath();
    } else {
      canvas.fillPath();
    }
  },
);

String _scheduleText(MedicationSchedule schedule) {
  if (schedule is CyclicalMedicationSchedule) {
    return 'cycle day ${schedule.startCycleDay}, ${schedule.durationDays} days';
  }
  if (schedule is FixedIntervalMedicationSchedule) {
    return '${schedule.durationDays} days every ${schedule.intervalDays} days '
        'from ${formatDate(schedule.anchor)}'
        '${schedule.effectiveEnd == null ? '' : ' · stopped ${formatDate(schedule.effectiveEnd!)}'}';
  }
  final continuous = schedule as ContinuousMedicationSchedule;
  return 'continuous since ${formatDate(continuous.start)}'
      '${continuous.end == null ? '' : ' · stopped ${formatDate(continuous.end!)}'}';
}

String _adjustmentSuffix(
  List<WindowAdjustment> adjustments,
  DateTime? sourcePeriodStart,
) {
  if (sourcePeriodStart == null) return '';
  for (final adjustment in adjustments) {
    if (adjustment.sourcePeriodStart == sourcePeriodStart) {
      if (adjustment.kind == WindowAdjustmentKind.skipped) return ' · skipped';
      final started = adjustment.startDate == null
          ? ''
          : ' · started ${formatDate(adjustment.startDate!)}';
      final ended = adjustment.kind == WindowAdjustmentKind.endedEarly
          ? ' · ended early ${formatDate(adjustment.endDate!)}'
          : '';
      return '$started$ended';
    }
  }
  return '';
}

int _monthlyTotal(MonthlySymptomCounts result) =>
    result.countsByTypeId.values.fold(
      0,
      (total, row) => total + row.fold<int>(0, (sum, count) => sum + count),
    );

String _formatMean(double mean) => mean == mean.roundToDouble()
    ? mean.toInt().toString()
    : mean.toStringAsFixed(1);

String _printCount(int count) => count == 0 ? '·' : '$count';

double _monthCellHeight(int medicationCount) =>
    45 + (medicationCount > 4 ? medicationCount - 4 : 0) * 4;

const _rule = PdfColor.fromInt(0xffb3b3b3);
const _pageMargin = 24.0;
const _matrixNameWidth = 150.0;
const _matrixAllWidth = 35.0;
const _cycleDayWidth = 27.0;
const _noCycleWidth = 55.0;
const _monthWidth = 52.0;

double get reportPortraitContentWidth =>
    PdfPageFormat.a4.width - _pageMargin * 2;

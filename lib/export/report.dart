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
import '../ui/theme.dart';

class ReportData {
  const ReportData({
    required this.range,
    required this.today,
    required this.periods,
    required this.medications,
    required this.symptomTypes,
    required this.symptomEntries,
    required this.windowsByMedicationId,
    required this.months,
    required this.cycleLengths,
    required this.cycleSummaries,
    required this.symptomCycleDayCounts,
    required this.monthlySymptomCounts,
    this.windowAdjustments = const [],
  });

  final DateRange range;
  final DateTime today;
  final List<Period> periods;
  final List<Medication> medications;
  final List<SymptomType> symptomTypes;
  final List<SymptomEntry> symptomEntries;
  final Map<int, List<MedicationWindow>> windowsByMedicationId;
  final List<WindowAdjustment> windowAdjustments;
  final List<DateTime> months;
  final List<int?> cycleLengths;
  final List<CycleLengthSummary> cycleSummaries;
  final List<SymptomCycleDayCounts> symptomCycleDayCounts;
  final MonthlySymptomCounts monthlySymptomCounts;
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
  return ReportData(
    range: range,
    today: dateOnly(today),
    periods: periods,
    medications: medications,
    symptomTypes: symptomTypes,
    symptomEntries: symptomEntries,
    windowsByMedicationId: windowsByMedicationId,
    windowAdjustments: windowAdjustments,
    months: [
      for (var offset = 0; offset < monthCount; offset++)
        DateTime(firstMonth.year, firstMonth.month + offset),
    ],
    cycleLengths: cycleLengthsToNext(periods),
    cycleSummaries: cycleLengthSummaries(periods, today),
    symptomCycleDayCounts: symptomCountsByCycleDay(symptomEntries, periods),
    monthlySymptomCounts: symptomCountsByMonth(symptomEntries, today),
  );
}

Future<Uint8List> buildReportPdf(ReportData data) async {
  WidgetsFlutterBinding.ensureInitialized();
  final fonts = await _ReportFonts.load();
  final letterhead = reportLetterheadSvg(
    data: data,
    template: await rootBundle.loadString('assets/brand/letterhead.svg'),
  );
  final document = pw.Document();
  final theme = pw.ThemeData.withFont(base: fonts.sans, bold: fonts.sansBold);

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      theme: theme,
      footer: (context) => _footer(context, fonts),
      build: (context) => [
        _reportHeader(letterhead, fonts),
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
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
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
        _cycleDayTable(data, fonts),
        pw.SizedBox(height: 14),
        _sectionHeading(
          'Monthly counts',
          '${_monthlyTotal(data.monthlySymptomCounts)} entries over 12 months '
              'to ${monthsShort[data.today.month - 1]} ${data.today.year}',
          fonts,
        ),
        _monthlyTable(data, fonts),
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
  final medicationLabels = [
    for (final medication in data.medications.take(2))
      '${medication.name} ${medication.dose}',
  ];
  return template
      .replaceAll('{{EXPORT_DATE}}', _letterheadDate(data.today))
      .replaceAll(
        '{{RANGE}}',
        '${_letterheadDate(data.range.start)}-'
            '${_letterheadDate(data.range.end)}',
      )
      .replaceAll(
        '{{MED_1}}',
        medicationLabels.isEmpty ? '' : _escapeSvgText(medicationLabels[0]),
      )
      .replaceAll(
        '{{MED_2}}',
        medicationLabels.length < 2 ? '' : _escapeSvgText(medicationLabels[1]),
      )
      .replaceFirst('font-size="10"', 'font-size="9"');
}

String _letterheadDate(DateTime date) =>
    '${date.day} ${monthsShort[date.month - 1]} '
    '${(date.year % 100).toString().padLeft(2, '0')}';

String _escapeSvgText(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

pw.Widget _reportHeader(String letterhead, _ReportFonts fonts) => pw.SvgImage(
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
  final lanes = laneAssignments(data.medications);
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
              lanes,
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
  if (dayNumber < 1 || dayNumber > daysInMonth) {
    return pw.SizedBox(height: _monthCellHeight(data.medications.length));
  }
  final date = DateTime(month.year, month.month, dayNumber);
  if (date.isBefore(data.range.start) || date.isAfter(data.range.end)) {
    return pw.SizedBox(height: _monthCellHeight(data.medications.length));
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
    height: _monthCellHeight(data.medications.length),
    padding: const pw.EdgeInsets.all(2),
    decoration: date == data.today
        ? pw.BoxDecoration(border: pw.Border.all(width: 1.2))
        : null,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          '$dayNumber',
          style: pw.TextStyle(font: fonts.monoMedium, fontSize: 8),
        ),
        pw.SizedBox(height: 2),
        marker.inPeriod
            ? _textureBand(MarkerTexture.solid, width: 40, height: 4)
            : pw.SizedBox(height: 4),
        pw.SizedBox(height: 2),
        for (var lane = 0; lane < data.medications.length; lane++) ...[
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
        '${calendarDaysBetween(data.periods[index].start, data.periods[index].end ?? data.today) + 1}',
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

pw.Widget _cycleDayTable(ReportData data, _ReportFonts fonts) {
  final types = {for (final type in data.symptomTypes) type.id!: type.name};
  return _textTable(
    [
      [
        'symptom',
        'all',
        for (var day = 1; day <= 35; day++) '$day',
        'no cycle',
      ],
      for (final row in data.symptomCycleDayCounts)
        [
          types[row.typeId] ?? '',
          '${row.totalCount}',
          for (var day = 1; day <= 35; day++)
            _printCount(row.countsByCycleDay[day] ?? 0),
          _printCount(row.noCycleCount),
        ],
    ],
    fonts,
    fontSize: 9,
    horizontalPadding: 1,
    columnWidths: {
      0: const pw.FixedColumnWidth(150),
      1: const pw.FixedColumnWidth(38),
      for (var column = 2; column < 37; column++)
        column: const pw.FixedColumnWidth(16),
      37: const pw.FixedColumnWidth(46),
    },
  );
}

pw.Widget _monthlyTable(ReportData data, _ReportFonts fonts) {
  final result = data.monthlySymptomCounts;
  final types = {for (final type in data.symptomTypes) type.id!: type.name};
  final typeIds = result.countsByTypeId.keys.toList()..sort();
  return _textTable(
    [
      [
        'symptom',
        'all',
        for (final month in result.months)
          '${month.month}/${(month.year % 100).toString().padLeft(2, '0')}',
      ],
      for (final typeId in typeIds)
        [
          types[typeId] ?? '',
          '${result.countsByTypeId[typeId]!.fold<int>(0, (sum, value) => sum + value)}',
          for (final count in result.countsByTypeId[typeId]!)
            _printCount(count),
        ],
    ],
    fonts,
    columnWidths: {
      0: const pw.FixedColumnWidth(150),
      1: const pw.FixedColumnWidth(38),
      for (var column = 2; column < 14; column++)
        column: const pw.FixedColumnWidth(40),
    },
  );
}

pw.Widget _textTable(
  List<List<String>> rows,
  _ReportFonts fonts, {
  double fontSize = 10,
  double horizontalPadding = 3,
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
              padding: pw.EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 4,
              ),
              child: pw.Text(
                value.$2,
                textAlign: value.$1 == 0
                    ? pw.TextAlign.left
                    : pw.TextAlign.right,
                style: pw.TextStyle(
                  font: row.$1 == 0 ? fonts.monoMedium : fonts.mono,
                  fontSize: row.$1 == 0 ? 9 : fontSize,
                ),
              ),
            ),
        ],
      ),
  ],
);

pw.Widget _medicationCourses(ReportData data, _ReportFonts fonts) {
  final lanes = laneAssignments(data.medications);
  final adjustmentsByMedication = <int, List<WindowAdjustment>>{};
  for (final adjustment in data.windowAdjustments) {
    adjustmentsByMedication
        .putIfAbsent(adjustment.medicationId, () => [])
        .add(adjustment);
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final medication in data.medications) ...[
        pw.Row(
          children: [
            _textureBand(
              Markers.print.lane(lanes[medication.id!]!).texture,
              width: 20,
              height: 4,
            ),
            pw.SizedBox(width: 6),
            pw.Text(
              '${Markers.print.lane(lanes[medication.id!]!).label} '
              '${medication.name} · ${medication.dose} · '
              '${_scheduleText(medication.schedule)}',
              style: pw.TextStyle(font: fonts.mono, fontSize: 10),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        for (final window
            in data.windowsByMedicationId[medication.id!] ??
                const <MedicationWindow>[])
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 26, bottom: 2),
            child: pw.Text(
              '${window.sourcePeriodStart == null
                  ? 'continuous'
                  : medication.schedule is FixedIntervalMedicationSchedule
                  ? '${formatDate(window.sourcePeriodStart!)} interval'
                  : '${formatDate(window.sourcePeriodStart!)} cycle'} · '
              '${formatDate(window.start)} - ${formatDate(window.end)}'
              '${_adjustmentSuffix(data.windowAdjustments, medication.id!, window.sourcePeriodStart)}',
              style: pw.TextStyle(font: fonts.mono, fontSize: 9),
            ),
          ),
        for (final adjustment
            in adjustmentsByMedication[medication.id!] ??
                const <WindowAdjustment>[])
          if (adjustment.kind == WindowAdjustmentKind.skipped)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 26, bottom: 2),
              child: pw.Text(
                '${formatDate(adjustment.sourcePeriodStart)} '
                '${medication.schedule is FixedIntervalMedicationSchedule ? 'interval' : 'cycle'} · skipped',
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
    final (mark, gap) = reportTextureMetrics(texture, size.x);
    canvas.setFillColor(PdfColors.black);
    for (var left = 0.0; left < size.x; left += mark + gap) {
      canvas.drawRect(left, 0, (left + mark).clamp(0, size.x) - left, size.y);
      canvas.fillPath();
    }
  },
);

(double, double) reportTextureMetrics(
  MarkerTexture texture,
  double solidWidth,
) => MarkerTextureMetrics.forTexture(texture, solidWidth);

pw.Widget _symptomGlyph(int typeId) => pw.CustomPaint(
  size: const PdfPoint(7, 7),
  painter: (canvas, size) {
    final shape = (typeId - 1) % 10;
    final open = shape >= 5 && shape <= 8;
    final base = open ? shape - 5 : shape;
    canvas
      ..setStrokeColor(PdfColors.black)
      ..setFillColor(PdfColors.black)
      ..setLineWidth(1);
    if (shape == 9) {
      canvas
        ..drawLine(1, 1, 6, 6)
        ..drawLine(1, 6, 6, 1)
        ..strokePath();
      return;
    }
    switch (base) {
      case 0:
        canvas.drawEllipse(3.5, 3.5, 2.5, 2.5);
        break;
      case 1:
        canvas
          ..moveTo(3.5, 0.7)
          ..lineTo(6.3, 3.5)
          ..lineTo(3.5, 6.3)
          ..lineTo(0.7, 3.5)
          ..closePath();
        break;
      case 2:
        canvas
          ..moveTo(3.5, 0.7)
          ..lineTo(6.3, 6.3)
          ..lineTo(0.7, 6.3)
          ..closePath();
        break;
      case 3:
        canvas.drawRect(0.8, 0.8, 5.4, 5.4);
        break;
      default:
        canvas
          ..drawRect(2.7, 0.5, 1.6, 6)
          ..drawRect(0.5, 2.7, 6, 1.6);
        break;
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
  int medicationId,
  DateTime? sourcePeriodStart,
) {
  if (sourcePeriodStart == null) return '';
  for (final adjustment in adjustments) {
    if (adjustment.medicationId == medicationId &&
        adjustment.sourcePeriodStart == sourcePeriodStart) {
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

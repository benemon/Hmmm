import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/calendar.dart';
import '../domain/cycle_lengths.dart';
import '../domain/dates.dart';
import '../domain/hrt_window.dart';
import '../domain/models.dart';
import '../domain/trends.dart';
import '../ui/format.dart';

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
  });

  final DateRange range;
  final DateTime today;
  final List<Period> periods;
  final List<Medication> medications;
  final List<SymptomType> symptomTypes;
  final List<SymptomEntry> symptomEntries;
  final Map<int, List<MedicationWindow>> windowsByMedicationId;
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
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: pw.ThemeData.withFont(base: pw.Font.helvetica()),
      build: (context) => [
        pw.Text(
          'Hmmm report',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          '${dateToIso(data.range.start)} to ${dateToIso(data.range.end)}',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 8),
        _legend(data),
        pw.SizedBox(height: 8),
        for (final month in data.months) ...[
          _monthGrid(data, month),
          pw.SizedBox(height: 10),
        ],
        pw.Header(level: 1, text: 'Trends'),
        pw.Header(level: 2, text: 'Cycles'),
        _cycleTable(data),
        pw.SizedBox(height: 5),
        for (final summary in data.cycleSummaries)
          pw.Text(
            _summaryText(summary),
            style: const pw.TextStyle(fontSize: 8),
          ),
        pw.Header(level: 2, text: 'Symptoms by cycle day'),
        _cycleDayTable(data),
        pw.Header(level: 2, text: 'Monthly counts'),
        _monthlyTable(data),
      ],
    ),
  );
  return document.save();
}

pw.Widget _legend(ReportData data) {
  final symptomNames = data.symptomTypes
      .map((type) => '${_initial(type.name)} ${type.name}')
      .join('  ');
  return pw.Text(
    'Period: filled  '
    '${[for (final medication in data.medications.indexed) '${medication.$1 + 1} ${medication.$2.name}'].join('  ')}'
    '${symptomNames.isEmpty ? '' : '  $symptomNames'}',
    style: const pw.TextStyle(fontSize: 7),
  );
}

pw.Widget _monthGrid(ReportData data, DateTime month) {
  final firstOffset = month.weekday - DateTime.monday;
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final lanes = laneAssignments(data.medications);
  final typesById = {for (final type in data.symptomTypes) type.id!: type};
  final rows = <pw.TableRow>[
    pw.TableRow(
      children: [
        for (final weekday in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
          pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Text(
              weekday,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
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
              typesById,
              lanes,
              month,
              week * 7 + weekday - firstOffset + 1,
              daysInMonth,
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
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 3),
      pw.Table(
        border: pw.TableBorder.all(width: 0.35, color: PdfColors.black),
        children: rows,
      ),
    ],
  );
}

pw.Widget _monthCell(
  ReportData data,
  Map<int, SymptomType> typesById,
  Map<int, int> lanes,
  DateTime month,
  int dayNumber,
  int daysInMonth,
) {
  if (dayNumber < 1 || dayNumber > daysInMonth) {
    return pw.SizedBox(height: 38);
  }
  final date = DateTime(month.year, month.month, dayNumber);
  if (date.isBefore(data.range.start) || date.isAfter(data.range.end)) {
    return pw.SizedBox(height: 38);
  }
  final marker = buildDayCellMarkerData(
    date: date,
    today: data.today,
    periods: data.periods,
    windowsByMedicationId: data.windowsByMedicationId,
    laneByMedicationId: lanes,
    entries: data.symptomEntries,
  );
  final initials = marker.visibleSymptomTypeIds
      .map((id) => _initial(typesById[id]?.name ?? ''))
      .join('');
  return pw.Container(
    height: 38,
    color: marker.inPeriod ? PdfColors.grey400 : null,
    padding: const pw.EdgeInsets.all(2),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('$dayNumber', style: const pw.TextStyle(fontSize: 7)),
            pw.Text(initials, style: const pw.TextStyle(fontSize: 6)),
          ],
        ),
        pw.Spacer(),
        for (var lane = 0; lane < data.medications.length; lane++)
          pw.Container(
            height: 2,
            margin: const pw.EdgeInsets.only(top: 1),
            decoration:
                marker.medicationMarkers.any(
                  (medication) => medication.laneIndex == lane,
                )
                ? const pw.BoxDecoration(color: PdfColors.black)
                : null,
          ),
      ],
    ),
  );
}

pw.Widget _cycleTable(ReportData data) => _textTable([
  const ['Start', 'Length', 'State'],
  for (var index = data.periods.length - 1; index >= 0; index--)
    [
      dateToIso(data.periods[index].start),
      data.cycleLengths[index]?.toString() ?? '',
      data.periods[index].end == null ? 'ongoing' : '',
    ],
]);

pw.Widget _cycleDayTable(ReportData data) {
  final types = {for (final type in data.symptomTypes) type.id!: type.name};
  return _textTable([
    const ['Symptom', 'Total', 'Cycle day counts'],
    for (final row in data.symptomCycleDayCounts)
      [
        types[row.typeId] ?? '',
        '${row.totalCount}',
        [
          for (final count in row.countsByCycleDay.entries)
            'd${count.key}x${count.value}',
          if (row.noCycleCount > 0) 'no cycle x${row.noCycleCount}',
        ].join(' '),
      ],
  ]);
}

pw.Widget _monthlyTable(ReportData data) {
  final result = data.monthlySymptomCounts;
  final types = {for (final type in data.symptomTypes) type.id!: type.name};
  final typeIds = result.countsByTypeId.keys.toList()..sort();
  return _textTable([
    [
      'Symptom',
      for (final month in result.months) '${month.month}/${month.year % 100}',
    ],
    for (final typeId in typeIds)
      [
        types[typeId] ?? '',
        for (final count in result.countsByTypeId[typeId]!) '$count',
      ],
  ], fontSize: 5.5);
}

pw.Widget _textTable(List<List<String>> rows, {double fontSize = 7}) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.3),
    children: [
      for (final row in rows.indexed)
        pw.TableRow(
          children: [
            for (final value in row.$2)
              pw.Padding(
                padding: const pw.EdgeInsets.all(2),
                child: pw.Text(
                  value,
                  style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: row.$1 == 0 ? pw.FontWeight.bold : null,
                  ),
                ),
              ),
          ],
        ),
    ],
  );
}

String _summaryText(CycleLengthSummary summary) {
  if (!summary.hasSufficientData) {
    return '${summary.months} mo: insufficient data';
  }
  final mean = summary.mean!;
  final meanText = mean == mean.roundToDouble()
      ? mean.toInt().toString()
      : mean.toStringAsFixed(1);
  return '${summary.months} mo: n=${summary.sampleCount}, '
      'min ${summary.minimum}, max ${summary.maximum}, mean $meanText';
}

String _initial(String value) => value.isEmpty ? '' : value[0].toUpperCase();

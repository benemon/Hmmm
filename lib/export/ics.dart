import '../domain/dates.dart';
import '../domain/hrt_window.dart';
import '../domain/models.dart';

class IcsMedicationWindows {
  const IcsMedicationWindows({required this.name, required this.windows});

  final String name;
  final List<MedicationWindow> windows;
}

class IcsSymptomDays {
  const IcsSymptomDays({required this.name, required this.dates});

  final String name;
  final List<DateTime> dates;
}

String buildIcs({
  required List<Period> periods,
  required List<IcsMedicationWindows> windowsByMedication,
  required List<IcsSymptomDays> symptomDaysByType,
  required DateRange range,
  required DateTime exportedAt,
}) {
  final dtstamp = '${_compactDate(exportedAt)}T000000Z';
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Hmmm//Hmmm 1.0//EN',
    'CALSCALE:GREGORIAN',
  ];

  for (final period in periods) {
    final clipped = _clip(period.start, period.end ?? range.end, range);
    if (clipped == null) continue;
    _addEvent(
      lines,
      dtstamp: dtstamp,
      uid: 'hmmm-period-${dateToIso(period.start)}@hmmm.local',
      summary: 'Period',
      start: clipped.$1,
      end: clipped.$2,
    );
  }
  for (final medication in windowsByMedication) {
    for (final window in medication.windows) {
      final clipped = _clip(window.start, window.end, range);
      if (clipped == null) continue;
      final source = window.sourcePeriodStart ?? window.start;
      _addEvent(
        lines,
        dtstamp: dtstamp,
        uid:
            'hmmm-medication-${_uidPart(medication.name)}-'
            '${dateToIso(source)}@hmmm.local',
        summary: medication.name,
        start: clipped.$1,
        end: clipped.$2,
      );
    }
  }
  for (final symptom in symptomDaysByType) {
    for (final date in symptom.dates) {
      if (date.isBefore(range.start) || date.isAfter(range.end)) continue;
      _addEvent(
        lines,
        dtstamp: dtstamp,
        uid:
            'hmmm-symptom-${_uidPart(symptom.name)}-'
            '${dateToIso(date)}@hmmm.local',
        summary: symptom.name,
        start: date,
        end: date,
      );
    }
  }

  lines.add('END:VCALENDAR');
  return '${lines.join('\r\n')}\r\n';
}

void _addEvent(
  List<String> lines, {
  required String dtstamp,
  required String uid,
  required String summary,
  required DateTime start,
  required DateTime end,
}) {
  lines.addAll([
    'BEGIN:VEVENT',
    'UID:$uid',
    'DTSTAMP:$dtstamp',
    'SUMMARY:${_escapeText(summary)}',
    'DTSTART;VALUE=DATE:${_compactDate(start)}',
    'DTEND;VALUE=DATE:${_compactDate(addCalendarDays(end, 1))}',
    'TRANSP:TRANSPARENT',
    'END:VEVENT',
  ]);
}

(DateTime, DateTime)? _clip(DateTime start, DateTime end, DateRange range) {
  if (end.isBefore(range.start) || start.isAfter(range.end)) return null;
  return (
    start.isBefore(range.start) ? range.start : start,
    end.isAfter(range.end) ? range.end : end,
  );
}

String _compactDate(DateTime date) => dateToIso(date).replaceAll('-', '');

String _escapeText(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('\n', '\\n')
    .replaceAll(',', '\\,')
    .replaceAll(';', '\\;');

String _uidPart(String value) {
  final lower = value.toLowerCase();
  final result = StringBuffer();
  var separatorPending = false;
  for (final codePoint in lower.runes) {
    final isLetter = codePoint >= 97 && codePoint <= 122;
    final isDigit = codePoint >= 48 && codePoint <= 57;
    if (isLetter || isDigit) {
      if (separatorPending && result.isNotEmpty) result.write('-');
      result.writeCharCode(codePoint);
      separatorPending = false;
    } else {
      separatorPending = true;
    }
  }
  return result.isEmpty ? 'item' : result.toString();
}

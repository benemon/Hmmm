import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/domain/hrt_window.dart';
import 'package:hmmm/domain/models.dart';
import 'package:hmmm/export/ics.dart';

void main() {
  test('all-day events use exclusive DTEND dates and CRLF lines', () {
    final output = buildIcs(
      periods: [
        Period(start: DateTime(2026, 5, 10), end: DateTime(2026, 5, 14)),
      ],
      windowsByMedication: [
        IcsMedicationWindows(
          name: 'progesterone',
          windows: [
            MedicationWindow(
              start: DateTime(2026, 5, 20),
              end: DateTime(2026, 5, 31),
              sourcePeriodStart: DateTime(2026, 5, 10),
            ),
          ],
        ),
      ],
      symptomDaysByType: [
        IcsSymptomDays(name: 'migraine', dates: [DateTime(2026, 5, 25)]),
      ],
      range: DateRange(start: DateTime(2026, 5, 1), end: DateTime(2026, 5, 31)),
      exportedAt: DateTime(2026, 6, 1),
    );

    expect(output, contains('VERSION:2.0\r\n'));
    expect(output, contains('DTSTAMP:20260601T000000Z\r\n'));
    expect(output, contains('PRODID:-//Hmmm//Hmmm 1.0//EN\r\n'));
    expect(
      output,
      contains(
        'SUMMARY:Period\r\n'
        'DTSTART;VALUE=DATE:20260510\r\n'
        'DTEND;VALUE=DATE:20260515\r\n',
      ),
    );
    expect(
      output,
      contains(
        'SUMMARY:progesterone\r\n'
        'DTSTART;VALUE=DATE:20260520\r\n'
        'DTEND;VALUE=DATE:20260601\r\n',
      ),
    );
    expect(
      output,
      contains(
        'SUMMARY:migraine\r\n'
        'DTSTART;VALUE=DATE:20260525\r\n'
        'DTEND;VALUE=DATE:20260526\r\n',
      ),
    );
    expect(output.replaceAll('\r\n', ''), isNot(contains('\n')));
  });

  test('UIDs are stable and use a cyclical window source period', () {
    final arguments = (
      periods: <Period>[],
      windows: [
        IcsMedicationWindows(
          name: 'Progesterone',
          windows: [
            MedicationWindow(
              start: DateTime(2026, 5, 24),
              end: DateTime(2026, 6, 4),
              sourcePeriodStart: DateTime(2026, 5, 10),
            ),
          ],
        ),
      ],
      symptoms: <IcsSymptomDays>[],
      range: DateRange(start: DateTime(2026, 5, 20), end: DateTime(2026, 6, 4)),
    );

    final first = buildIcs(
      periods: arguments.periods,
      windowsByMedication: arguments.windows,
      symptomDaysByType: arguments.symptoms,
      range: arguments.range,
      exportedAt: DateTime(2026, 6, 1),
    );
    final second = buildIcs(
      periods: arguments.periods,
      windowsByMedication: arguments.windows,
      symptomDaysByType: arguments.symptoms,
      range: arguments.range,
      exportedAt: DateTime(2026, 6, 1),
    );

    expect(first, second);
    expect(
      first,
      contains('UID:hmmm-medication-progesterone-2026-05-10@hmmm.local\r\n'),
    );
  });
}

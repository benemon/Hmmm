import 'package:flutter_test/flutter_test.dart';
import 'package:hmmm/domain/models.dart';
import 'package:hmmm/domain/validation.dart';

void main() {
  final today = DateTime(2026, 6, 15);

  test('overlapping period is rejected', () {
    final existing = [
      Period(id: 1, start: DateTime(2026, 5, 10), end: DateTime(2026, 5, 14)),
    ];

    expect(
      () => validatePeriod(
        Period(start: DateTime(2026, 5, 14), end: DateTime(2026, 5, 17)),
        existing,
        today: today,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('overlap'),
        ),
      ),
    );
  });

  test('period end before start is rejected', () {
    expect(
      () => validatePeriod(
        Period(start: DateTime(2026, 5, 10), end: DateTime(2026, 5, 9)),
        const [],
        today: today,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('on or after'),
        ),
      ),
    );
  });

  test('future period start is rejected', () {
    expect(
      () => validatePeriod(
        Period(start: DateTime(2026, 6, 16)),
        const [],
        today: today,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('future'),
        ),
      ),
    );
  });

  test('future symptom entry is rejected', () {
    expect(
      () => validateSymptomEntry(
        SymptomEntry(date: DateTime(2026, 6, 16), typeId: 1, severity: 2),
        today: today,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('future'),
        ),
      ),
    );
  });

  test('cyclical effective end before start is rejected', () {
    expect(
      () => validateMedication(
        Medication(
          name: 'Progesterone',
          dose: '200 mg',
          schedule: CyclicalMedicationSchedule(
            startCycleDay: 15,
            durationDays: 12,
            effectiveStart: DateTime(2026, 6, 2),
            effectiveEnd: DateTime(2026, 6, 1),
          ),
          active: true,
        ),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'Medication effective end must be on or after its start.',
        ),
      ),
    );
  });
}

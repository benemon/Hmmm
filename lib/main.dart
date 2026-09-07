import 'package:flutter/material.dart';

import 'app_authenticator.dart';
import 'data/database.dart';
import 'data/medication_repository.dart';
import 'data/period_repository.dart';
import 'data/settings_repository.dart';
import 'data/symptom_repository.dart';
import 'domain/dates.dart';
import 'export/json.dart';
import 'ui/app_lock.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      theme: hmmmTheme(Brightness.light),
      darkTheme: hmmmTheme(Brightness.dark),
      home: const Scaffold(),
    ),
  );
  final database = await openHmmmDatabase();
  final periodRepository = PeriodRepository(database);
  final medicationRepository = MedicationRepository(database);
  final symptomRepository = SymptomRepository(database);
  final settingsRepository = SettingsRepository(database);
  await settingsRepository.load();
  runApp(
    HmmmApp(
      periodRepository: periodRepository,
      medicationRepository: medicationRepository,
      symptomRepository: symptomRepository,
      settingsRepository: settingsRepository,
      backupRepository: JsonBackupRepository(database),
      authenticator: LocalAppAuthenticator(),
      today: dateOnly(DateTime.now()),
    ),
  );
}

class HmmmApp extends StatelessWidget {
  const HmmmApp({
    super.key,
    required this.periodRepository,
    required this.medicationRepository,
    required this.symptomRepository,
    required this.settingsRepository,
    required this.backupRepository,
    required this.authenticator,
    required this.today,
  });

  final PeriodRepository periodRepository;
  final MedicationRepository medicationRepository;
  final SymptomRepository symptomRepository;
  final SettingsRepository settingsRepository;
  final JsonBackupRepository backupRepository;
  final AppAuthenticator authenticator;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hmmm',
      theme: hmmmTheme(Brightness.light),
      darkTheme: hmmmTheme(Brightness.dark),
      home: AppLockGate(
        settingsRepository: settingsRepository,
        authenticator: authenticator,
        child: HomeShell(
          periodRepository: periodRepository,
          medicationRepository: medicationRepository,
          symptomRepository: symptomRepository,
          settingsRepository: settingsRepository,
          backupRepository: backupRepository,
          authenticator: authenticator,
          today: today,
        ),
      ),
    );
  }
}

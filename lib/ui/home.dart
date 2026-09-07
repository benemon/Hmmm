import 'package:flutter/material.dart';

import '../app_authenticator.dart';
import '../data/medication_repository.dart';
import '../data/period_repository.dart';
import '../data/settings_repository.dart';
import '../data/symptom_repository.dart';
import '../export/json.dart';
import 'calendar.dart';
import 'settings.dart';
import 'trends.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
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
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_tab) {
        0 => CalendarScreen(
          periodRepository: widget.periodRepository,
          medicationRepository: widget.medicationRepository,
          symptomRepository: widget.symptomRepository,
          today: widget.today,
        ),
        1 => TrendsScreen(
          periodRepository: widget.periodRepository,
          symptomRepository: widget.symptomRepository,
          today: widget.today,
        ),
        _ => SettingsScreen(
          periodRepository: widget.periodRepository,
          medicationRepository: widget.medicationRepository,
          symptomRepository: widget.symptomRepository,
          settingsRepository: widget.settingsRepository,
          backupRepository: widget.backupRepository,
          authenticator: widget.authenticator,
          today: widget.today,
        ),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.table_chart_outlined),
            selectedIcon: Icon(Icons.table_chart),
            label: 'Trends',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../app_authenticator.dart';
import '../data/medication_repository.dart';
import '../data/period_repository.dart';
import '../data/settings_repository.dart';
import '../data/symptom_repository.dart';
import '../domain/hrt_window.dart';
import '../domain/models.dart';
import '../export/ics.dart';
import '../export/json.dart';
import '../export/report.dart';
import 'feedback.dart';
import 'medications.dart';
import 'period_records.dart';
import 'symptom_types.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Medications'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => MedicationsScreen(
                  medicationRepository: medicationRepository,
                  periodRepository: periodRepository,
                  today: today,
                ),
              ),
            ),
          ),
          ListTile(
            title: const Text('Period records'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => PeriodRecordsScreen(
                  repository: periodRepository,
                  today: today,
                ),
              ),
            ),
          ),
          ListTile(
            title: const Text('Symptom types'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) =>
                    SymptomTypesScreen(repository: symptomRepository),
              ),
            ),
          ),
          ListTile(
            title: const Text('Export calendar (.ics)'),
            onTap: () => _exportCalendar(context),
          ),
          ListTile(
            title: const Text('Export data (JSON)'),
            onTap: () => _exportJson(context),
          ),
          ListTile(
            title: const Text('Import data (JSON)'),
            onTap: () => _importJson(context),
          ),
          ListTile(
            title: const Text('Print report'),
            onTap: () => _printReport(context),
          ),
          ListenableBuilder(
            listenable: settingsRepository,
            builder: (context, child) => SwitchListTile(
              title: const Text('Require unlock'),
              value: settingsRepository.requireUnlock,
              onChanged: (value) => _setRequireUnlock(context, value),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCalendar(BuildContext context) async {
    final months = await _chooseRange(context);
    if (months == null || !context.mounted) return;
    final data = await _loadData();
    if (!context.mounted) return;
    final range = _rangeForMonths(today, months);
    final text = buildIcs(
      periods: data.periods,
      windowsByMedication: [
        for (final medication in data.medications)
          IcsMedicationWindows(
            name: medication.name,
            windows: deriveWindows(medication, data.periods, range),
          ),
      ],
      symptomDaysByType: [
        for (final type in data.symptomTypes)
          IcsSymptomDays(
            name: type.name,
            dates: data.symptomEntries
                .where((entry) => entry.typeId == type.id)
                .map((entry) => entry.date)
                .toList(),
          ),
      ],
      range: range,
      exportedAt: today,
    );
    await _shareTextFile(
      context,
      text,
      name: 'hmmm-calendar.ics',
      mimeType: 'text/calendar',
    );
  }

  Future<void> _exportJson(BuildContext context) async {
    final text = await backupRepository.export(exportedAt: today);
    if (!context.mounted) return;
    await _shareTextFile(
      context,
      text,
      name: 'hmmm-data.json',
      mimeType: 'application/json',
    );
  }

  Future<void> _importJson(BuildContext context) async {
    final controller = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import data (JSON)'),
        content: TextField(
          key: const ValueKey('import-json-text'),
          controller: controller,
          autofocus: true,
          minLines: 8,
          maxLines: 16,
          decoration: const InputDecoration(hintText: 'Paste JSON'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (source == null || !context.mounted) return;
    try {
      parseJsonExport(source);
    } on FormatException catch (error) {
      showMessage(context, error.message);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('Current data will be replaced.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-import-json'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await backupRepository.restore(source);
      periodRepository.refresh();
      medicationRepository.refresh();
      symptomRepository.refresh();
      await settingsRepository.refresh();
      if (context.mounted) showMessage(context, 'Data imported.');
    } on Exception {
      if (context.mounted) {
        showMessage(context, 'Import failed. Current data was not changed.');
      }
    }
  }

  Future<void> _printReport(BuildContext context) async {
    final months = await _chooseRange(context);
    if (months == null) return;
    final source = await _loadData();
    final data = assembleReportData(
      periods: source.periods,
      medications: source.medications,
      symptomTypes: source.symptomTypes,
      symptomEntries: source.symptomEntries,
      range: _rangeForMonths(today, months),
      today: today,
    );
    final bytes = await buildReportPdf(data);
    await Printing.sharePdf(bytes: bytes, filename: 'hmmm-report.pdf');
  }

  Future<void> _setRequireUnlock(BuildContext context, bool value) async {
    if (!value) {
      await settingsRepository.setRequireUnlock(false);
      return;
    }
    var authenticated = false;
    try {
      authenticated = await authenticator.authenticate();
    } on Exception {
      authenticated = false;
    }
    if (!context.mounted) return;
    if (!authenticated) {
      showMessage(context, 'Device authentication unavailable.');
      return;
    }
    await settingsRepository.setRequireUnlock(true);
  }

  Future<_ExportData> _loadData() async => _ExportData(
    periods: await periodRepository.listPeriods(),
    medications: await medicationRepository.listMedications(),
    symptomTypes: await symptomRepository.listTypes(),
    symptomEntries: await symptomRepository.listEntries(),
  );
}

Future<int?> _chooseRange(BuildContext context) => showDialog<int>(
  context: context,
  builder: (context) => SimpleDialog(
    title: const Text('Range'),
    children: [
      for (final months in const [1, 3, 6, 12])
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, months),
          child: Text('$months ${months == 1 ? 'month' : 'months'}'),
        ),
    ],
  ),
);

DateRange _rangeForMonths(DateTime today, int months) => DateRange(
  start: DateTime(today.year, today.month - months + 1),
  end: today,
);

Future<void> _shareTextFile(
  BuildContext context,
  String text, {
  required String name,
  required String mimeType,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(text)),
          mimeType: mimeType,
        ),
      ],
      fileNameOverrides: [name],
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

class _ExportData {
  const _ExportData({
    required this.periods,
    required this.medications,
    required this.symptomTypes,
    required this.symptomEntries,
  });

  final List<Period> periods;
  final List<Medication> medications;
  final List<SymptomType> symptomTypes;
  final List<SymptomEntry> symptomEntries;
}

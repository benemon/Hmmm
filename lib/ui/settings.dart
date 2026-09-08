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
import 'format.dart';
import 'medications.dart';
import 'period_records.dart';
import 'symptom_types.dart';
import 'theme.dart';

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

  Future<_SettingsData> _loadData() async => _SettingsData(
    periods: await periodRepository.listPeriods(),
    medications: await medicationRepository.listMedications(),
    symptomTypes: await symptomRepository.listTypes(),
    symptomEntries: await symptomRepository.listEntries(),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        periodRepository,
        medicationRepository,
        symptomRepository,
        settingsRepository,
      ]),
      builder: (context, child) => FutureBuilder<_SettingsData>(
        future: _loadData(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          return Scaffold(
            appBar: AppBar(title: const Text('Settings')),
            body: data == null
                ? const SizedBox.shrink()
                : ListView(
                    children: [
                      const _SettingsGroupHeader('RECORDS'),
                      _SettingsRow(
                        title: 'Medications',
                        detail:
                            '${data.medications.length} · '
                            '${data.medications.where((item) => item.active).length} active',
                        navigating: true,
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
                      _SettingsRow(
                        title: 'Period records',
                        detail: _periodDetail(data.periods),
                        navigating: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => PeriodRecordsScreen(
                              repository: periodRepository,
                              today: today,
                            ),
                          ),
                        ),
                      ),
                      _SettingsRow(
                        title: 'Symptom types',
                        detail:
                            '${data.symptomTypes.length} · '
                            '${data.symptomTypes.where((item) => !item.builtin).length} custom',
                        navigating: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => SymptomTypesScreen(
                              repository: symptomRepository,
                            ),
                          ),
                        ),
                      ),
                      const _SettingsGroupHeader('EXPORT'),
                      _SettingsRow(
                        title: 'Print report',
                        detail: 'PDF · choose 1/3/6/12 months',
                        onTap: () => _printReport(context),
                      ),
                      _SettingsRow(
                        title: 'Export calendar',
                        detail: 'hmmm-calendar.ics',
                        onTap: () => _exportCalendar(context),
                      ),
                      _SettingsRow(
                        title: 'Export data',
                        detail: 'hmmm-data.json · complete record',
                        onTap: () => _exportJson(context),
                      ),
                      _SettingsRow(
                        title: 'Import data',
                        detail: 'JSON · replaces everything',
                        onTap: () => _importJson(context),
                      ),
                      const _SettingsGroupHeader('SECURITY'),
                      _RequireUnlockRow(
                        value: settingsRepository.requireUnlock,
                        onChanged: (value) => _setRequireUnlock(context, value),
                      ),
                      const _SettingsGroupHeader('ABOUT'),
                      const _AboutBlock(),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Future<void> _exportCalendar(BuildContext context) async {
    final months = await _chooseRange(context, today);
    if (months == null || !context.mounted) return;
    final data = await _loadData();
    if (!context.mounted) return;
    final range = rangeForMonths(today, months);
    final windows = await medicationRepository.loadAdjustedWindows(
      medications: data.medications,
      periods: data.periods,
      range: range,
      today: today,
    );
    if (!context.mounted) return;
    final text = buildIcs(
      periods: data.periods,
      windowsByMedication: [
        for (final medication in data.medications)
          IcsMedicationWindows(
            name: medication.name,
            windows: windows.windowsByMedicationId[medication.id!]!,
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
        title: const Text('Import data'),
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
        title: const Text('Replace all data?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current record', style: HmmmType.of(context).figure),
            const SizedBox(height: Dim.s1),
            const Text(
              'Every current record is removed before the imported record is written.',
            ),
          ],
        ),
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
    } on Exception {
      if (context.mounted) {
        showMessage(context, 'Import failed. Current data was not changed.');
      }
    }
  }

  Future<void> _printReport(BuildContext context) async {
    final months = await _chooseRange(context, today);
    if (months == null) return;
    final source = await _loadData();
    final range = rangeForMonths(today, months);
    final windows = await medicationRepository.loadAdjustedWindows(
      medications: source.medications,
      periods: source.periods,
      range: range,
      today: today,
    );
    final data = assembleReportData(
      periods: source.periods,
      medications: source.medications,
      symptomTypes: source.symptomTypes,
      symptomEntries: source.symptomEntries,
      windowsByMedicationId: windows.windowsByMedicationId,
      windowAdjustments: windows.adjustments,
      range: range,
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
}

class _SettingsGroupHeader extends StatelessWidget {
  const _SettingsGroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final rule = Theme.of(context).colorScheme.outlineVariant;
    return Semantics(
      header: true,
      child: ExcludeFocus(
        child: Container(
          padding: const EdgeInsets.fromLTRB(Dim.s4, Dim.s3, Dim.s4, 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              top: BorderSide(color: rule),
              bottom: BorderSide(color: rule),
            ),
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelSmall),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.detail,
    required this.onTap,
    this.navigating = false,
  });

  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool navigating;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Dim.rowMinHeight),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: Dim.s4),
        title: Text(title),
        subtitle: Text(
          detail,
          style: HmmmType.of(context).figureSmall
              .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        trailing: navigating ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ),
    );
  }
}

class _RequireUnlockRow extends StatelessWidget {
  const _RequireUnlockRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      value: value ? 'on' : 'off',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Dim.rowMinHeight),
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Dim.s4),
          title: const Text('Require unlock'),
          subtitle: Text(
            'device authentication on open',
            style: HmmmType.of(context).figureSmall.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _AboutBlock extends StatelessWidget {
  const _AboutBlock();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Dim.s4, Dim.s4, Dim.s4, Dim.s7),
      child: Text(
        'Hmmm 0.1.2\n'
        'local SQLite · no network permission\n'
        'excluded from device backup\n'
        'JSON export is the only way data leaves this device',
        style: HmmmType.of(context).figureSmall.copyWith(
          height: 20 / 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

Future<int?> _chooseRange(BuildContext context, DateTime today) =>
    showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Range'),
        contentPadding: const EdgeInsets.symmetric(vertical: Dim.s2),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final months in const [1, 3, 6, 12])
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Dim.minTarget),
                child: ListTile(
                  title: Text(
                    '$months ${months == 1 ? 'month' : 'months'}',
                    style: HmmmType.of(context).figureSmall,
                  ),
                  subtitle: Text(
                    _rangeDescription(rangeForMonths(today, months)),
                    style: HmmmType.of(context).figureSmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, months),
                ),
              ),
          ],
        ),
      ),
    );

DateRange rangeForMonths(DateTime today, int months) => DateRange(
  start: DateTime(today.year, today.month - months + 1),
  end: today,
);

String _rangeDescription(DateRange range) =>
    '${formatDate(range.start)} – ${formatDate(range.end)}';

String _periodDetail(List<Period> periods) {
  if (periods.isEmpty) return '0 · no records';
  final newest = periods.last;
  return '${periods.length} · newest ${formatDate(newest.start)}, '
      '${newest.end == null ? 'open' : 'ended ${formatDate(newest.end!)}'}';
}

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

class _SettingsData {
  const _SettingsData({
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

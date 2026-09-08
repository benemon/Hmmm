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
                    key: const ValueKey('settings-list'),
                    children: [
                      _SettingsRow(
                        key: const ValueKey('settings-records'),
                        title: 'Records',
                        detail:
                            '${_count(data.medications.length, 'medication')} · '
                            '${_count(data.periods.length, 'period')} · '
                            '${_count(data.symptomTypes.length, 'symptom type')}',
                        navigating: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => _RecordsScreen(
                              medicationRepository: medicationRepository,
                              periodRepository: periodRepository,
                              symptomRepository: symptomRepository,
                              today: today,
                            ),
                          ),
                        ),
                      ),
                      _SettingsRow(
                        key: const ValueKey('settings-export-print'),
                        title: 'Export & print',
                        detail: 'ics · json · pdf',
                        navigating: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => _ExportPrintScreen(
                              onPrintReport: () => _printReport(context),
                              onExportCalendar: () => _exportCalendar(context),
                              onExportData: () => _exportJson(context),
                              onImportData: () => _importJson(context),
                            ),
                          ),
                        ),
                      ),
                      _SettingsRow(
                        key: const ValueKey('settings-theme'),
                        title: 'Theme',
                        detail: settingsRepository.themeMode.name,
                        onTap: () => _setThemeMode(context),
                      ),
                      _RequireUnlockRow(
                        key: const ValueKey('settings-require-unlock'),
                        value: settingsRepository.requireUnlock,
                        onChanged: (value) => _setRequireUnlock(context, value),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Future<void> _exportCalendar(BuildContext context) async {
    final export = await _chooseExport(context);
    if (export == null || !context.mounted) return;
    final text = buildIcs(
      periods: export.source.periods,
      windowsByMedication: [
        for (final medication in export.source.medications)
          IcsMedicationWindows(
            name: medication.name,
            windows: export.windowsByMedicationId[medication.id!]!,
          ),
      ],
      symptomDaysByType: [
        for (final type in export.source.symptomTypes)
          IcsSymptomDays(
            name: type.name,
            dates: export.source.symptomEntries
                .where((entry) => entry.typeId == type.id)
                .map((entry) => entry.date)
                .toList(),
          ),
      ],
      range: export.range,
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
    var input = '';
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import data'),
        content: TextField(
          key: const ValueKey('import-json-text'),
          autofocus: true,
          minLines: 8,
          maxLines: 16,
          onChanged: (value) => input = value,
          decoration: const InputDecoration(hintText: 'Paste JSON'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
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
    final export = await _chooseExport(context);
    if (export == null) return;
    final data = assembleReportData(
      periods: export.source.periods,
      medications: export.source.medications,
      symptomTypes: export.source.symptomTypes,
      symptomEntries: export.source.symptomEntries,
      windowsByMedicationId: export.windowsByMedicationId,
      windowAdjustments: export.adjustments,
      range: export.range,
      today: today,
    );
    final bytes = await buildReportPdf(data);
    await Printing.sharePdf(bytes: bytes, filename: 'hmmm-report.pdf');
  }

  Future<_ExportData?> _chooseExport(BuildContext context) async {
    final source = await _loadData();
    final adjustments = await medicationRepository.listAdjustments();
    final rangeEnd = latestDerivedWindowEnd(
      medications: source.medications,
      periods: source.periods,
      adjustments: adjustments,
      today: today,
    );
    if (!context.mounted) return null;
    final months = await _chooseRange(context, today, rangeEnd);
    if (months == null) return null;
    final range = rangeForMonths(today, months, rangeEnd);
    return _ExportData(
      source: source,
      adjustments: adjustments,
      range: range,
      windowsByMedicationId: {
        for (final medication in source.medications)
          medication.id!: deriveAdjustedWindows(
            medication,
            source.periods,
            range,
            adjustments,
            today: today,
          ),
      },
    );
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

  Future<void> _setThemeMode(BuildContext context) async {
    final mode = await _chooseThemeMode(context);
    if (mode == null) return;
    await settingsRepository.setThemeMode(mode);
  }
}

class _RecordsScreen extends StatelessWidget {
  const _RecordsScreen({
    required this.periodRepository,
    required this.medicationRepository,
    required this.symptomRepository,
    required this.today,
  });

  final PeriodRepository periodRepository;
  final MedicationRepository medicationRepository;
  final SymptomRepository symptomRepository;
  final DateTime today;

  Future<_SettingsData> _loadData() async => _SettingsData(
    periods: await periodRepository.listPeriods(),
    medications: await medicationRepository.listMedications(),
    symptomTypes: await symptomRepository.listTypes(),
    symptomEntries: const [],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      periodRepository,
      medicationRepository,
      symptomRepository,
    ]),
    builder: (context, child) => FutureBuilder<_SettingsData>(
      future: _loadData(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          key: const ValueKey('records-screen'),
          appBar: AppBar(
            title: Semantics(namesRoute: true, child: const Text('Records')),
          ),
          body: data == null
              ? const SizedBox.shrink()
              : ListView(
                  children: [
                    _SettingsRow(
                      key: const ValueKey('records-medications'),
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
                      key: const ValueKey('records-periods'),
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
                      key: const ValueKey('records-symptom-types'),
                      title: 'Symptom types',
                      detail:
                          '${data.symptomTypes.length} · '
                          '${data.symptomTypes.where((item) => !item.builtin).length} custom',
                      navigating: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) =>
                              SymptomTypesScreen(repository: symptomRepository),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    ),
  );
}

class _ExportPrintScreen extends StatelessWidget {
  const _ExportPrintScreen({
    required this.onPrintReport,
    required this.onExportCalendar,
    required this.onExportData,
    required this.onImportData,
  });

  final VoidCallback onPrintReport;
  final VoidCallback onExportCalendar;
  final VoidCallback onExportData;
  final VoidCallback onImportData;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('export-print-screen'),
    appBar: AppBar(
      title: Semantics(namesRoute: true, child: const Text('Export & print')),
    ),
    body: ListView(
      children: [
        _SettingsRow(
          key: const ValueKey('export-print-report'),
          title: 'Print report',
          detail: 'PDF · choose 1/3/6/12 months',
          onTap: onPrintReport,
        ),
        _SettingsRow(
          key: const ValueKey('export-calendar'),
          title: 'Export calendar',
          detail: 'hmmm-calendar.ics',
          onTap: onExportCalendar,
        ),
        _SettingsRow(
          key: const ValueKey('export-data'),
          title: 'Export data',
          detail: 'hmmm-data.json · complete record',
          onTap: onExportData,
        ),
        _SettingsRow(
          key: const ValueKey('import-data'),
          title: 'Import data',
          detail: 'JSON · replaces everything',
          onTap: onImportData,
        ),
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    super.key,
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
    return Semantics(
      button: true,
      label: '$title, $detail',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Dim.rowMinHeight),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Dim.s4),
          title: Text(title),
          subtitle: Text(
            detail,
            style: HmmmType.of(context).figureSmall.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: navigating ? const Icon(Icons.chevron_right) : null,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _RequireUnlockRow extends StatelessWidget {
  const _RequireUnlockRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

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

Future<int?> _chooseRange(
  BuildContext context,
  DateTime today,
  DateTime rangeEnd,
) => showDialog<int>(
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
                _rangeDescription(rangeForMonths(today, months, rangeEnd)),
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

Future<AppThemeMode?> _chooseThemeMode(BuildContext context) =>
    showDialog<AppThemeMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Theme'),
        contentPadding: const EdgeInsets.symmetric(vertical: Dim.s2),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (mode, label, detail) in const [
              (AppThemeMode.system, 'System', 'follow the device setting'),
              (AppThemeMode.light, 'Light', 'always light'),
              (AppThemeMode.dark, 'Dark', 'always dark'),
            ])
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Dim.minTarget),
                child: ListTile(
                  title: Text(label),
                  subtitle: Text(
                    detail,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  onTap: () => Navigator.pop(context, mode),
                ),
              ),
          ],
        ),
      ),
    );

DateRange rangeForMonths(DateTime today, int months, DateTime rangeEnd) =>
    DateRange(
      start: DateTime(today.year, today.month - months + 1),
      end: rangeEnd.isAfter(today) ? rangeEnd : today,
    );

String _rangeDescription(DateRange range) =>
    '${formatDate(range.start)} – ${formatDate(range.end)}';

String _periodDetail(List<Period> periods) {
  if (periods.isEmpty) return '0 · no records';
  final newest = periods.last;
  return '${periods.length} · newest ${formatDate(newest.start)}, '
      '${newest.end == null ? 'open' : 'ended ${formatDate(newest.end!)}'}';
}

String _count(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';

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

class _ExportData {
  const _ExportData({
    required this.source,
    required this.adjustments,
    required this.range,
    required this.windowsByMedicationId,
  });

  final _SettingsData source;
  final List<WindowAdjustment> adjustments;
  final DateRange range;
  final Map<int, List<MedicationWindow>> windowsByMedicationId;
}

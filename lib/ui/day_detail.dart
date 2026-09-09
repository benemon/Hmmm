import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/medication_repository.dart';
import '../data/period_repository.dart';
import '../data/symptom_repository.dart';
import '../domain/calendar.dart';
import '../domain/dates.dart';
import '../domain/hrt_window.dart';
import '../domain/models.dart';
import 'feedback.dart';
import 'format.dart';
import 'marker_band.dart';
import 'symptom_glyph.dart';
import 'theme.dart';

class DayDetailSheet extends StatefulWidget {
  const DayDetailSheet({
    super.key,
    required this.initialDate,
    required this.today,
    required this.periodRepository,
    required this.medicationRepository,
    required this.symptomRepository,
  });

  final DateTime initialDate;
  final DateTime today;
  final PeriodRepository periodRepository;
  final MedicationRepository medicationRepository;
  final SymptomRepository symptomRepository;

  @override
  State<DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends State<DayDetailSheet> {
  static const _historyAnchor = 10000;
  late final DateTime _initialDate = dateOnly(widget.initialDate);
  late final bool _initialIsFuture = _initialDate.isAfter(
    dateOnly(widget.today),
  );
  late final int _initialPage = _initialIsFuture
      ? _historyAnchor + calendarDaysBetween(widget.today, _initialDate)
      : _historyAnchor;
  late final int _lastPage = _initialIsFuture
      ? _initialPage
      : _initialPage + calendarDaysBetween(_initialDate, widget.today);
  late final PageController _pageController = PageController(
    initialPage: _initialPage,
  );
  late final Listenable _repositories;

  @override
  void initState() {
    super.initState();
    _repositories = Listenable.merge([
      widget.periodRepository,
      widget.medicationRepository,
      widget.symptomRepository,
    ]);
  }

  Future<_DayDetailData> _loadData() async {
    final periods = await widget.periodRepository.listPeriods();
    final medications = await widget.medicationRepository.listMedications();
    final types = await widget.symptomRepository.listTypes();
    final entries = await widget.symptomRepository.listEntries();
    final windows = await widget.medicationRepository.loadAdjustedWindows(
      medications: medications,
      periods: periods,
      range: unboundedDateRange,
      today: widget.today,
    );
    final adjustmentsByMedicationId = <int, Map<DateTime, WindowAdjustment>>{};
    for (final adjustment in windows.adjustments) {
      (adjustmentsByMedicationId[adjustment.medicationId] ??=
              {})[adjustment.sourcePeriodStart] =
          adjustment;
    }
    final medicationsWithWindows = [
      for (final medication in medications)
        if (medicationHasDerivableWindows(
          medication,
          periods,
          today: widget.today,
        ))
          medication,
    ];
    return _DayDetailData(
      periods: periods,
      medications: medications,
      types: types,
      entries: entries,
      laneByMedicationId: laneAssignments(medicationsWithWindows),
      adjustmentsByMedicationId: adjustmentsByMedicationId,
      windowsByMedicationId: windows.windowsByMedicationId,
      unadjustedWindowsByMedicationId: {
        for (final medication in medicationsWithWindows)
          medication.id!: deriveWindows(
            medication,
            periods,
            unboundedDateRange,
            today: widget.today,
          ),
      },
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Day detail, ${formatLongDate(_initialDate)}',
      child: DraggableScrollableSheet(
        expand: false,
        minChildSize: 0.50,
        initialChildSize: 0.85,
        maxChildSize: 0.96,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outline)),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Dim.radiusSheet),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              const SliverToBoxAdapter(child: _GrabHandle()),
              SliverFillRemaining(
                hasScrollBody: true,
                child: ListenableBuilder(
                  listenable: _repositories,
                  builder: (context, child) => FutureBuilder<_DayDetailData>(
                    future: _loadData(),
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      if (data == null) return const SizedBox.shrink();
                      return PageView.builder(
                        key: const ValueKey('day-detail-pages'),
                        controller: _pageController,
                        physics: const ClampingScrollPhysics(),
                        itemCount: _lastPage + 1,
                        onPageChanged: (index) {
                          SemanticsService.sendAnnouncement(
                            View.of(context),
                            formatLongDate(_dateForPage(index)),
                            Directionality.of(context),
                          );
                        },
                        itemBuilder: (context, index) => _DayPage(
                          date: _dateForPage(index),
                          today: widget.today,
                          data: data,
                          onPrevious: index == 0
                              ? null
                              : () => _goToPage(index - 1),
                          onNext: index >= _lastPage
                              ? null
                              : () => _goToPage(index + 1),
                          periodRepository: widget.periodRepository,
                          medicationRepository: widget.medicationRepository,
                          symptomRepository: widget.symptomRepository,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateTime _dateForPage(int index) =>
      addCalendarDays(_initialDate, index - _initialPage);

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: Motion.scaled(context, Motion.dayPage),
      curve: Motion.curve,
    );
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('day-sheet-grab-handle'),
    height: Dim.minTarget,
    child: Center(
      child: Container(
        width: Dim.s7,
        height: Dim.s1,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline,
          borderRadius: BorderRadius.circular(Dim.radiusBandCap),
        ),
      ),
    ),
  );
}

class _DayDetailData {
  const _DayDetailData({
    required this.periods,
    required this.medications,
    required this.types,
    required this.entries,
    required this.laneByMedicationId,
    required this.adjustmentsByMedicationId,
    required this.windowsByMedicationId,
    required this.unadjustedWindowsByMedicationId,
  });

  final List<Period> periods;
  final List<Medication> medications;
  final List<SymptomType> types;
  final List<SymptomEntry> entries;
  final Map<int, int> laneByMedicationId;
  final Map<int, Map<DateTime, WindowAdjustment>> adjustmentsByMedicationId;
  final Map<int, List<MedicationWindow>> windowsByMedicationId;
  final Map<int, List<MedicationWindow>> unadjustedWindowsByMedicationId;
}

class _DayPage extends StatelessWidget {
  const _DayPage({
    required this.date,
    required this.today,
    required this.data,
    required this.onPrevious,
    required this.onNext,
    required this.periodRepository,
    required this.medicationRepository,
    required this.symptomRepository,
  });

  final DateTime date;
  final DateTime today;
  final _DayDetailData data;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final PeriodRepository periodRepository;
  final MedicationRepository medicationRepository;
  final SymptomRepository symptomRepository;

  @override
  Widget build(BuildContext context) {
    final cycleDay = cycleDayForDate(date, data.periods);
    final openPeriod = data.periods
        .where((period) => period.end == null)
        .firstOrNull;
    final coveringOpenPeriod =
        openPeriod != null &&
            !date.isBefore(openPeriod.start) &&
            !date.isAfter(today)
        ? openPeriod
        : null;
    final coveringClosedPeriod = data.periods.where((period) {
      final end = period.end;
      return end != null && !date.isBefore(period.start) && !date.isAfter(end);
    }).firstOrNull;
    final entriesByTypeId = {
      for (final entry in data.entries)
        if (entry.date == date) entry.typeId: entry,
    };
    final courses = _coursesForDate(date, data);
    final activeCourseCount = courses.where((course) => course.active).length;
    final sortedTypes = [...data.types]
      ..sort((a, b) {
        final aEntry = entriesByTypeId[a.id];
        final bEntry = entriesByTypeId[b.id];
        if (aEntry != null && bEntry == null) return -1;
        if (aEntry == null && bEntry != null) return 1;
        if (aEntry != null && bEntry != null) {
          final severity = bEntry.severity.compareTo(aEntry.severity);
          if (severity != 0) return severity;
        }
        return a.id!.compareTo(b.id!);
      });

    return Column(
      children: [
        _DayHeader(
          date: date,
          cycleDay: cycleDay,
          onPrevious: onPrevious,
          onNext: onNext,
        ),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey('day-detail-${dateToIso(date)}'),
            padding: const EdgeInsets.only(bottom: Dim.s7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetBlock(
                  semanticsLabel: 'Period',
                  label: 'PERIOD',
                  child: _PeriodBlock(
                    date: date,
                    today: today,
                    periods: data.periods,
                    openPeriod: openPeriod,
                    coveringOpenPeriod: coveringOpenPeriod,
                    coveringClosedPeriod: coveringClosedPeriod,
                    repository: periodRepository,
                  ),
                ),
                const Divider(height: 1),
                _SheetBlock(
                  semanticsLabel: 'Medications',
                  label:
                      'MEDICATIONS  $activeCourseCount of '
                      '${data.medications.length} active today',
                  child: _MedicationBlock(
                    date: date,
                    courses: courses,
                    medicationCount: data.medications.length,
                    repository: medicationRepository,
                  ),
                ),
                const Divider(height: 1),
                _SheetBlock(
                  semanticsLabel: 'Symptoms',
                  label:
                      'SYMPTOMS  ${entriesByTypeId.length} of '
                      '${data.types.length} recorded',
                  meta: 'tap to set severity 0–3 · hold for note',
                  child: _SymptomsBlock(
                    date: date,
                    today: today,
                    types: sortedTypes,
                    entriesByTypeId: entriesByTypeId,
                    repository: symptomRepository,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.date,
    required this.cycleDay,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime date;
  final int? cycleDay;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    liveRegion: true,
    header: true,
    label:
        '${formatLongDate(date)}. ${_weekdays[date.weekday - 1]}'
        '${cycleDay == null ? '' : '. Cycle day $cycleDay'}',
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Dim.daySheetHeaderHeight),
      child: Row(
        children: [
          Semantics(
            label: 'Previous day',
            button: true,
            enabled: onPrevious != null,
            child: IconButton(
              key: const ValueKey('previous-day'),
              tooltip: 'Previous day',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
          ),
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    formatDate(date),
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${_weekdays[date.weekday - 1]}'
                    '${cycleDay == null ? '' : ' · cycle day $cycleDay'}',
                    softWrap: false,
                    style: HmmmType.of(context).figureSmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            label: 'Next day',
            button: true,
            enabled: onNext != null,
            child: IconButton(
              key: const ValueKey('next-day'),
              tooltip: 'Next day',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SheetBlock extends StatelessWidget {
  const _SheetBlock({
    required this.semanticsLabel,
    required this.label,
    required this.child,
    this.meta,
  });

  final String semanticsLabel;
  final String label;
  final Widget child;
  final String? meta;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semanticsLabel,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Dim.s4, Dim.s4, Dim.s4, Dim.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(label, style: Theme.of(context).textTheme.labelSmall),
          ),
          if (meta != null) ...[
            const SizedBox(height: Dim.s1),
            Text(meta!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: Dim.s3),
          child,
        ],
      ),
    ),
  );
}

class _PeriodBlock extends StatelessWidget {
  const _PeriodBlock({
    required this.date,
    required this.today,
    required this.periods,
    required this.openPeriod,
    required this.coveringOpenPeriod,
    required this.coveringClosedPeriod,
    required this.repository,
  });

  final DateTime date;
  final DateTime today;
  final List<Period> periods;
  final Period? openPeriod;
  final Period? coveringOpenPeriod;
  final Period? coveringClosedPeriod;
  final PeriodRepository repository;

  @override
  Widget build(BuildContext context) {
    final covering = coveringClosedPeriod ?? coveringOpenPeriod;
    final recordedDays = covering == null
        ? null
        : recordedPeriodLength(covering, today);
    final status = coveringClosedPeriod != null
        ? '${formatDate(coveringClosedPeriod!.start)} – '
              '${formatDate(coveringClosedPeriod!.end!)}'
        : coveringOpenPeriod != null
        ? 'started ${formatDate(coveringOpenPeriod!.start)} · open'
        : 'none recorded';
    final facts = coveringClosedPeriod != null
        ? '$recordedDays recorded '
              '${recordedDays == 1 ? 'day' : 'days'}, '
              'end recorded'
        : coveringOpenPeriod != null
        ? '$recordedDays recorded '
              '${recordedDays == 1 ? 'day' : 'days'}, '
              'no end recorded'
        : _nearestStartText(date, periods);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(status, style: HmmmType.of(context).figure),
        if (facts != null) ...[
          const SizedBox(height: Dim.s1),
          Text(
            facts,
            style: HmmmType.of(context).figureSmall.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (covering != null ||
            (openPeriod == null && !date.isAfter(today))) ...[
          const SizedBox(height: Dim.s3),
          Wrap(
            spacing: Dim.s2,
            runSpacing: Dim.s2,
            children: [
              if (openPeriod == null &&
                  coveringClosedPeriod == null &&
                  !date.isAfter(today))
                FilledButton(
                  key: ValueKey('period-start-${dateToIso(date)}'),
                  onPressed: () => _startPeriod(context),
                  child: const Text('Period started'),
                )
              else if (coveringOpenPeriod != null)
                FilledButton(
                  key: ValueKey('period-end-${dateToIso(date)}'),
                  onPressed: () => _endPeriod(context, coveringOpenPeriod!),
                  child: const Text('Period ended'),
                ),
              if (covering != null)
                TextButton(
                  key: ValueKey('period-delete-${dateToIso(date)}'),
                  onPressed: () => _deletePeriod(context, covering),
                  child: const Text('Delete record'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _deletePeriod(BuildContext context, Period period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete period record?'),
        content: Text(
          '${formatPeriodRange(period.start, period.end)}\n\n'
          'Derived medication windows from this start are removed too.',
          style: HmmmType.of(context).figure,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-period'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await repository.delete(period.id!);
  }

  Future<void> _startPeriod(BuildContext context) async {
    try {
      await repository.insert(Period(start: date), today: today);
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }

  Future<void> _endPeriod(BuildContext context, Period period) async {
    try {
      await repository.update(
        Period(id: period.id, start: period.start, end: date),
        today: today,
      );
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }
}

class _MedicationCourse {
  const _MedicationCourse({
    required this.medication,
    required this.window,
    required this.laneIndex,
    required this.adjustment,
    required this.active,
    required this.previousStart,
  });

  final Medication medication;
  final MedicationWindow window;
  final int laneIndex;
  final WindowAdjustment? adjustment;
  final bool active;
  final DateTime? previousStart;
}

class _MedicationBlock extends StatelessWidget {
  const _MedicationBlock({
    required this.date,
    required this.courses,
    required this.medicationCount,
    required this.repository,
  });

  final DateTime date;
  final List<_MedicationCourse> courses;
  final int medicationCount;
  final MedicationRepository repository;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return Text(
        medicationCount == 0 ? '0 medications configured' : 'none active',
        style: HmmmType.of(context).figureSmall
            .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      children: [
        for (final course in courses)
          _MedicationCourseRow(
            date: date,
            course: course,
            repository: repository,
          ),
      ],
    );
  }
}

class _MedicationCourseRow extends StatelessWidget {
  const _MedicationCourseRow({
    required this.date,
    required this.course,
    required this.repository,
  });

  final DateTime date;
  final _MedicationCourse course;
  final MedicationRepository repository;

  @override
  Widget build(BuildContext context) {
    final marker = Markers.of(context).lane(course.laneIndex);
    final adjustment = course.adjustment;
    return Semantics(
      customSemanticsActions: course.window.sourcePeriodStart == null
          ? const {}
          : {
              const CustomSemanticsAction(label: 'Course started…'): () =>
                  _adjustCourse(context, _CourseAction.startedOn),
            },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Dim.rowMinHeight),
        child: Row(
          children: [
            SizedBox(
              width: Dim.s5,
              child: MarkerBand(
                color: marker.color,
                height: Dim.laneBandHeight,
                texture: marker.texture,
              ),
            ),
            const SizedBox(width: Dim.s2),
            Text(marker.label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: Dim.s2),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Dim.s2,
                    runSpacing: 0,
                    children: [
                      Text(
                        course.medication.name,
                        style: HmmmType.of(context).bodyStrong,
                      ),
                      Text(
                        course.medication.dose,
                        style: HmmmType.of(context).figureSmall,
                      ),
                    ],
                  ),
                  Text(
                    _courseDerivation(course),
                    style: HmmmType.of(context).figureSmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (adjustment?.startDate != null)
                    Text(
                      'started ${formatDate(adjustment!.startDate!)}',
                      style: HmmmType.of(context).figureSmall,
                    ),
                  if (adjustment?.kind == WindowAdjustmentKind.endedEarly)
                    Text(
                      'ended early ${formatDate(adjustment!.endDate!)}',
                      style: HmmmType.of(context).figureSmall,
                    ),
                  if (adjustment?.kind == WindowAdjustmentKind.skipped)
                    Text('skipped', style: HmmmType.of(context).figureSmall),
                ],
              ),
            ),
            if (course.window.sourcePeriodStart != null)
              PopupMenuButton<_CourseAction>(
                key: ValueKey(
                  'course-actions-${course.medication.id}-'
                  '${dateToIso(course.window.sourcePeriodStart!)}',
                ),
                tooltip: 'Course adjustment',
                onSelected: (action) => _adjustCourse(context, action),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _CourseAction.startedOn,
                    child: SizedBox(
                      height: Dim.minTarget,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Course started…'),
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _CourseAction.endedEarly,
                    child: SizedBox(
                      height: Dim.minTarget,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Course ended ${formatDate(date)}'),
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _CourseAction.skipped,
                    child: SizedBox(
                      height: Dim.minTarget,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Course skipped'),
                      ),
                    ),
                  ),
                  if (adjustment != null) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _CourseAction.restore,
                      child: SizedBox(
                        height: Dim.minTarget,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Restore full course'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _adjustCourse(BuildContext context, _CourseAction action) async {
    final source = course.window.sourcePeriodStart!;
    if (action == _CourseAction.restore) {
      await repository.clearAdjustment(course.medication.id!, source);
      return;
    }
    final current = course.adjustment;
    DateTime? startDate = current?.startDate;
    if (action == _CourseAction.startedOn) {
      final selected = await showDatePicker(
        context: context,
        initialDate: startDate ?? course.window.start,
        firstDate: DateTime(1, 1, 1),
        lastDate: DateTime(9999, 12, 31),
      );
      if (selected == null) return;
      startDate = selected;
    }
    await repository.setAdjustment(
      WindowAdjustment(
        medicationId: course.medication.id!,
        sourcePeriodStart: source,
        kind: switch (action) {
          _CourseAction.startedOn =>
            current?.kind == WindowAdjustmentKind.endedEarly ||
                    current?.kind == WindowAdjustmentKind.skipped
                ? current!.kind
                : WindowAdjustmentKind.startedOn,
          _CourseAction.endedEarly => WindowAdjustmentKind.endedEarly,
          _CourseAction.skipped => WindowAdjustmentKind.skipped,
          _CourseAction.restore => throw StateError('Restore handled above.'),
        },
        startDate: startDate,
        endDate: action == _CourseAction.endedEarly ? date : current?.endDate,
      ),
    );
  }
}

class _SymptomsBlock extends StatelessWidget {
  const _SymptomsBlock({
    required this.date,
    required this.today,
    required this.types,
    required this.entriesByTypeId,
    required this.repository,
  });

  final DateTime date;
  final DateTime today;
  final List<SymptomType> types;
  final Map<int, SymptomEntry> entriesByTypeId;
  final SymptomRepository repository;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final oneColumn = textScaler.scale(1) >= Dim.singleColumnTextScale;
    final chipHeight = math.max(Dim.minTarget, textScaler.scale(22) + Dim.s6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: types.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: oneColumn ? 1 : 2,
            crossAxisSpacing: Dim.s2,
            mainAxisSpacing: Dim.s2,
            mainAxisExtent: chipHeight,
          ),
          itemBuilder: (context, index) {
            final type = types[index];
            final entry = entriesByTypeId[type.id];
            return _SeverityChip(
              key: ValueKey('symptom-chip-${dateToIso(date)}-${type.id}'),
              type: type,
              entry: entry,
              enabled: !date.isAfter(today),
              onTap: () => _cycleSymptom(context, type, entry),
              onLongPress: () => _editNote(context, type, entry),
            );
          },
        ),
        const SizedBox(height: Dim.s3),
        OutlinedButton(
          key: const ValueKey('add-symptom-type'),
          onPressed: () => _addSymptomType(context),
          child: const Text('Add symptom type'),
        ),
      ],
    );
  }

  Future<void> _cycleSymptom(
    BuildContext context,
    SymptomType type,
    SymptomEntry? entry,
  ) async {
    try {
      await repository.upsertEntry(
        SymptomEntry(
          date: date,
          typeId: type.id!,
          severity: nextSymptomSeverity(entry?.severity ?? 0),
          note: entry?.note,
        ),
        today: today,
      );
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }

  Future<void> _editNote(
    BuildContext context,
    SymptomType type,
    SymptomEntry? entry,
  ) async {
    if (date.isAfter(today)) return;
    final controller = TextEditingController(text: entry?.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !context.mounted) return;
    try {
      await repository.upsertEntry(
        SymptomEntry(
          date: date,
          typeId: type.id!,
          severity: entry?.severity ?? 1,
          note: note.isEmpty ? null : note,
        ),
        today: today,
      );
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }

  Future<void> _addSymptomType(BuildContext context) async {
    var typeName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Symptom type'),
        content: TextField(
          key: const ValueKey('symptom-type-name'),
          autofocus: true,
          onChanged: (value) => typeName = value,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-add-symptom-type'),
            onPressed: () => Navigator.pop(context, typeName.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    try {
      await repository.insertType(SymptomType(name: name, builtin: false));
    } on ArgumentError catch (error) {
      if (context.mounted) showValidationError(context, error);
    }
  }
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({
    super.key,
    required this.type,
    required this.entry,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
  });

  final SymptomType type;
  final SymptomEntry? entry;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final severity = entry?.severity ?? 0;
    final recorded = severity > 0;
    final border = recorded ? scheme.onSurface : scheme.outline;
    final hint = [
      if (entry?.note != null) 'note recorded',
      'double tap to increase severity, long press to edit note',
    ].join('. ');
    final content = AnimatedContainer(
      duration: Motion.scaled(context, Motion.state),
      curve: Motion.curve,
      constraints: const BoxConstraints(minHeight: Dim.minTarget),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(Dim.radiusControl),
        border: enabled
            ? Border.all(color: border, width: recorded ? 1.5 : 1)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          onLongPress: enabled ? onLongPress : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
            child: Row(
              children: [
                SymptomGlyphMark(typeId: type.id!, size: Dim.glyphSizeChip),
                const SizedBox(width: Dim.s2),
                Expanded(
                  child: Text(
                    '${type.name}${entry?.note == null ? '' : '*'}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(width: Dim.s2),
                Text(
                  enabled ? '$severity/3' : 'future',
                  style: HmmmType.of(context).figureSmall.copyWith(
                    color: recorded && enabled
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                    fontWeight: recorded && enabled
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(width: Dim.s2),
                  for (var segment = 1; segment <= 3; segment++) ...[
                    AnimatedContainer(
                      duration: Motion.scaled(context, Motion.state),
                      curve: Motion.curve,
                      width: Dim.s2,
                      height: Dim.s1,
                      decoration: BoxDecoration(
                        color: segment <= severity ? scheme.onSurface : null,
                        border: segment <= severity
                            ? null
                            : Border.all(color: border),
                      ),
                    ),
                    if (segment < 3) const SizedBox(width: 2),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      enabled: enabled,
      button: true,
      label: type.name,
      value: enabled ? '$severity of 3' : 'future',
      hint: enabled ? hint : null,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dim.minTarget),
          child: enabled
              ? content
              : CustomPaint(
                  foregroundPainter: _DashedRoundedBorderPainter(
                    color: scheme.outline,
                  ),
                  child: content,
                ),
        ),
      ),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  const _DashedRoundedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(Dim.radiusControl),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 7) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + 4).clamp(0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedBorderPainter oldDelegate) =>
      color != oldDelegate.color;
}

enum _CourseAction { startedOn, endedEarly, skipped, restore }

List<_MedicationCourse> _coursesForDate(DateTime date, _DayDetailData data) {
  final courses = <_MedicationCourse>[];
  for (final medication in data.medications) {
    final lane = data.laneByMedicationId[medication.id];
    if (lane == null) continue;
    final adjustmentsBySourcePeriod =
        data.adjustmentsByMedicationId[medication.id] ?? const {};
    final unadjustedWindows =
        data.unadjustedWindowsByMedicationId[medication.id]!;
    for (final window in unadjustedWindows) {
      final source = window.sourcePeriodStart;
      final adjustment = source == null
          ? null
          : adjustmentsBySourcePeriod[source];
      final active =
          data.windowsByMedicationId[medication.id]?.any(
            (adjusted) =>
                adjusted.sourcePeriodStart == source &&
                !date.isBefore(adjusted.start) &&
                !date.isAfter(adjusted.end),
          ) ??
          false;
      final withinUnadjusted =
          !date.isBefore(window.start) && !date.isAfter(window.end);
      if (active ||
          (withinUnadjusted &&
              adjustment?.kind == WindowAdjustmentKind.skipped)) {
        courses.add(
          _MedicationCourse(
            medication: medication,
            window: window,
            laneIndex: lane,
            adjustment: adjustment,
            active: active,
            previousStart: source == null
                ? null
                : previousAdjustedCourseStart(
                    sourcePeriodStart: source,
                    unadjustedWindows: unadjustedWindows,
                    adjustmentsBySourcePeriod: adjustmentsBySourcePeriod,
                  ),
          ),
        );
      }
    }
  }
  return courses;
}

String _courseDerivation(_MedicationCourse course) {
  final schedule = course.medication.schedule;
  final previousStart = course.previousStart;
  final spacing = previousStart == null
      ? ''
      : ' · ${calendarDaysBetween(previousStart, course.adjustment?.startDate ?? course.window.start)} '
            'days since last course started';
  if (schedule is CyclicalMedicationSchedule) {
    final lastDay = schedule.startCycleDay + schedule.durationDays - 1;
    return 'day ${schedule.startCycleDay}–$lastDay of the '
        '${formatDayMonth(course.window.sourcePeriodStart!)} cycle · '
        'starts ${formatDayMonth(course.window.start)}$spacing';
  }
  if (schedule is FixedIntervalMedicationSchedule) {
    final courseNumber =
        calendarDaysBetween(
              schedule.anchor,
              course.window.sourcePeriodStart!,
            ) ~/
            schedule.intervalDays +
        1;
    return 'course $courseNumber · started ${formatDate(course.window.start)} '
        'by interval$spacing';
  }
  final continuous = schedule as ContinuousMedicationSchedule;
  return continuous.end == null
      ? 'continuous since ${formatDate(continuous.start)}'
      : 'continuous ${formatDate(continuous.start)} – '
            '${formatDate(continuous.end!)}';
}

String? _nearestStartText(DateTime date, List<Period> periods) {
  if (periods.isEmpty) return null;
  var nearest = periods.first.start;
  var distance = calendarDaysBetween(date, nearest).abs();
  for (final period in periods.skip(1)) {
    final candidateDistance = calendarDaysBetween(date, period.start).abs();
    if (candidateDistance < distance) {
      nearest = period.start;
      distance = candidateDistance;
    }
  }
  final direction = nearest.isBefore(date) ? 'before' : 'after';
  return 'nearest start ${formatDate(nearest)} · $distance '
      '${distance == 1 ? 'day' : 'days'} $direction';
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

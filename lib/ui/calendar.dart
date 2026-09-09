import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../data/medication_repository.dart';
import '../data/period_repository.dart';
import '../data/symptom_repository.dart';
import '../domain/calendar.dart';
import '../domain/dates.dart';
import '../domain/hrt_window.dart';
import '../domain/models.dart';
import 'day_detail.dart';
import 'format.dart';
import 'marker_band.dart';
import 'symptom_glyph.dart';
import 'theme.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.periodRepository,
    required this.medicationRepository,
    required this.symptomRepository,
    required this.today,
  });

  final PeriodRepository periodRepository;
  final MedicationRepository medicationRepository;
  final SymptomRepository symptomRepository;
  final DateTime today;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _scrollController = ScrollController();
  late final Listenable _repositories;
  Object? _positionedLayout;
  double _todayScrollOffset = 0;
  final _todayInView = ValueNotifier(true);

  @override
  void initState() {
    super.initState();
    _repositories = Listenable.merge([
      widget.periodRepository,
      widget.medicationRepository,
      widget.symptomRepository,
    ]);
  }

  Future<_CalendarData> _loadData() async {
    final periods = await widget.periodRepository.listPeriods();
    final medications = (await widget.medicationRepository.listMedications())
        .where(
          (medication) => medicationHasDerivableWindows(
            medication,
            periods,
            today: widget.today,
          ),
        )
        .toList();
    final types = await widget.symptomRepository.listTypes();
    final entries = await widget.symptomRepository.listEntries();
    final currentMonth = DateTime(widget.today.year, widget.today.month);
    final windows = await widget.medicationRepository.loadAdjustedWindows(
      medications: medications,
      periods: periods,
      range: DateRange(
        start: DateTime(
          currentMonth.year,
          currentMonth.month - _pastMonthCount,
        ),
        end: unboundedDateRange.end,
      ),
      today: widget.today,
    );
    final adjustmentsByMedicationId = <int, Map<DateTime, WindowAdjustment>>{};
    for (final adjustment in windows.adjustments) {
      (adjustmentsByMedicationId[adjustment.medicationId] ??=
              {})[adjustment.sourcePeriodStart] =
          adjustment;
    }
    return _CalendarData(
      periods: periods,
      medications: medications,
      types: types,
      entries: entries,
      laneByMedicationId: laneAssignments(medications),
      adjustmentsByMedicationId: adjustmentsByMedicationId,
      windowsByMedicationId: windows.windowsByMedicationId,
      unadjustedWindowsByMedicationId: {
        for (final medication in medications)
          medication.id!: deriveWindows(
            medication,
            periods,
            unboundedDateRange,
            today: widget.today,
          ),
      },
      finalMonth: _lastDerivedMonth(
        currentMonth,
        widget.today,
        medications,
        windows.windowsByMedicationId,
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _todayInView.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repositories,
      builder: (context, child) => FutureBuilder<_CalendarData>(
        future: _loadData(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          final agendaMode =
              MediaQuery.textScalerOf(context).scale(1) >=
              Dim.agendaModeTextScale;
          final laneByMedicationId = data?.laneByMedicationId ?? const {};
          if (data != null) {
            final layout = (
              agendaMode,
              data.medications.length,
              data.periods.length,
              data.entries.length,
            );
            if (_positionedLayout != layout) {
              _positionedLayout = layout;
              _todayScrollOffset = agendaMode
                  ? 0
                  : _pastMonthCount * Dim.monthExtent(data.medications.length);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_scrollController.hasClients) return;
                _scrollController.jumpTo(
                  _todayScrollOffset.clamp(
                    0,
                    _scrollController.position.maxScrollExtent,
                  ),
                );
              });
            }
          }
          return Scaffold(
            appBar: AppBar(
              title: const Text('Calendar'),
              actions: [
                ValueListenableBuilder<bool>(
                  valueListenable: _todayInView,
                  builder: (context, todayInView, child) => IconButton(
                    key: const ValueKey('jump-to-today'),
                    tooltip: 'Jump to today',
                    color: Theme.of(context).colorScheme.onSurface,
                    disabledColor: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.40),
                    onPressed: data == null || todayInView
                        ? null
                        : _jumpToToday,
                    icon: const Icon(Icons.today_outlined),
                  ),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(Dim.legendHeight),
                child: _CalendarLegend(
                  medications: data?.medications ?? const [],
                  laneByMedicationId: laneByMedicationId,
                ),
              ),
            ),
            body: data == null
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      if (!agendaMode) const _WeekdayRow(),
                      Expanded(
                        child: _MonthStrip(
                          scrollController: _scrollController,
                          data: data,
                          today: widget.today,
                          agendaMode: agendaMode,
                          laneByMedicationId: laneByMedicationId,
                          onDayTap: _showDay,
                          onCourseStart: _setCourseStart,
                          onTodayVisibilityChanged: (visible) {
                            if (_todayInView.value != visible) {
                              _todayInView.value = visible;
                            }
                          },
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  void _jumpToToday() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _todayScrollOffset.clamp(0, _scrollController.position.maxScrollExtent),
      duration: Motion.scaled(context, Motion.dayPage),
      curve: Motion.curve,
    );
  }

  Future<void> _showDay(DateTime date) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: AnimationStyle(
        duration: Motion.scaled(context, Motion.sheet),
        reverseDuration: Motion.scaled(context, Motion.sheet),
      ),
      builder: (context) => DayDetailSheet(
        initialDate: date,
        today: widget.today,
        periodRepository: widget.periodRepository,
        medicationRepository: widget.medicationRepository,
        symptomRepository: widget.symptomRepository,
      ),
    );
    if (mounted) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Day detail dismissed',
        Directionality.of(context),
      );
    }
  }

  Future<void> _setCourseStart(_CourseDrag drag, DateTime startDate) async {
    final current = drag.adjustment;
    await widget.medicationRepository.setAdjustment(
      WindowAdjustment(
        medicationId: drag.medication.id!,
        sourcePeriodStart: drag.window.sourcePeriodStart!,
        kind:
            current?.kind == WindowAdjustmentKind.endedEarly ||
                current?.kind == WindowAdjustmentKind.skipped
            ? current!.kind
            : WindowAdjustmentKind.startedOn,
        startDate: startDate,
        endDate: current?.endDate,
      ),
    );
  }
}

class _CalendarData {
  const _CalendarData({
    required this.periods,
    required this.medications,
    required this.types,
    required this.entries,
    required this.laneByMedicationId,
    required this.adjustmentsByMedicationId,
    required this.windowsByMedicationId,
    required this.unadjustedWindowsByMedicationId,
    required this.finalMonth,
  });

  final List<Period> periods;
  final List<Medication> medications;
  final List<SymptomType> types;
  final List<SymptomEntry> entries;
  final Map<int, int> laneByMedicationId;
  final Map<int, Map<DateTime, WindowAdjustment>> adjustmentsByMedicationId;
  final Map<int, List<MedicationWindow>> windowsByMedicationId;
  final Map<int, List<MedicationWindow>> unadjustedWindowsByMedicationId;
  final DateTime finalMonth;
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({
    required this.medications,
    required this.laneByMedicationId,
  });

  final List<Medication> medications;
  final Map<int, int> laneByMedicationId;

  @override
  Widget build(BuildContext context) {
    final markers = Markers.of(context);
    final medicationsWithLanes = [
      for (final medication in medications)
        (medication, markers.lane(laneByMedicationId[medication.id!]!)),
    ];
    final semantics = [
      'Legend.',
      'Period.',
      for (final (medication, lane) in medicationsWithLanes)
        '${lane.label} '
            '${medication.name}${medication.active ? '' : ' stopped'}.',
      'Symptoms shown as shapes.',
    ].join(' ');
    final surface = Theme.of(context).colorScheme.surface;

    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: Container(
          height: Dim.legendHeight,
          decoration: BoxDecoration(
            color: surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Stack(
            children: [
              ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Dim.s3),
                children: [
                  _LegendItem(
                    color: markers.period,
                    texture: MarkerTexture.solid,
                    height: Dim.periodBandHeight,
                    name: 'Period',
                  ),
                  for (final (medication, lane) in medicationsWithLanes)
                    _LegendItem(
                      color: lane.color,
                      texture: lane.texture,
                      height: Dim.laneBandHeight,
                      laneLabel: lane.label,
                      name: medication.active
                          ? medication.name
                          : '${medication.name} (stopped)',
                    ),
                  const _LegendSymptomKey(),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                bottom: 1,
                width: Dim.s4,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [surface.withValues(alpha: 0), surface],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.texture,
    required this.height,
    required this.name,
    this.laneLabel,
  });

  final Color color;
  final MarkerTexture texture;
  final double height;
  final String? laneLabel;
  final String name;

  @override
  Widget build(BuildContext context) {
    final nameStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: Theme.of(context).colorScheme.onSurface);
    return Padding(
      padding: const EdgeInsets.only(right: Dim.s3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: Dim.s5,
            child: MarkerBand(color: color, height: height, texture: texture),
          ),
          const SizedBox(width: 6),
          if (laneLabel != null) ...[
            Text(laneLabel!, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: 6),
          ],
          Text(name, softWrap: false, style: nameStyle),
        ],
      ),
    );
  }
}

class _LegendSymptomKey extends StatelessWidget {
  const _LegendSymptomKey();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: Dim.s3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SymptomGlyphMark(typeId: 1, size: Dim.glyphSizeCalendar),
        const SizedBox(width: 6),
        Text(
          'shapes',
          softWrap: false,
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
      ],
    ),
  );
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      key: const ValueKey('calendar-weekdays'),
      height: Dim.weekdayRowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          for (final weekday in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
            Expanded(
              child: Text(
                weekday,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1.1,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _MonthStrip extends StatefulWidget {
  const _MonthStrip({
    required this.scrollController,
    required this.data,
    required this.today,
    required this.agendaMode,
    required this.laneByMedicationId,
    required this.onDayTap,
    required this.onCourseStart,
    required this.onTodayVisibilityChanged,
  });

  final ScrollController scrollController;
  final _CalendarData data;
  final DateTime today;
  final bool agendaMode;
  final Map<int, int> laneByMedicationId;
  final ValueChanged<DateTime> onDayTap;
  final Future<void> Function(_CourseDrag drag, DateTime startDate)
  onCourseStart;
  final ValueChanged<bool> onTodayVisibilityChanged;

  @override
  State<_MonthStrip> createState() => _MonthStripState();
}

class _MonthStripState extends State<_MonthStrip> {
  late List<DateTime> _months;
  final _agendaCenterKey = GlobalKey();
  final _agendaViewportKey = GlobalKey();
  final _agendaMonthKeys = <int, GlobalKey>{};
  final _dragFocusNode = FocusNode();
  final _dragStart = ValueNotifier<DateTime?>(null);
  _CourseDrag? _activeDrag;
  var _dragCancelled = false;
  var _visibleMonthIndex = _pastMonthCount;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScroll);
    _prepareMonths();
  }

  @override
  void didUpdateWidget(_MonthStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_handleScroll);
      widget.scrollController.addListener(_handleScroll);
    }
    _prepareMonths();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScroll);
    _dragFocusNode.dispose();
    _dragStart.dispose();
    super.dispose();
  }

  void _prepareMonths() {
    final currentMonth = DateTime(widget.today.year, widget.today.month);
    final finalMonth = widget.data.finalMonth;
    final futureMonthCount = _monthsBetween(currentMonth, finalMonth) + 1;
    _months = [
      for (var index = 0; index < _pastMonthCount + futureMonthCount; index++)
        DateTime(
          currentMonth.year,
          currentMonth.month + index - _pastMonthCount,
        ),
    ];
  }

  void _handleScroll() {
    if (!widget.scrollController.hasClients) return;
    if (widget.agendaMode) {
      _handleAgendaScroll();
      return;
    }
    final offset = widget.scrollController.offset;
    final viewportEnd =
        offset + widget.scrollController.position.viewportDimension;
    final monthExtent = Dim.monthExtent(widget.data.medications.length);
    final todayStart = _pastMonthCount * monthExtent;
    final todayEnd = todayStart + monthExtent;
    widget.onTodayVisibilityChanged(
      todayStart < viewportEnd && todayEnd > offset,
    );

    final nextIndex = (offset / monthExtent).floor().clamp(
      0,
      _months.length - 1,
    );
    if (nextIndex != _visibleMonthIndex && mounted) {
      setState(() => _visibleMonthIndex = nextIndex);
    }
  }

  void _handleAgendaScroll() {
    final viewport = _agendaViewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    var nextIndex = _visibleMonthIndex;
    var nextTop = double.negativeInfinity;
    var todayInView = false;

    for (final entry in _agendaMonthKeys.entries) {
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = top + renderObject.size.height;
      if (entry.key == _pastMonthCount) {
        todayInView = top < viewportBottom && bottom > viewportTop;
      }
      if (bottom > viewportTop && top <= viewportTop && top > nextTop) {
        nextIndex = entry.key;
        nextTop = top;
      }
    }

    widget.onTodayVisibilityChanged(todayInView);
    if (nextIndex != _visibleMonthIndex && mounted) {
      setState(() => _visibleMonthIndex = nextIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typeById = {for (final type in widget.data.types) type.id!: type};
    final medicationById = {
      for (final medication in widget.data.medications)
        medication.id!: medication,
    };
    final monthExtent = Dim.monthExtent(widget.data.medications.length);
    return KeyboardListener(
      focusNode: _dragFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        onPointerUp: (_) {
          if (_dragCancelled) _endDrag();
        },
        onPointerCancel: (_) {
          if (_dragCancelled) _endDrag();
        },
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            key: _agendaViewportKey,
            children: [
              if (widget.agendaMode)
                CustomScrollView(
                  key: const ValueKey('calendar-agenda'),
                  controller: widget.scrollController,
                  center: _agendaCenterKey,
                  slivers: [
                    SliverList.builder(
                      itemCount: _pastMonthCount,
                      itemBuilder: (context, index) => _buildMonth(
                        _pastMonthCount - index - 1,
                        typeById,
                        medicationById,
                      ),
                    ),
                    SliverList.builder(
                      key: _agendaCenterKey,
                      itemCount: _months.length - _pastMonthCount,
                      itemBuilder: (context, index) => _buildMonth(
                        _pastMonthCount + index,
                        typeById,
                        medicationById,
                      ),
                    ),
                  ],
                )
              else
                ListView.builder(
                  key: const ValueKey('calendar-grid'),
                  controller: widget.scrollController,
                  padding: EdgeInsets.only(
                    bottom: math.max(0, constraints.maxHeight - monthExtent),
                  ),
                  itemExtent: monthExtent,
                  itemCount: _months.length,
                  itemBuilder: (context, index) =>
                      _buildMonth(index, typeById, medicationById),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Semantics(
                  header: true,
                  label:
                      '${monthsFull[_months[_visibleMonthIndex].month - 1]} '
                      '${_months[_visibleMonthIndex].year}',
                  child: ExcludeSemantics(
                    child: _MonthBand(
                      month: _months[_visibleMonthIndex],
                      expandForText: widget.agendaMode,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonth(
    int index,
    Map<int, SymptomType> typeById,
    Map<int, Medication> medicationById,
  ) => _MonthSection(
    key: widget.agendaMode
        ? _agendaMonthKeys.putIfAbsent(index, GlobalKey.new)
        : null,
    month: _months[index],
    today: widget.today,
    periods: widget.data.periods,
    medications: widget.data.medications,
    windowsByMedicationId: widget.data.windowsByMedicationId,
    laneByMedicationId: widget.laneByMedicationId,
    entries: widget.data.entries,
    typeById: typeById,
    medicationById: medicationById,
    agendaMode: widget.agendaMode,
    onDayTap: widget.onDayTap,
    dragStart: widget.agendaMode || _dragCancelled ? null : _dragForDate,
    dragTargetStart: _dragStart,
    onDragStarted: _startDrag,
    onDragMoved: _moveDrag,
    onDragLeft: () => _dragStart.value = null,
    onDragAccepted: _acceptDrag,
    onDragEnded: _endDrag,
  );

  _CourseDrag? _dragForDate(DateTime date, DayCellMarkerData marker) {
    final medicationMarkers = [...marker.medicationMarkers]
      ..sort((a, b) => a.laneIndex.compareTo(b.laneIndex));
    for (final dayMarker in medicationMarkers) {
      final medication = widget.data.medications
          .where((candidate) => candidate.id == dayMarker.medicationId)
          .first;
      if (medication.schedule is! CyclicalMedicationSchedule) continue;
      final adjustedWindow = widget.data.windowsByMedicationId[medication.id]!
          .where(
            (window) =>
                window.sourcePeriodStart != null &&
                !date.isBefore(window.start) &&
                !date.isAfter(window.end),
          )
          .firstOrNull;
      if (adjustedWindow == null) continue;
      final source = adjustedWindow.sourcePeriodStart!;
      final window = widget.data.unadjustedWindowsByMedicationId[medication.id]!
          .where((candidate) => candidate.sourcePeriodStart == source)
          .first;
      final adjustmentsBySourcePeriod =
          widget.data.adjustmentsByMedicationId[medication.id] ?? const {};
      final adjustment = adjustmentsBySourcePeriod[source];
      return _CourseDrag(
        medication: medication,
        window: window,
        adjustedWindow: adjustedWindow,
        adjustment: adjustment,
        laneIndex: dayMarker.laneIndex,
        grabbedDate: date,
        previousStart: previousAdjustedCourseStart(
          sourcePeriodStart: source,
          unadjustedWindows:
              widget.data.unadjustedWindowsByMedicationId[medication.id]!,
          adjustmentsBySourcePeriod: adjustmentsBySourcePeriod,
        ),
      );
    }
    return null;
  }

  void _startDrag(_CourseDrag drag) {
    _dragFocusNode.requestFocus();
    _activeDrag = drag;
    _dragCancelled = false;
    _dragStart.value = drag.adjustedWindow.start;
  }

  void _moveDrag(DateTime date) {
    final drag = _activeDrag;
    if (drag == null || _dragCancelled) return;
    _dragStart.value = addCalendarDays(
      drag.adjustedWindow.start,
      calendarDaysBetween(drag.grabbedDate, date),
    );
  }

  void _acceptDrag(_CourseDrag drag) {
    final start = _dragStart.value;
    if (_dragCancelled || start == null || drag != _activeDrag) return;
    widget.onCourseStart(drag, start);
  }

  void _endDrag() {
    if (_activeDrag == null && !_dragCancelled && _dragStart.value == null) {
      return;
    }
    if (mounted) {
      setState(() {
        _activeDrag = null;
        _dragCancelled = false;
        _dragStart.value = null;
      });
    }
  }

  void _cancelDrag() {
    if (_activeDrag == null) return;
    setState(() {
      _dragCancelled = true;
      _activeDrag = null;
      _dragStart.value = null;
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _activeDrag != null) {
      _cancelDrag();
    }
  }
}

class _CourseDrag {
  const _CourseDrag({
    required this.medication,
    required this.window,
    required this.adjustedWindow,
    required this.adjustment,
    required this.laneIndex,
    required this.grabbedDate,
    required this.previousStart,
  });

  final Medication medication;
  final MedicationWindow window;
  final MedicationWindow adjustedWindow;
  final WindowAdjustment? adjustment;
  final int laneIndex;
  final DateTime grabbedDate;
  final DateTime? previousStart;
}

class _MonthSection extends StatelessWidget {
  const _MonthSection({
    super.key,
    required this.month,
    required this.today,
    required this.periods,
    required this.medications,
    required this.windowsByMedicationId,
    required this.laneByMedicationId,
    required this.entries,
    required this.typeById,
    required this.medicationById,
    required this.agendaMode,
    required this.onDayTap,
    required this.dragStart,
    required this.dragTargetStart,
    required this.onDragStarted,
    required this.onDragMoved,
    required this.onDragLeft,
    required this.onDragAccepted,
    required this.onDragEnded,
  });

  final DateTime month;
  final DateTime today;
  final List<Period> periods;
  final List<Medication> medications;
  final Map<int, List<MedicationWindow>> windowsByMedicationId;
  final Map<int, int> laneByMedicationId;
  final List<SymptomEntry> entries;
  final Map<int, SymptomType> typeById;
  final Map<int, Medication> medicationById;
  final bool agendaMode;
  final ValueChanged<DateTime> onDayTap;
  final _CourseDrag? Function(DateTime date, DayCellMarkerData marker)?
  dragStart;
  final ValueNotifier<DateTime?> dragTargetStart;
  final ValueChanged<_CourseDrag> onDragStarted;
  final ValueChanged<DateTime> onDragMoved;
  final VoidCallback onDragLeft;
  final ValueChanged<_CourseDrag> onDragAccepted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        key: ValueKey(
          'month-${month.year}-${month.month.toString().padLeft(2, '0')}',
        ),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: _MonthBand(month: month, expandForText: agendaMode),
          ),
          if (agendaMode) _buildAgenda() else _buildGrid(),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final firstOffset = month.weekday - DateTime.monday;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    return Column(
      children: [
        for (var row = 0; row < 6; row++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: _buildCell(firstOffset, row * 7 + column, daysInMonth),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCell(int firstOffset, int index, int daysInMonth) {
    final dayNumber = index - firstOffset + 1;
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return SizedBox(height: Dim.dayCellHeight(medications.length));
    }
    final date = DateTime(month.year, month.month, dayNumber);
    final marker = _marker(date);
    return _DayCell(
      date: date,
      today: today,
      marker: marker,
      medicationCount: medications.length,
      medicationById: medicationById,
      onTap: () => onDayTap(date),
      courseDrag: dragStart?.call(date, marker),
      dragTargetStart: dragTargetStart,
      onDragStarted: onDragStarted,
      onDragMoved: onDragMoved,
      onDragLeft: onDragLeft,
      onDragAccepted: onDragAccepted,
      onDragEnded: onDragEnded,
    );
  }

  Widget _buildAgenda() {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    return Column(
      children: [
        for (var day = 1; day <= daysInMonth; day++)
          if (DateTime(month.year, month.month, day) case final date)
            if (_marker(date) case final marker when _carriesRecords(marker))
              _AgendaDayRow(
                date: date,
                today: today,
                marker: marker,
                entries: entries,
                typeById: typeById,
                medicationById: medicationById,
                onTap: () => onDayTap(date),
              ),
      ],
    );
  }

  DayCellMarkerData _marker(DateTime date) => buildDayCellMarkerData(
    date: date,
    today: today,
    periods: periods,
    windowsByMedicationId: windowsByMedicationId,
    laneByMedicationId: laneByMedicationId,
    entries: entries,
  );
}

class _MonthBand extends StatelessWidget {
  const _MonthBand({required this.month, required this.expandForText});

  final DateTime month;
  final bool expandForText;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(
      'month-band-${month.year}-${month.month.toString().padLeft(2, '0')}',
    ),
    constraints: BoxConstraints(
      minHeight: Dim.monthBandHeight,
      maxHeight: expandForText ? double.infinity : Dim.monthBandHeight,
    ),
    padding: const EdgeInsets.symmetric(horizontal: Dim.s4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Row(
      children: [
        Text(
          monthsFull[month.month - 1],
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Spacer(),
        Text(
          '${month.year}',
          style: HmmmType.of(context).figureSmall
              .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.date,
    required this.today,
    required this.marker,
    required this.medicationCount,
    required this.medicationById,
    required this.onTap,
    required this.courseDrag,
    required this.dragTargetStart,
    required this.onDragStarted,
    required this.onDragMoved,
    required this.onDragLeft,
    required this.onDragAccepted,
    required this.onDragEnded,
  });

  final DateTime date;
  final DateTime today;
  final DayCellMarkerData marker;
  final int medicationCount;
  final Map<int, Medication> medicationById;
  final VoidCallback onTap;
  final _CourseDrag? courseDrag;
  final ValueNotifier<DateTime?> dragTargetStart;
  final ValueChanged<_CourseDrag> onDragStarted;
  final ValueChanged<DateTime> onDragMoved;
  final VoidCallback onDragLeft;
  final ValueChanged<_CourseDrag> onDragAccepted;
  final VoidCallback onDragEnded;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = widget.date == dateOnly(widget.today);

    final cell = Focus(
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('day-${dateToIso(widget.date)}'),
          onTap: widget.onTap,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? scheme.onSurface.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: SizedBox(
            height: Dim.dayCellHeight(widget.medicationCount),
            child: Stack(
              children: [
                if (_focused)
                  Positioned.fill(
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.onSurface, width: 2),
                        borderRadius: BorderRadius.circular(Dim.radiusToday),
                      ),
                    ),
                  ),
                if (isToday)
                  Positioned.fill(
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.onSurface, width: 2),
                        borderRadius: BorderRadius.circular(Dim.radiusToday),
                      ),
                    ),
                  ),
                _DayCellContents(
                  date: widget.date,
                  marker: widget.marker,
                  medicationCount: widget.medicationCount,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final drag = widget.courseDrag;
    final draggable = drag == null
        ? cell
        : LongPressDraggable<_CourseDrag>(
            data: drag,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _CourseDragFeedback(
              drag: drag,
              targetStart: widget.dragTargetStart,
            ),
            onDragStarted: () => widget.onDragStarted(drag),
            onDragEnd: (_) => widget.onDragEnded(),
            childWhenDragging: Opacity(opacity: 0.24, child: cell),
            child: cell,
          );

    return Semantics(
      button: true,
      label: _daySemanticsData(
        widget.date,
        widget.today,
        widget.marker,
        widget.medicationById,
      ),
      child: ExcludeSemantics(
        child: DragTarget<_CourseDrag>(
          onMove: (_) => widget.onDragMoved(widget.date),
          onLeave: (_) => widget.onDragLeft(),
          onAcceptWithDetails: (details) => widget.onDragAccepted(details.data),
          builder: (context, candidates, rejected) => draggable,
        ),
      ),
    );
  }
}

class _DayCellContents extends StatelessWidget {
  const _DayCellContents({
    required this.date,
    required this.marker,
    required this.medicationCount,
  });

  final DateTime date;
  final DayCellMarkerData marker;
  final int medicationCount;

  @override
  Widget build(BuildContext context) {
    final markers = Markers.of(context);
    final dateIso = dateToIso(date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: Dim.s1,
            right: Dim.s1,
            top: Dim.s1,
          ),
          child: Text('${date.day}', style: HmmmType.of(context).dayNumber),
        ),
        const SizedBox(height: Dim.s1),
        SizedBox(
          height: Dim.periodBandHeight,
          child: marker.inPeriod
              ? MarkerBand(
                  color: markers.period,
                  height: Dim.periodBandHeight,
                  texture: MarkerTexture.solid,
                  capStart: marker.startsPeriod,
                  capEnd: marker.endsPeriod,
                )
              : null,
        ),
        const SizedBox(height: Dim.s1),
        SizedBox(
          height: medicationCount * Dim.lanePitch,
          child: Stack(
            children: [
              for (final medication in marker.medicationMarkers)
                Positioned(
                  key: ValueKey(
                    'medication-band-$dateIso-'
                    '${medication.medicationId}',
                  ),
                  top: medication.laneIndex * Dim.lanePitch,
                  left: 0,
                  right: 0,
                  height: Dim.laneBandHeight,
                  child: switch (markers.lane(medication.laneIndex)) {
                    final lane => MarkerBand(
                      color: lane.color,
                      height: Dim.laneBandHeight,
                      texture: lane.texture,
                      capStart: medication.startsWindow,
                      capEnd: medication.endsWindow,
                    ),
                  },
                ),
            ],
          ),
        ),
        const Spacer(),
        SizedBox(
          height: Dim.s3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Dim.s1),
            child: Row(
              children: [
                for (final (index, typeId)
                    in marker.visibleSymptomTypeIds.indexed) ...[
                  SymptomGlyphMark(typeId: typeId, size: Dim.glyphSizeCalendar),
                  if (index < marker.visibleSymptomTypeIds.length - 1)
                    const SizedBox(width: 3),
                ],
                if (marker.symptomOverflowCount > 0)
                  Text(
                    '+${marker.symptomOverflowCount}',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(letterSpacing: 0),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Dim.s1),
      ],
    );
  }
}

class _CourseDragFeedback extends StatelessWidget {
  const _CourseDragFeedback({required this.drag, required this.targetStart});

  final _CourseDrag drag;
  final ValueNotifier<DateTime?> targetStart;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DateTime?>(
    valueListenable: targetStart,
    builder: (context, value, child) {
      final start = value ?? drag.adjustedWindow.start;
      final durationDays =
          calendarDaysBetween(drag.window.start, drag.window.end) + 1;
      final fullEnd = addCalendarDays(start, durationDays - 1);
      final recordedEnd = drag.adjustment?.endDate;
      final end = recordedEnd == null
          ? fullEnd
          : recordedEnd.isBefore(start)
          ? start
          : recordedEnd.isAfter(fullEnd)
          ? fullEnd
          : recordedEnd;
      final spanDays = calendarDaysBetween(start, end) + 1;
      final width = MediaQuery.sizeOf(context).width;
      final cellWidth = width / 7;
      final bandWidth = math.min(width - Dim.s7, cellWidth * spanDays);
      final daysSince = drag.previousStart == null
          ? null
          : calendarDaysBetween(drag.previousStart!, start);
      final label =
          'starts ${formatDayMonth(start)}'
          '${daysSince == null ? '' : ' · $daysSince days since last course started'}';
      final lane = Markers.of(context).lane(drag.laneIndex);
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1),
        duration: Motion.scaled(context, Motion.state),
        curve: Motion.curve,
        builder: (context, scale, child) => Transform.scale(
          alignment: Alignment.topLeft,
          scale: scale,
          child: child,
        ),
        child: Transform.translate(
          offset: const Offset(-Dim.s4, -Dim.s8),
          child: Material(
            color: Colors.transparent,
            child: Column(
              key: const ValueKey('course-drag-ghost'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: bandWidth),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Dim.s2,
                    vertical: Dim.s1,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    borderRadius: BorderRadius.circular(Dim.radiusControl),
                  ),
                  child: Text(
                    label,
                    style: HmmmType.of(context).figureSmall,
                    softWrap: true,
                  ),
                ),
                const SizedBox(height: Dim.s2),
                SizedBox(
                  width: bandWidth,
                  child: Opacity(
                    opacity: 0.72,
                    child: MarkerBand(
                      color: lane.color,
                      height: Dim.laneBandHeight,
                      texture: lane.texture,
                      capStart: true,
                      capEnd: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _AgendaDayRow extends StatelessWidget {
  const _AgendaDayRow({
    required this.date,
    required this.today,
    required this.marker,
    required this.entries,
    required this.typeById,
    required this.medicationById,
    required this.onTap,
  });

  final DateTime date;
  final DateTime today;
  final DayCellMarkerData marker;
  final List<SymptomEntry> entries;
  final Map<int, SymptomType> typeById;
  final Map<int, Medication> medicationById;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dayEntries = entries.where((entry) => entry.date == date).toList();
    return Semantics(
      button: true,
      label: _daySemanticsData(date, today, marker, medicationById),
      child: ExcludeSemantics(
        child: InkWell(
          key: ValueKey('day-${dateToIso(date)}'),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: _agendaRowHeight(context)),
            padding: const EdgeInsets.symmetric(
              horizontal: Dim.s4,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 104,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDate(date),
                        style: HmmmType.of(context).figureSmall,
                      ),
                      if (marker.periodDay != null)
                        Text(
                          'period day ${marker.periodDay}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final medication in marker.medicationMarkers) ...[
                          _AgendaLaneChip(
                            marker: medication,
                            name: medicationById[medication.medicationId]!.name,
                          ),
                          const SizedBox(width: Dim.s2),
                        ],
                        for (final entry in dayEntries) ...[
                          SymptomGlyphMark(
                            typeId: entry.typeId,
                            size: Dim.glyphSizeTable,
                          ),
                          const SizedBox(width: Dim.s1),
                          Text(
                            typeById[entry.typeId]?.name ??
                                'symptom ${entry.typeId}',
                            softWrap: false,
                          ),
                          const SizedBox(width: Dim.s2),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgendaLaneChip extends StatelessWidget {
  const _AgendaLaneChip({required this.marker, required this.name});

  final MedicationDayMarker marker;
  final String name;

  @override
  Widget build(BuildContext context) {
    final lane = Markers.of(context).lane(marker.laneIndex);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Dim.s2, vertical: Dim.s1),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(Dim.radiusControl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: Dim.s5,
            child: MarkerBand(
              color: lane.color,
              height: Dim.laneBandHeight,
              texture: lane.texture,
            ),
          ),
          const SizedBox(width: 6),
          Text(lane.label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(width: 6),
          Text(name, softWrap: false),
        ],
      ),
    );
  }
}

String _daySemanticsData(
  DateTime date,
  DateTime today,
  DayCellMarkerData marker,
  Map<int, Medication> medicationById,
) {
  final clauses = <String>[
    formatLongDate(date),
    if (marker.periodDay != null) 'Period day ${marker.periodDay}',
    if (marker.medicationMarkers.isNotEmpty)
      marker.medicationMarkers
          .map((item) => medicationById[item.medicationId]!.name)
          .join(', '),
    if (marker.symptomCount > 0)
      '${marker.symptomCount} '
          '${marker.symptomCount == 1 ? 'symptom' : 'symptoms'} recorded',
    if (date == dateOnly(today)) 'Today',
  ];
  return '${clauses.join('. ')}.';
}

bool _carriesRecords(DayCellMarkerData marker) =>
    marker.inPeriod ||
    marker.medicationMarkers.isNotEmpty ||
    marker.symptomCount > 0;

const _pastMonthCount = 2400;

int _monthsBetween(DateTime start, DateTime end) =>
    (end.year - start.year) * 12 + end.month - start.month;

double _agendaRowHeight(BuildContext context) =>
    72 * MediaQuery.textScalerOf(context).scale(1);

DateTime _lastDerivedMonth(
  DateTime currentMonth,
  DateTime today,
  List<Medication> medications,
  Map<int, List<MedicationWindow>> windowsByMedicationId,
) {
  var lastDate = DateTime(currentMonth.year, currentMonth.month + 1, 0);
  for (final windows in windowsByMedicationId.values) {
    for (final window in windows) {
      if (window.sourcePeriodStart != null && window.end.isAfter(lastDate)) {
        lastDate = window.end;
      }
    }
  }
  for (final medication in medications) {
    final schedule = medication.schedule;
    if (schedule is! FixedIntervalMedicationSchedule) continue;
    final fixedIntervalExtent = addCalendarDays(
      dateOnly(today),
      schedule.intervalDays + schedule.durationDays,
    );
    if (fixedIntervalExtent.isAfter(lastDate)) lastDate = fixedIntervalExtent;
  }
  return DateTime(lastDate.year, lastDate.month);
}

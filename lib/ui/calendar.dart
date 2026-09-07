import 'package:flutter/material.dart';

import '../data/medication_repository.dart';
import '../data/period_repository.dart';
import '../data/symptom_repository.dart';
import '../domain/calendar.dart';
import '../domain/dates.dart';
import '../domain/hrt_window.dart';
import '../domain/models.dart';
import 'day_detail.dart';
import 'format.dart';
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
  double? _positionedMonthExtent;
  double _todayScrollOffset = 0;

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
    final medications = await widget.medicationRepository.listMedications();
    final entries = await widget.symptomRepository.listEntries();
    return _CalendarData(
      periods: periods,
      medications: medications
          .where(
            (medication) => medicationHasDerivableWindows(medication, periods),
          )
          .toList(),
      entries: entries,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
          if (data != null) {
            final monthExtent = _monthExtent(data.medications.length);
            _todayScrollOffset = _pastMonthCount * monthExtent;
            if (_positionedMonthExtent != monthExtent) {
              _positionedMonthExtent = monthExtent;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.jumpTo(_todayScrollOffset);
                }
              });
            }
          }
          return Scaffold(
            appBar: AppBar(
              title: const Text('Calendar'),
              actions: [
                IconButton(
                  tooltip: 'Today',
                  icon: const Icon(Icons.today_outlined),
                  onPressed: () {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        _todayScrollOffset,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(34),
                child: _CalendarLegend(
                  medications: data?.medications ?? const [],
                  laneByMedicationId: laneAssignments(
                    data?.medications ?? const [],
                  ),
                ),
              ),
            ),
            body: data == null
                ? const SizedBox.shrink()
                : _MonthStrip(
                    scrollController: _scrollController,
                    data: data,
                    today: widget.today,
                    monthExtent: _monthExtent(data.medications.length),
                    laneByMedicationId: laneAssignments(data.medications),
                    onDayTap: _showDay,
                  ),
          );
        },
      ),
    );
  }

  void _showDay(DateTime date) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DayDetailSheet(
        initialDate: date,
        today: widget.today,
        periodRepository: widget.periodRepository,
        medicationRepository: widget.medicationRepository,
        symptomRepository: widget.symptomRepository,
      ),
    );
  }
}

class _CalendarData {
  const _CalendarData({
    required this.periods,
    required this.medications,
    required this.entries,
  });

  final List<Period> periods;
  final List<Medication> medications;
  final List<SymptomEntry> entries;
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
    return Container(
      height: 34,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _LegendItem(color: markers.period, label: 'period'),
          for (final medication in medications)
            _LegendItem(
              color: markers.lane(laneByMedicationId[medication.id!]!),
              label: medication.active
                  ? medication.name
                  : '${medication.name} (stopped)',
            ),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: Text('symptoms as shapes')),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        children: [
          Container(width: 16, height: 4, color: color),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
    );
  }
}

class _MonthStrip extends StatelessWidget {
  const _MonthStrip({
    required this.scrollController,
    required this.data,
    required this.today,
    required this.monthExtent,
    required this.laneByMedicationId,
    required this.onDayTap,
  });

  final ScrollController scrollController;
  final _CalendarData data;
  final DateTime today;
  final double monthExtent;
  final Map<int, int> laneByMedicationId;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final currentMonth = DateTime(today.year, today.month);
    final finalMonth = _lastDerivedMonth(currentMonth);
    final futureMonthCount = _monthsBetween(currentMonth, finalMonth) + 1;

    return ListView.builder(
      controller: scrollController,
      itemExtent: monthExtent,
      itemCount: _pastMonthCount + futureMonthCount,
      itemBuilder: (context, index) => _buildMonth(
        context,
        DateTime(
          currentMonth.year,
          currentMonth.month + index - _pastMonthCount,
        ),
      ),
    );
  }

  DateTime _lastDerivedMonth(DateTime currentMonth) {
    var lastDate = DateTime(currentMonth.year, currentMonth.month + 1, 0);
    for (final medication in data.medications) {
      final schedule = medication.schedule;
      if (schedule is! CyclicalMedicationSchedule) continue;
      for (final period in data.periods) {
        if (!cyclicalScheduleAppliesToPeriodStart(schedule, period.start)) {
          continue;
        }
        final end = addCalendarDays(
          period.start,
          schedule.startCycleDay + schedule.durationDays - 2,
        );
        if (end.isAfter(lastDate)) lastDate = end;
      }
    }
    return DateTime(lastDate.year, lastDate.month);
  }

  int _monthsBetween(DateTime start, DateTime end) =>
      (end.year - start.year) * 12 + end.month - start.month;

  Widget _buildMonth(BuildContext context, DateTime month) {
    final range = DateRange(
      start: month,
      end: DateTime(month.year, month.month + 1, 0),
    );
    final windowsByMedicationId = <int, List<MedicationWindow>>{
      for (final medication in data.medications)
        medication.id!: deriveWindows(medication, data.periods, range),
    };
    return _MonthSection(
      month: month,
      today: today,
      periods: data.periods,
      medications: data.medications,
      windowsByMedicationId: windowsByMedicationId,
      laneByMedicationId: laneByMedicationId,
      entries: data.entries,
      onDayTap: onDayTap,
    );
  }
}

class _MonthSection extends StatelessWidget {
  const _MonthSection({
    required this.month,
    required this.today,
    required this.periods,
    required this.medications,
    required this.windowsByMedicationId,
    required this.laneByMedicationId,
    required this.entries,
    required this.onDayTap,
  });

  final DateTime month;
  final DateTime today;
  final List<Period> periods;
  final List<Medication> medications;
  final Map<int, List<MedicationWindow>> windowsByMedicationId;
  final Map<int, int> laneByMedicationId;
  final List<SymptomEntry> entries;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final firstOffset = month.weekday - DateTime.monday;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    const rowCount = 6;

    return Padding(
      key: ValueKey(
        'month-${month.year}-${month.month.toString().padLeft(2, '0')}',
      ),
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${monthsFull[month.month - 1]} ${month.year}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final weekday in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(child: Center(child: Text(weekday))),
            ],
          ),
          const SizedBox(height: 4),
          for (var row = 0; row < rowCount; row++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: _buildCell(
                      firstOffset,
                      row * 7 + column,
                      daysInMonth,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCell(int firstOffset, int index, int daysInMonth) {
    final dayNumber = index - firstOffset + 1;
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return SizedBox(height: 72 + medications.length * 4);
    }
    final date = DateTime(month.year, month.month, dayNumber);
    final marker = buildDayCellMarkerData(
      date: date,
      today: today,
      periods: periods,
      windowsByMedicationId: windowsByMedicationId,
      laneByMedicationId: laneByMedicationId,
      entries: entries,
    );
    return _DayCell(
      date: date,
      today: today,
      marker: marker,
      medicationCount: medications.length,
      onTap: () => onDayTap(date),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.today,
    required this.marker,
    required this.medicationCount,
    required this.onTap,
  });

  final DateTime date;
  final DateTime today;
  final DayCellMarkerData marker;
  final int medicationCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final markers = Markers.of(context);
    final isToday = date == today;

    return Semantics(
      button: true,
      label: '${date.day} ${monthsFull[date.month - 1]} ${date.year}',
      child: InkWell(
        key: ValueKey('day-${dateToIso(date)}'),
        onTap: onTap,
        child: Container(
          height: 72 + medicationCount * 4,
          decoration: BoxDecoration(
            border: isToday
                ? Border.all(color: scheme.onSurface, width: 1)
                : null,
            borderRadius: isToday ? BorderRadius.circular(4) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 5, top: 3),
                child: Text(
                  '${date.day}',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.merge(tabularFigures),
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 7,
                child: marker.inPeriod
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: markers.period,
                          borderRadius: BorderRadius.horizontal(
                            left: marker.startsPeriod
                                ? const Radius.circular(4)
                                : Radius.zero,
                            right: marker.endsPeriod
                                ? const Radius.circular(4)
                                : Radius.zero,
                          ),
                        ),
                      )
                    : null,
              ),
              SizedBox(
                height: medicationCount * 4,
                child: Stack(
                  children: [
                    for (final medication in marker.medicationMarkers)
                      Positioned(
                        top: medication.laneIndex * 4,
                        left: 0,
                        right: 0,
                        height: 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: markers.lane(medication.laneIndex),
                            borderRadius: BorderRadius.horizontal(
                              left: medication.startsWindow
                                  ? const Radius.circular(2)
                                  : Radius.zero,
                              right: medication.endsWindow
                                  ? const Radius.circular(2)
                                  : Radius.zero,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 3, 4),
                child: Row(
                  children: [
                    for (final typeId in marker.visibleSymptomTypeIds) ...[
                      SymptomGlyphMark(typeId: typeId, size: 9),
                      const SizedBox(width: 2),
                    ],
                    if (marker.symptomOverflowCount > 0)
                      Text(
                        '+${marker.symptomOverflowCount}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _pastMonthCount = 2400;

double _monthExtent(int medicationCount) =>
    100 + 6 * (72 + medicationCount * 4);

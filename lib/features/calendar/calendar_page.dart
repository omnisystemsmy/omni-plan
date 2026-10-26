import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_form_kit.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/core/widgets/omni_plan_fields.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/preferences.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/tasks/task_pickers.dart';
import 'package:provider/provider.dart';

class CalendarPage extends StatelessWidget {
  final String? projectId;

  const CalendarPage({super.key, this.projectId});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: omniListAppBar(context, 'Calendar'),
    body: PlanCalendar(projectId: projectId, allowProjectFilter: projectId == null),
  );
}

/// Tasks and milestones by date, from the stored records. Long-press a task
/// (or use its menu) to move it to another day.
class PlanCalendar extends StatefulWidget {
  final String? projectId;
  final bool allowProjectFilter;

  const PlanCalendar({super.key, this.projectId, this.allowProjectFilter = true});

  @override
  State<PlanCalendar> createState() => _PlanCalendarState();
}

class _PlanCalendarState extends State<PlanCalendar> {
  late DateTime _selected = dateOnly(DateTime.now());
  late DateTime _month = DateTime(_selected.year, _selected.month);
  CalendarViewMode? _modeOverride;
  String? _projectFilter;
  bool _showDone = false;
  bool _showMilestones = true;
  Priority? _priority;

  CalendarViewMode _mode(PlanPreferences p) => _modeOverride ?? CalendarViewMode.fromPref(p.defaultCalendarView);

  String? get _project => widget.projectId ?? _projectFilter;

  List<PlanTask> _tasksOn(PlanStore store, DateTime day) => [
    for (final t in store.tasksDueOn(day))
      if ((_project == null || t.projectId == _project) &&
          (_showDone || !t.isDone) &&
          (_priority == null || t.priority == _priority))
        t,
  ]..sort((a, b) {
    // All-day first, then by time.
    final ma = a.dueMinutes ?? -1, mb = b.dueMinutes ?? -1;
    return ma.compareTo(mb);
  });

  List<Milestone> _milestonesOn(PlanStore store, DateTime day) => !_showMilestones
      ? const []
      : [
          for (final m in store.milestones)
            if (m.dueDate != null &&
                dateOnly(m.dueDate!) == day &&
                (_project == null || m.projectId == _project))
              m,
        ];

  void _move(int delta, CalendarViewMode mode) {
    setState(() {
      switch (mode) {
        case CalendarViewMode.month:
          _month = DateTime(_month.year, _month.month + delta);
          _selected = DateTime(_month.year, _month.month, 1);
        case CalendarViewMode.week:
          _selected = DateTime(_selected.year, _selected.month, _selected.day + 7 * delta);
          _month = DateTime(_selected.year, _selected.month);
        case CalendarViewMode.day:
        case CalendarViewMode.agenda:
          _selected = DateTime(_selected.year, _selected.month, _selected.day + delta);
          _month = DateTime(_selected.year, _selected.month);
      }
    });
  }

  void _today() => setState(() {
    _selected = dateOnly(DateTime.now());
    _month = DateTime(_selected.year, _selected.month);
  });

  Future<void> _reschedule(PlanTask t) async {
    final store = context.read<PlanStore>();
    final d = await pickDate(context, t.dueDate);
    if (d == null || !mounted) return;
    await runPlanAction(context, () => store.rescheduleTask(t, d));
    if (mounted) showPlanSnack(context, 'Moved to ${PlanFormat(store.prefs).date(d)}');
  }

  Future<void> _filters() async {
    final store = context.read<PlanStore>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => StatefulBuilder(
        builder: (context, set) {
          void both(VoidCallback f) {
            set(f);
            setState(() {});
          }

          return OmniBottomSheetScaffold(
            title: 'Calendar filters',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.allowProjectFilter)
                  OmniTapField(
                    label: 'Project',
                    value: store.project(_projectFilter)?.name ?? 'All projects',
                    icon: Icons.folder_outlined,
                    onTap: () async {
                      final p = await pickOption<String>(
                        context,
                        title: 'Project',
                        icon: Icons.folder_outlined,
                        noneLabel: 'All projects',
                        current: _projectFilter,
                        options: [for (final p in store.projects) (p.id, p.name)],
                      );
                      if (p != null) both(() => _projectFilter = p.value);
                    },
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Priority?>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Any priority')),
                    for (final p in Priority.values) DropdownMenuItem(value: p, child: Text(p.label)),
                  ],
                  onChanged: (v) => both(() => _priority = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show completed tasks'),
                  value: _showDone,
                  onChanged: (v) => both(() => _showDone = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show milestones'),
                  value: _showMilestones,
                  onChanged: (v) => both(() => _showMilestones = v),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final mode = _mode(store.prefs);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final filtered = _projectFilter != null || _showDone || !_showMilestones || _priority != null;

    String title;
    switch (mode) {
      case CalendarViewMode.month:
        title = PlanFormat.monthYear(_month);
      case CalendarViewMode.week:
        final start = _weekStart(_selected, store.prefs.weekStart);
        title = '${PlanFormat.dayMonth(start)} – ${PlanFormat.dayMonth(start.add(const Duration(days: 6)))}';
      case CalendarViewMode.day:
        title = '${PlanFormat.weekdayShort(_selected)}, ${fmt.date(_selected)}';
      case CalendarViewMode.agenda:
        title = 'From ${fmt.relativeDay(_selected)}';
    }

    final header = [
      Padding(
        padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 0),
        child: OmniSegmented<CalendarViewMode>(
          options: [for (final m in CalendarViewMode.values) OmniOption(m, m.label)],
          value: mode,
          onChanged: (m) => setState(() => _modeOverride = m),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(
          children: [
            IconButton(tooltip: 'Previous', onPressed: () => _move(-1, mode), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
              child: Text(title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(tooltip: 'Next', onPressed: () => _move(1, mode), icon: const Icon(Icons.chevron_right_rounded)),
            TextButton(onPressed: _today, child: const Text('Today')),
            IconButton(
              tooltip: 'Filters',
              onPressed: _filters,
              icon: Badge(isLabelVisible: filtered, smallSize: 8, child: const Icon(Icons.tune_rounded)),
            ),
          ],
        ),
      ),
    ];

    final dayList = _DayList(
      day: _selected,
      tasks: _tasksOn(store, _selected),
      milestones: _milestonesOn(store, _selected),
      onReschedule: _reschedule,
      onAdd: () => newTask(context, dueDate: _selected, projectId: _project),
      showProject: widget.projectId == null,
    );

    switch (mode) {
      case CalendarViewMode.month:
        return ListView(
          padding: EdgeInsets.only(bottom: 24 + bottom),
          children: [
            ...header,
            _MonthGrid(
              month: _month,
              selected: _selected,
              weekStart: store.prefs.weekStart,
              countFor: (d) => _tasksOn(store, d).length,
              hasMilestone: (d) => _milestonesOn(store, d).isNotEmpty,
              hasOverdue: (d) => _tasksOn(store, d).any((t) => t.isOverdue(DateTime.now())),
              onSelect: (d) => setState(() => _selected = d),
            ),
            const Divider(height: 24),
            dayList,
          ],
        );
      case CalendarViewMode.week:
        final start = _weekStart(_selected, store.prefs.weekStart);
        return ListView(
          padding: EdgeInsets.only(bottom: 24 + bottom),
          children: [
            ...header,
            for (var i = 0; i < 7; i++)
              _WeekDay(
                day: start.add(Duration(days: i)),
                tasks: _tasksOn(store, start.add(Duration(days: i))),
                milestones: _milestonesOn(store, start.add(Duration(days: i))),
                showProject: widget.projectId == null,
                onReschedule: _reschedule,
                onAdd: () => newTask(context, dueDate: start.add(Duration(days: i)), projectId: _project),
              ),
          ],
        );
      case CalendarViewMode.day:
        return ListView(padding: EdgeInsets.only(bottom: 24 + bottom), children: [...header, dayList]);
      case CalendarViewMode.agenda:
        final days = [for (var i = 0; i < 30; i++) _selected.add(Duration(days: i))];
        final rows = <Widget>[];
        for (final d in days) {
          final tasks = _tasksOn(store, d);
          final ms = _milestonesOn(store, d);
          if (tasks.isEmpty && ms.isEmpty) continue;
          rows.add(GroupHeader('${fmt.relativeDay(d)} · ${PlanFormat.weekdayShort(d)} ${PlanFormat.dayMonth(d)}'));
          for (final m in ms) {
            rows.add(MilestoneRow(milestone: m, showProject: widget.projectId == null, onTap: () => openMilestone(context, m)));
          }
          for (final t in tasks) {
            rows.add(_CalendarTask(task: t, showProject: widget.projectId == null, onReschedule: _reschedule));
          }
        }
        return ListView(
          padding: EdgeInsets.only(bottom: 24 + bottom),
          children: [
            ...header,
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: OmniEmptyState(
                  icon: Icons.event_available_rounded,
                  title: 'Nothing in the next 30 days',
                  message: 'Tasks with a due date appear here.',
                ),
              )
            else
              ...rows,
          ],
        );
    }
  }

  static DateTime _weekStart(DateTime d, int weekStart) {
    final offset = (d.weekday - weekStart + 7) % 7;
    return DateTime(d.year, d.month, d.day - offset);
  }

}

/// The calendar's own view modes, opened on the Settings default.
enum CalendarViewMode {
  month('Month'),
  week('Week'),
  day('Day'),
  agenda('Agenda');

  final String label;
  const CalendarViewMode(this.label);

  static CalendarViewMode fromPref(CalendarView v) => CalendarViewMode.values.firstWhere((m) => m.name == v.name);
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final int weekStart;
  final int Function(DateTime) countFor;
  final bool Function(DateTime) hasMilestone;
  final bool Function(DateTime) hasOverdue;
  final ValueChanged<DateTime> onSelect;

  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.weekStart,
    required this.countFor,
    required this.hasMilestone,
    required this.hasOverdue,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = DateTime(month.year, month.month, 1);
    final offset = (first.weekday - weekStart + 7) % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((offset + daysInMonth) / 7).ceil() * 7;
    final today = dateOnly(DateTime.now());
    final names = [for (var i = 0; i < 7; i++) PlanFormat.weekdayShort(DateTime(2024, 1, weekStart == 7 ? 7 + i : 1 + i))];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset - 4),
      child: Column(
        children: [
          Row(
            children: [
              for (final n in names)
                Expanded(child: Center(child: Text(n.substring(0, 2), style: theme.textTheme.labelSmall))),
            ],
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.95),
            itemBuilder: (context, i) {
              final dayNum = i - offset + 1;
              if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox.shrink();
              final d = DateTime(month.year, month.month, dayNum);
              final isSel = d == selected;
              final isToday = d == today;
              final count = countFor(d);
              final ms = hasMilestone(d);
              final late = hasOverdue(d);
              return Semantics(
                button: true,
                selected: isSel,
                label: '${PlanFormat.dayMonth(d)}, $count tasks${ms ? ', milestone' : ''}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelect(d),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSel ? theme.colorScheme.primary : null,
                      borderRadius: BorderRadius.circular(12),
                      border: isToday && !isSel ? Border.all(color: theme.colorScheme.primary) : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$dayNum',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isToday || isSel ? FontWeight.w700 : FontWeight.w500,
                            color: isSel ? Colors.white : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (count > 0)
                              Text(
                                count > 9 ? '9+' : '$count',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: isSel ? Colors.white : (late ? theme.colorScheme.error : theme.colorScheme.primary),
                                ),
                              ),
                            if (ms)
                              Icon(Icons.flag_rounded, size: 10, color: isSel ? Colors.white : OmniDesignTokens.categoryNfc),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  final DateTime day;
  final List<PlanTask> tasks;
  final List<Milestone> milestones;
  final ValueChanged<PlanTask> onReschedule;
  final VoidCallback onAdd;
  final bool showProject;

  const _DayList({
    required this.day,
    required this.tasks,
    required this.milestones,
    required this.onReschedule,
    required this.onAdd,
    required this.showProject,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.read<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
          child: OmniSectionHeader(title: fmt.relativeDay(day), actionLabel: 'Add task', onAction: onAdd),
        ),
        for (final m in milestones)
          MilestoneRow(milestone: m, showProject: showProject, onTap: () => openMilestone(context, m)),
        for (final t in tasks) _CalendarTask(task: t, showProject: showProject, onReschedule: onReschedule),
        if (tasks.isEmpty && milestones.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 4, OmniDesignTokens.pageInset, 0),
            child: Text('Nothing planned for this day.', style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _WeekDay extends StatelessWidget {
  final DateTime day;
  final List<PlanTask> tasks;
  final List<Milestone> milestones;
  final bool showProject;
  final ValueChanged<PlanTask> onReschedule;
  final VoidCallback onAdd;

  const _WeekDay({
    required this.day,
    required this.tasks,
    required this.milestones,
    required this.showProject,
    required this.onReschedule,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = PlanFormat(context.read<PlanStore>().prefs);
    final isToday = dateOnly(DateTime.now()) == day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupHeader(
          '${isToday ? 'Today · ' : ''}${PlanFormat.weekdayShort(day)} ${PlanFormat.dayMonth(day)}',
          count: tasks.length,
          trailing: IconButton(
            tooltip: 'Add task on ${fmt.date(day)}',
            visualDensity: VisualDensity.compact,
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 20),
          ),
        ),
        for (final m in milestones) MilestoneRow(milestone: m, showProject: showProject, onTap: () => openMilestone(context, m)),
        for (final t in tasks) _CalendarTask(task: t, showProject: showProject, onReschedule: onReschedule),
      ],
    );
  }
}

class _CalendarTask extends StatelessWidget {
  final PlanTask task;
  final bool showProject;
  final ValueChanged<PlanTask> onReschedule;

  const _CalendarTask({required this.task, required this.showProject, required this.onReschedule});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: () => onReschedule(task),
    child: TaskRow(
      task: task,
      showProject: showProject,
      onTap: () => openTask(context, task),
      trailing: IconButton(
        tooltip: 'Move to another day',
        visualDensity: VisualDensity.compact,
        onPressed: () => onReschedule(task),
        icon: const Icon(Icons.event_repeat_rounded, size: 20),
      ),
    ),
  );
}

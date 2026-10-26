import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/app/shell/shell_controller.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_form_kit.dart';
import 'package:omni_plan/core/widgets/omni_glow_border.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/preferences.dart';
import 'package:omni_plan/domain/rules.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/tasks/task_views.dart';
import 'package:provider/provider.dart';

/// My Tasks: every task, with quick filters, search, advanced filters and
/// sorting, shown as a list, a board or an agenda. The view opens on the
/// default chosen in Settings.
class TasksTab extends StatefulWidget {
  const TasksTab({super.key});

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> {
  final TextEditingController _search = TextEditingController();
  TaskFilter _filter = const TaskFilter();
  TaskView? _view;
  late final ShellController _shell;

  @override
  void initState() {
    super.initState();
    _shell = context.read<ShellController>();
    _shell.addListener(_takeFilter);
    _takeFilter();
  }

  void _takeFilter() {
    final f = _shell.takeTaskFilter();
    if (f != null && mounted) {
      setState(() => _filter = _filter.copyWith(quick: f));
    }
  }

  @override
  void dispose() {
    _shell.removeListener(_takeFilter);
    _search.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final next = await showTaskFilterSheet(context, _filter);
    if (next != null) setState(() => _filter = next);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final view = _view ?? store.prefs.defaultTaskView;
    final tasks = store.filterTasks(_filter);
    final openCount = store.tasks.where((t) => !t.isDone && !t.isSubtask).length;
    final bottom = MediaQuery.paddingOf(context).bottom;

    final header = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 0),
        child: OmniPageTitle(
          title: 'My Tasks',
          subtitle: openCount == 1 ? '1 open task' : '$openCount open tasks',
          trailing: IconButton(
            tooltip: 'Calendar',
            onPressed: () => openCalendar(context),
            icon: const Icon(Icons.calendar_month_rounded, color: OmniDesignTokens.primary),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 16, OmniDesignTokens.pageInset, 12),
        child: OmniGlowBorder(
          child: OmniSearchField(
            controller: _search,
            hintText: 'Search tasks...',
            hasActiveFilter: _filter.hasAdvanced,
            onFilter: _openFilters,
            onChanged: (v) => setState(() => _filter = _filter.copyWith(query: v)),
            onClear: _filter.query.isEmpty
                ? null
                : () {
                    _search.clear();
                    setState(() => _filter = _filter.copyWith(query: ''));
                  },
          ),
        ),
      ),
      OmniFilterChips<TaskQuick>(
        items: [for (final q in TaskQuick.values) (value: q, label: q.label, icon: null)],
        selected: _filter.quick,
        onSelected: (q) => setState(() => _filter = _filter.copyWith(quick: q)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 12, OmniDesignTokens.pageInset, 4),
        child: OmniSegmented<TaskView>(
          options: const [
            OmniOption(TaskView.list, 'List', icon: Icons.view_list_rounded),
            OmniOption(TaskView.board, 'Board', icon: Icons.view_kanban_rounded),
            OmniOption(TaskView.agenda, 'Agenda', icon: Icons.view_agenda_rounded),
          ],
          value: view,
          onChanged: (v) => setState(() => _view = v),
        ),
      ),
      if (_filter.hasAdvanced)
        Padding(
          padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 4, OmniDesignTokens.pageInset - 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${tasks.length} shown · filters on · ${_filter.sort.label}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _filter = _filter.cleared()),
                child: const Text('Clear filters'),
              ),
            ],
          ),
        ),
    ];

    final empty = OmniEmptyState(
      icon: _filter.quick == TaskQuick.completed ? Icons.task_alt_rounded : Icons.checklist_rounded,
      title: _emptyTitle(),
      message: store.tasks.isEmpty
          ? 'Add your first task. Only a title is needed.'
          : 'Change the filter or add a task.',
      actionLabel: 'New task',
      onAction: () => newTask(
        context,
        dueDate: _filter.quick == TaskQuick.today ? DateTime.now() : null,
      ),
    );

    if (view == TaskView.board) {
      return Column(
        children: [
          ...header,
          Expanded(
            child: TaskBoard(
              // The board shows every status, so the "All" filter's rule of
              // hiding done tasks does not apply here.
              tasks: _filter.quick == TaskQuick.all
                  ? store.filterTasks(_filter.copyWith(statuses: TaskStatus.values.toSet()))
                  : tasks,
              onAdd: (status) async {
                final created = await newTask(context);
                if (created != null && created.status != status && context.mounted) {
                  await store.setTaskStatus(created, status);
                }
              },
            ),
          ),
        ],
      );
    }

    final rows = tasks.isEmpty
        ? <Widget>[Padding(padding: const EdgeInsets.only(top: 24), child: empty)]
        : view == TaskView.agenda
        ? agendaTaskRows(context, tasks)
        : (_filter.sort == TaskSort.smart && _filter.quick == TaskQuick.all)
        ? dueGroupedTaskRows(context, tasks)
        : [
            const SizedBox(height: 6),
            for (final t in tasks) TaskRow(task: t, onTap: () => openTask(context, t)),
          ];

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: 96 + bottom),
      children: [...header, ...rows],
    );
  }

  String _emptyTitle() {
    switch (_filter.quick) {
      case TaskQuick.today:
        return 'Nothing due today';
      case TaskQuick.upcoming:
        return 'Nothing in the next 7 days';
      case TaskQuick.overdue:
        return 'Nothing overdue';
      case TaskQuick.completed:
        return 'No completed tasks yet';
      case TaskQuick.noDate:
        return 'Every task has a date';
      case TaskQuick.inbox:
        return 'No tasks outside projects';
      case TaskQuick.all:
        return _filter.query.isEmpty && !_filter.hasAdvanced ? 'No open tasks' : 'No matching tasks';
    }
  }
}

/// Projects, priorities, statuses, tags, sorting and subtasks. Returns the
/// new filter, or null when dismissed.
Future<TaskFilter?> showTaskFilterSheet(BuildContext context, TaskFilter current) {
  return showModalBottomSheet<TaskFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FilterSheet(initial: current),
  );
}

class _FilterSheet extends StatefulWidget {
  final TaskFilter initial;
  const _FilterSheet({required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late TaskFilter _f = widget.initial;

  Set<T> _toggle<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final tags = store.allTags.toList()..sort();
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(t, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
    return OmniBottomSheetScaffold(
      title: 'Filter and sort',
      child: Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label('Sort by'),
                    DropdownButtonFormField<TaskSort>(
                      initialValue: _f.sort,
                      isExpanded: true,
                      items: [for (final s in TaskSort.values) DropdownMenuItem(value: s, child: Text(s.label))],
                      onChanged: (v) => setState(() => _f = _f.copyWith(sort: v)),
                    ),
                    label('Project'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('No project'),
                          selected: _f.projectIds.contains(''),
                          onSelected: (_) => setState(() => _f = _f.copyWith(projectIds: _toggle(_f.projectIds, ''))),
                        ),
                        for (final p in store.projects)
                          FilterChip(
                            label: Text(p.name),
                            selected: _f.projectIds.contains(p.id),
                            onSelected: (_) => setState(() => _f = _f.copyWith(projectIds: _toggle(_f.projectIds, p.id))),
                          ),
                      ],
                    ),
                    label('Priority'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in Priority.values)
                          FilterChip(
                            label: Text(p.label),
                            selected: _f.priorities.contains(p),
                            onSelected: (_) => setState(() => _f = _f.copyWith(priorities: _toggle(_f.priorities, p))),
                          ),
                      ],
                    ),
                    label('Status'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in TaskStatus.values)
                          FilterChip(
                            label: Text(s.label),
                            selected: _f.statuses.contains(s),
                            onSelected: (_) => setState(() => _f = _f.copyWith(statuses: _toggle(_f.statuses, s))),
                          ),
                      ],
                    ),
                    if (tags.isNotEmpty) ...[
                      label('Tags'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in tags)
                            FilterChip(
                              label: Text('#$t'),
                              selected: _f.tags.contains(t),
                              onSelected: (_) => setState(() => _f = _f.copyWith(tags: _toggle(_f.tags, t))),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show subtasks as their own rows'),
                      value: _f.showSubtasks,
                      onChanged: (v) => setState(() => _f = _f.copyWith(showSubtasks: v)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, _f.cleared()),
                      child: const Text('Clear'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _f),
                      child: const Text('Apply'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

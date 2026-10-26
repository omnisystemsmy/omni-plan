import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:provider/provider.dart';

// The three ways to look at the same task records. None of them copies a
// task: each groups the list it is given.

/// Tasks grouped by when they are due: Overdue, Today, Tomorrow, This week,
/// Later, No date, Completed.
List<Widget> dueGroupedTaskRows(BuildContext context, List<PlanTask> tasks, {bool showProject = true}) {
  final now = DateTime.now();
  final today = dateOnly(now);
  final groups = <String, List<PlanTask>>{
    'Overdue': [],
    'Today': [],
    'Tomorrow': [],
    'Next 7 days': [],
    'Later': [],
    'No date': [],
    'Completed': [],
  };
  for (final t in tasks) {
    final due = t.dueDate;
    String key;
    if (t.isDone) {
      key = 'Completed';
    } else if (t.isOverdue(now)) {
      key = 'Overdue';
    } else if (due == null) {
      key = 'No date';
    } else {
      final diff = dateOnly(due).difference(today).inDays;
      key = diff <= 0
          ? 'Today'
          : diff == 1
          ? 'Tomorrow'
          : diff <= 7
          ? 'Next 7 days'
          : 'Later';
    }
    groups[key]!.add(t);
  }
  return [
    for (final e in groups.entries)
      if (e.value.isNotEmpty) ...[
        GroupHeader(e.key, count: e.value.length),
        for (final t in e.value)
          TaskRow(task: t, showProject: showProject, onTap: () => openTask(context, t)),
      ],
  ];
}

/// Tasks by due date, one heading per day, for the agenda view.
List<Widget> agendaTaskRows(BuildContext context, List<PlanTask> tasks, {bool showProject = true}) {
  final store = context.read<PlanStore>();
  final fmt = PlanFormat(store.prefs);
  final dated = tasks.where((t) => t.dueDate != null).toList()
    ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  final undated = tasks.where((t) => t.dueDate == null).toList();
  final out = <Widget>[];
  DateTime? current;
  for (final t in dated) {
    final d = dateOnly(t.dueDate!);
    if (current == null || d != current) {
      current = d;
      out.add(GroupHeader('${fmt.relativeDay(d)} · ${PlanFormat.weekdayShort(d)} ${PlanFormat.dayMonth(d)}'));
    }
    out.add(TaskRow(task: t, showProject: showProject, onTap: () => openTask(context, t)));
  }
  if (undated.isNotEmpty) {
    out.add(GroupHeader('No date', count: undated.length));
    for (final t in undated) {
      out.add(TaskRow(task: t, showProject: showProject, onTap: () => openTask(context, t)));
    }
  }
  return out;
}

/// Status columns. A card moves with its menu (or a long press); the
/// board needs no drag and drop to be usable.
class TaskBoard extends StatelessWidget {
  final List<PlanTask> tasks;
  final bool showProject;

  /// Adds a task straight into a column ([TaskStatus]); null hides "Add".
  final void Function(TaskStatus status)? onAdd;

  const TaskBoard({super.key, required this.tasks, this.showProject = true, this.onAdd});

  @override
  Widget build(BuildContext context) {
    // The columns run down to the navigation bar; room for the centre button
    // is left inside each column's list instead of under the whole board.
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 12),
      children: [
        for (final status in TaskStatus.values)
          _BoardColumn(
            status: status,
            tasks: [for (final t in tasks) if (t.status == status) t],
            showProject: showProject,
            onAdd: onAdd == null || status == TaskStatus.done ? null : () => onAdd!(status),
          ),
      ],
    );
  }
}

class _BoardColumn extends StatelessWidget {
  final TaskStatus status;
  final List<PlanTask> tasks;
  final bool showProject;
  final VoidCallback? onAdd;

  const _BoardColumn({required this.status, required this.tasks, required this.showProject, this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = (MediaQuery.sizeOf(context).width * 0.78).clamp(240.0, 320.0);
    return Container(
      width: width,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? OmniDesignTokens.surfaceMuted
            : OmniDesignTokens.darkSurface,
        borderRadius: BorderRadius.circular(OmniDesignTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
            child: Row(
              children: [
                Icon(status.icon, size: 18, color: status.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${status.label} · ${tasks.length}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (onAdd != null)
                  IconButton(
                    tooltip: 'Add to ${status.label}',
                    visualDensity: VisualDensity.compact,
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded),
                  ),
              ],
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('No tasks', style: theme.textTheme.bodySmall),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 44),
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _BoardCard(task: tasks[i], showProject: showProject),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  final PlanTask task;
  final bool showProject;

  const _BoardCard({required this.task, required this.showProject});

  Future<void> _move(BuildContext context) async {
    final store = context.read<PlanStore>();
    final status = await showModalBottomSheet<TaskStatus>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => OmniBottomSheetScaffold(
        title: 'Move to',
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in TaskStatus.values)
              OmniMenuRow(
                icon: s.icon,
                iconColor: s.color,
                title: s.label,
                selected: s == task.status,
                trailing: s == task.status ? const Icon(Icons.check_rounded) : const SizedBox.shrink(),
                onTap: () => Navigator.pop(sheet, s),
              ),
          ],
        ),
      ),
    );
    if (status != null && context.mounted) {
      await runPlanAction(context, () => store.setTaskStatus(task, status));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final project = showProject ? store.project(task.projectId) : null;
    final overdue = task.isOverdue(DateTime.now());
    final blocked = store.isBlocked(task);
    return OmniSurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      onTap: () => openTask(context, task),
      semanticLabel: '${task.title}, ${task.status.label}',
      child: GestureDetector(
        onLongPress: () => _move(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: task.isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (task.priority != Priority.none) PriorityFlag(task.priority),
                      if (task.dueDate != null)
                        Text(
                          fmt.due(task),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: overdue ? theme.colorScheme.error : null,
                          ),
                        ),
                      if (project != null)
                        Text(project.name, style: theme.textTheme.bodySmall?.copyWith(color: project.colorValue)),
                      if (blocked)
                        const Icon(Icons.block_rounded, size: 14, color: OmniDesignTokens.accentAmber, semanticLabel: 'Waiting on another task'),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Move ${task.title}',
              visualDensity: VisualDensity.compact,
              onPressed: () => _move(context),
              icon: const Icon(Icons.more_vert_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

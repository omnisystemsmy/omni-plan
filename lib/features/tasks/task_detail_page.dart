import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_form_kit.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/rules.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/tasks/task_pickers.dart';
import 'package:provider/provider.dart';

/// Everything about one task, with its subtasks, checklist and
/// dependencies, and the actions on it.
class TaskDetailPage extends StatelessWidget {
  final String taskId;

  const TaskDetailPage({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final task = store.task(taskId);
    if (task == null) {
      return Scaffold(
        appBar: omniListAppBar(context, 'Task'),
        body: const OmniEmptyState(
          icon: Icons.search_off_rounded,
          title: 'This task no longer exists',
          message: 'It was deleted, or its project was deleted.',
        ),
      );
    }
    return _TaskDetail(task: task);
  }
}

enum _Action { duplicate, move, archive, restore, delete }

class _TaskDetail extends StatelessWidget {
  final PlanTask task;

  const _TaskDetail({required this.task});

  Future<void> _onAction(BuildContext context, _Action a) async {
    final store = context.read<PlanStore>();
    final navigator = Navigator.of(context);
    switch (a) {
      case _Action.duplicate:
        PlanTask? copy;
        final ok = await runPlanAction(context, () async => copy = await store.duplicateTask(task));
        if (ok && context.mounted) {
          showPlanSnack(context, 'Task duplicated');
          navigator.pushReplacement(MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: copy!.id)));
        }
      case _Action.move:
        final picked = await pickProject(context, task.projectId);
        if (picked == null || !context.mounted) return;
        await runPlanAction(
          context,
          () => store.saveTask(
            picked.value == null
                ? task.copyWith(clearProject: true, clearSection: true, clearMilestone: true, dependsOn: const [])
                : task.copyWith(
                    projectId: picked.value,
                    clearSection: true,
                    clearMilestone: true,
                    dependsOn: picked.value == task.projectId ? null : const [],
                  ),
          ),
        );
      case _Action.archive:
        final n = store.subtaskCount(task.id);
        if (await runPlanAction(context, () => store.archiveTask(task)) && context.mounted) {
          navigator.pop();
          showPlanSnack(
            context,
            n == 0 ? 'Task archived' : 'Task and $n subtasks archived',
            action: SnackBarAction(label: 'Undo', onPressed: () => store.restoreTask(task)),
          );
        }
      case _Action.restore:
        await runPlanAction(context, () => store.restoreTask(task));
      case _Action.delete:
        final n = store.subtaskCount(task.id);
        final ok = await confirmAction(
          context,
          title: 'Delete task?',
          message: n == 0
              ? '"${task.title}" will be deleted for good.'
              : '"${task.title}" and its $n subtasks will be deleted for good.',
          confirmLabel: 'Delete',
        );
        if (!ok || !context.mounted) return;
        if (await runPlanAction(context, () => store.deleteTask(task)) && context.mounted) {
          navigator.pop();
          showPlanSnack(context, 'Task deleted');
        }
    }
  }

  Future<void> _addDependency(BuildContext context) async {
    final store = context.read<PlanStore>();
    final candidates = [
      for (final t in store.tasksOfProject(task.projectId!))
        if (t.id != task.id && !task.dependsOn.contains(t.id) && t.parentId != task.id) t,
    ];
    if (candidates.isEmpty) {
      showPlanSnack(context, 'No other tasks in this project to depend on.');
      return;
    }
    final picked = await pickOption<String>(
      context,
      title: 'This task waits for',
      icon: Icons.link_rounded,
      current: null,
      options: [for (final t in candidates) (t.id, t.title)],
    );
    final id = picked?.value;
    if (id == null || !context.mounted) return;
    await runPlanAction(context, () => store.addDependency(task, store.task(id)!));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final project = store.project(task.projectId);
    final parent = store.task(task.parentId);
    final subtasks = store.subtasksOf(task.id);
    final subProgress = progressOf(subtasks);
    final waitsFor = [for (final id in task.dependsOn) if (store.task(id) != null) store.task(id)!];
    final blocking = store.dependents(task);
    final blocked = store.isBlocked(task);
    final overdue = task.isOverdue(DateTime.now());
    final bottom = MediaQuery.paddingOf(context).bottom;
    final timed = task.dueMinutes != null;

    Widget info(String label, String value, {VoidCallback? onTap, Color? color}) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(label, style: theme.textTheme.bodySmall)),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color ?? (onTap == null ? null : theme.colorScheme.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        centerTitle: true,
        title: Text(parent == null ? 'Task' : 'Subtask',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Edit task',
            onPressed: () => editTask(context, task),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<_Action>(
            tooltip: 'More options',
            onSelected: (a) => _onAction(context, a),
            itemBuilder: (_) => [
              const PopupMenuItem(value: _Action.duplicate, child: Text('Duplicate')),
              if (parent == null) const PopupMenuItem(value: _Action.move, child: Text('Move to project')),
              if (task.isArchived)
                const PopupMenuItem(value: _Action.restore, child: Text('Restore'))
              else
                const PopupMenuItem(value: _Action.archive, child: Text('Archive')),
              const PopupMenuItem(value: _Action.delete, child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: 24 + bottom),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 0),
            child: OmniSurfaceCard(
              padding: const EdgeInsets.fromLTRB(8, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TaskCheck(task: task, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            task.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              decoration: task.isDone ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        if (parent != null) ...[
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () => openTask(context, parent),
                            child: Text('Subtask of ${parent.title}',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OmniStatusPill(label: task.status.label, color: task.status.color, icon: task.status.icon),
                            if (task.priority != Priority.none)
                              OmniStatusPill(label: task.priority.label, color: task.priority.color, icon: Icons.flag_rounded),
                            if (overdue)
                              OmniStatusPill(label: 'Overdue', color: theme.colorScheme.error, icon: Icons.warning_amber_rounded),
                            if (blocked)
                              const OmniStatusPill(label: 'Waiting on another task', color: OmniDesignTokens.accentAmber, icon: Icons.block_rounded),
                            if (task.isArchived)
                              OmniStatusPill(label: 'Archived', color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 16, OmniDesignTokens.pageInset, 4),
            child: OmniSegmented<TaskStatus>(
              dense: true,
              options: [for (final s in TaskStatus.values) OmniOption(s, s.label)],
              value: task.status,
              onChanged: (s) => runPlanAction(context, () => store.setTaskStatus(task, s)),
            ),
          ),
          if (task.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 12, OmniDesignTokens.pageInset, 0),
              child: Text(task.description, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
            ),
          const SizedBox(height: 12),
          const OmniListSection(title: 'Details', children: []),
          info(
            'Project',
            project?.name ?? 'No project',
            onTap: project == null ? null : () => openProject(context, project),
          ),
          if (store.section(task.sectionId) != null) info('Section', store.section(task.sectionId)!.name),
          if (store.milestone(task.milestoneId) != null)
            info('Milestone', store.milestone(task.milestoneId)!.title,
                onTap: () => openMilestone(context, store.milestone(task.milestoneId)!)),
          info(
            'Due',
            task.dueDate == null ? 'No date' : '${fmt.date(task.dueDate!)}${timed ? ', ${fmt.time(task.dueMinutes!)}' : ''}',
            color: overdue ? theme.colorScheme.error : null,
          ),
          if (task.startDate != null) info('Start', fmt.date(task.startDate!)),
          if (task.dueDate != null) ...[
            info('Reminder', PlanFormat.reminderLabel(task.reminderMinutes, timed: timed)),
            info('Repeat', task.recurrence?.summary ?? 'Does not repeat'),
          ],
          if (task.estimateMinutes != null) info('Estimate', fmt.duration(task.estimateMinutes!)),
          if (task.tags.isNotEmpty) info('Tags', task.tags.map((t) => '#$t').join('  ')),
          if (task.completedAt != null) info('Completed', fmt.dateTime(task.completedAt!)),
          info('Created', fmt.dateTime(task.createdAt)),
          if (parent == null) ...[
            const SizedBox(height: OmniDesignTokens.sectionGap),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
              child: OmniSectionHeader(
                title: subtasks.isEmpty ? 'Subtasks' : 'Subtasks · ${subProgress.done}/${subProgress.total}',
                actionLabel: 'Add',
                onAction: () => newTask(context, parentId: task.id, projectId: task.projectId, sectionId: task.sectionId),
              ),
            ),
            if (subtasks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 4, OmniDesignTokens.pageInset, 4),
                child: OmniProgressBar(fraction: subProgress.fraction),
              ),
            if (subtasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
                child: Text('Break this task into smaller steps.', style: theme.textTheme.bodySmall),
              ),
            for (final s in subtasks) TaskRow(task: s, showProject: false, dense: true, onTap: () => openTask(context, s)),
          ],
          if (task.checklist.isNotEmpty) ...[
            const SizedBox(height: OmniDesignTokens.sectionGap),
            OmniListSection(
              title: 'Checklist · ${task.checklistDone}/${task.checklist.length}',
              children: [
                for (final c in task.checklist)
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset - 4),
                    value: c.done,
                    title: Text(
                      c.title,
                      style: TextStyle(decoration: c.done ? TextDecoration.lineThrough : null),
                    ),
                    onChanged: (_) => store.toggleChecklistItem(task, c.id),
                  ),
              ],
            ),
          ],
          if (project != null && parent == null) ...[
            const SizedBox(height: OmniDesignTokens.sectionGap),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
              child: OmniSectionHeader(title: 'Dependencies', actionLabel: 'Add', onAction: () => _addDependency(context)),
            ),
            if (waitsFor.isEmpty && blocking.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
                child: Text(
                  'Link tasks that must be finished before this one can start.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (waitsFor.isNotEmpty) const GroupHeader('Waits for'),
            for (final d in waitsFor)
              TaskRow(
                task: d,
                showProject: false,
                dense: true,
                onTap: () => openTask(context, d),
                trailing: IconButton(
                  tooltip: 'Remove dependency',
                  onPressed: () => store.removeDependency(task, d.id),
                  icon: const Icon(Icons.link_off_rounded, size: 20),
                ),
              ),
            if (blocking.isNotEmpty) const GroupHeader('Blocking'),
            for (final d in blocking)
              TaskRow(task: d, showProject: false, dense: true, onTap: () => openTask(context, d)),
          ],
          if (task.notes.isNotEmpty) ...[
            const SizedBox(height: OmniDesignTokens.sectionGap),
            const OmniListSection(title: 'Notes and links', children: []),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
              child: SelectableText(task.notes, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
            ),
          ],
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 12 + bottom),
        child: SizedBox(
          height: 52,
          child: task.isDone
              ? OutlinedButton.icon(
                  onPressed: () => store.setTaskDone(task, false),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Reopen task'),
                )
              : FilledButton.icon(
                  onPressed: () async {
                    final next = await store.setTaskDone(task, true);
                    if (next != null && context.mounted) {
                      showPlanSnack(context, 'Done. The next one is due ${fmt.relativeDay(next.dueDate!)}.');
                    }
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Mark complete'),
                ),
        ),
      ),
    );
  }
}

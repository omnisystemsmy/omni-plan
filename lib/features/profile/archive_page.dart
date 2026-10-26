import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:provider/provider.dart';

/// Archived projects, tasks and goals: restore them, or delete them for
/// good. Archiving never deletes anything.
class ArchivePage extends StatelessWidget {
  const ArchivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final projects = store.archivedProjects;
    final tasks = store.archivedTasks;
    final goals = store.archivedGoals;

    Widget actions({required VoidCallback restore, required VoidCallback delete}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: 'Restore', onPressed: restore, icon: const Icon(Icons.unarchive_outlined)),
        IconButton(tooltip: 'Delete for good', onPressed: delete, icon: const Icon(Icons.delete_outline_rounded)),
      ],
    );

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Archive'),
          bottom: TabBar(tabs: [
            Tab(text: 'Projects (${projects.length})'),
            Tab(text: 'Tasks (${tasks.length})'),
            Tab(text: 'Goals (${goals.length})'),
          ]),
        ),
        body: TabBarView(
          children: [
            projects.isEmpty
                ? const OmniEmptyState(icon: Icons.archive_outlined, title: 'No archived projects', message: 'Projects you archive are kept here with their tasks.')
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final p in projects)
                        OmniMenuRow(
                          icon: p.iconData,
                          iconColor: p.colorValue,
                          useTile: true,
                          title: p.name,
                          subtitle: 'Archived ${fmt.date(p.archivedAt!)} · ${store.tasksOfProject(p.id).length} tasks',
                          onTap: () => openProject(context, p),
                          trailing: actions(
                            restore: () async {
                              await store.restoreProject(p);
                              if (context.mounted) showPlanSnack(context, '${p.name} restored');
                            },
                            delete: () async {
                              final ok = await confirmAction(
                                context,
                                title: 'Delete project for good?',
                                message: '"${p.name}" and all its tasks, sections and milestones are deleted. This cannot be undone.',
                                confirmLabel: 'Delete',
                              );
                              if (ok) await store.deleteProject(p, ProjectDeleteMode.deleteTasks);
                            },
                          ),
                        ),
                    ],
                  ),
            tasks.isEmpty
                ? const OmniEmptyState(icon: Icons.archive_outlined, title: 'No archived tasks', message: 'Tasks you archive are kept here with their subtasks.')
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final t in tasks)
                        OmniMenuRow(
                          icon: t.isDone ? Icons.task_alt_rounded : Icons.radio_button_unchecked_rounded,
                          useTile: true,
                          title: t.title,
                          subtitle: [
                            store.project(t.projectId)?.name ?? 'No project',
                            'archived ${fmt.date(t.archivedAt!)}',
                          ].join(' · '),
                          onTap: () => openTask(context, t),
                          trailing: actions(
                            restore: () async {
                              await store.restoreTask(t);
                              if (context.mounted) showPlanSnack(context, 'Task restored');
                            },
                            delete: () async {
                              final ok = await confirmAction(
                                context,
                                title: 'Delete task for good?',
                                message: '"${t.title}" and its subtasks are deleted. This cannot be undone.',
                                confirmLabel: 'Delete',
                              );
                              if (ok) await store.deleteTask(t);
                            },
                          ),
                        ),
                    ],
                  ),
            goals.isEmpty
                ? const OmniEmptyState(icon: Icons.archive_outlined, title: 'No archived goals', message: 'Goals you archive are kept here.')
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final g in goals)
                        OmniMenuRow(
                          icon: Icons.flag_rounded,
                          useTile: true,
                          title: g.title,
                          subtitle: g.status.label,
                          onTap: () => openGoal(context, g),
                          trailing: actions(
                            restore: () => store.setGoalArchived(g, false),
                            delete: () async {
                              final ok = await confirmAction(
                                context,
                                title: 'Delete goal for good?',
                                message: '"${g.title}" is deleted. Linked projects are kept.',
                                confirmLabel: 'Delete',
                              );
                              if (ok) await store.deleteGoal(g);
                            },
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

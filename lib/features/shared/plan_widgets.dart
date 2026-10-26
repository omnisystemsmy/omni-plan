import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/rules.dart';
import 'package:provider/provider.dart';

// Planning pieces built only from the Omni Docs components and tokens: the
// row is the Docs flat list row with a completion circle in front, the card
// is OmniSurfaceCard with OmniIconTile, the chips are OmniStatusPill.

void showPlanSnack(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

/// Runs a store change and shows its error, if any, in a snackbar. Returns
/// whether it succeeded.
Future<bool> runPlanAction(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on PlanStoreException catch (e) {
    if (context.mounted) showPlanSnack(context, e.message);
  } catch (e) {
    if (context.mounted) showPlanSnack(context, 'Something went wrong: $e');
  }
  return false;
}

/// The standard confirmation before anything that cannot be undone.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final theme = Theme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(d, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Rounded progress bar in the brand colour.
class OmniProgressBar extends StatelessWidget {
  final double? fraction;
  final Color? color;
  final double height;

  const OmniProgressBar({super.key, required this.fraction, this.color, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(OmniDesignTokens.radiusPill),
      child: LinearProgressIndicator(
        value: fraction ?? 0,
        minHeight: height,
        color: c,
        backgroundColor: c.withValues(alpha: 0.14),
      ),
    );
  }
}

/// A small coloured flag for priorities above "none".
class PriorityFlag extends StatelessWidget {
  final Priority priority;
  final double size;

  const PriorityFlag(this.priority, {super.key, this.size = 15});

  @override
  Widget build(BuildContext context) {
    if (priority == Priority.none) return const SizedBox.shrink();
    return Icon(
      Icons.flag_rounded,
      size: size,
      color: priority.color,
      semanticLabel: '${priority.label} priority',
    );
  }
}

/// The circle in front of a task: tap to complete or reopen.
class TaskCheck extends StatelessWidget {
  final PlanTask task;
  final double size;

  const TaskCheck({super.key, required this.task, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = task.isDone;
    final color = done ? OmniDesignTokens.success : (task.priority == Priority.none ? theme.colorScheme.onSurfaceVariant : task.priority.color);
    return Semantics(
      checked: done,
      button: true,
      label: done ? 'Reopen ${task.title}' : 'Complete ${task.title}',
      child: InkResponse(
        radius: 22,
        onTap: () async {
          HapticFeedback.lightImpact();
          final store = context.read<PlanStore>();
          final messenger = ScaffoldMessenger.of(context);
          final next = await store.setTaskDone(task, !done);
          if (next != null) {
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text('Next "${task.title}" added for ${PlanFormat(store.prefs).relativeDay(next.dueDate!)}')),
              );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AnimatedContainer(
            duration: OmniDesignTokens.mediumMotion,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? OmniDesignTokens.success : Colors.transparent,
              border: Border.all(color: color, width: 2),
            ),
            child: done ? Icon(Icons.check_rounded, size: size - 8, color: Colors.white) : null,
          ),
        ),
      ),
    );
  }
}

/// One task in a list: completion circle, title, and only the details that
/// apply (due, project, subtasks, checklist, repeat, reminder, blocked).
class TaskRow extends StatelessWidget {
  final PlanTask task;
  final VoidCallback onTap;
  final bool showProject;
  final bool dense;
  final Widget? trailing;

  const TaskRow({
    super.key,
    required this.task,
    required this.onTap,
    this.showProject = true,
    this.dense = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final now = DateTime.now();
    final overdue = task.isOverdue(now);
    final project = showProject ? store.project(task.projectId) : null;
    final subs = store.subtasksOf(task.id);
    final blocked = store.isBlocked(task);
    final muted = theme.colorScheme.onSurfaceVariant;
    final metaStyle = theme.textTheme.bodySmall?.copyWith(color: muted);

    final meta = <Widget>[
      if (task.dueDate != null)
        _Meta(
          icon: Icons.event_rounded,
          text: fmt.due(task, now: now),
          color: overdue ? theme.colorScheme.error : null,
        ),
      if (project != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: project.colorValue, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle),
            ),
          ],
        ),
      if (subs.isNotEmpty)
        _Meta(
          icon: Icons.account_tree_outlined,
          text: '${subs.where((s) => s.isDone).length}/${subs.length}',
        ),
      if (task.checklist.isNotEmpty)
        _Meta(icon: Icons.checklist_rounded, text: '${task.checklistDone}/${task.checklist.length}'),
      if (task.status == TaskStatus.inProgress || task.status == TaskStatus.onHold)
        _Meta(icon: task.status.icon, text: task.status.label, color: task.status.color),
      if (blocked) _Meta(icon: Icons.block_rounded, text: 'Waiting', color: OmniDesignTokens.accentAmber),
      if (task.recurrence != null) const _Meta(icon: Icons.repeat_rounded),
      if (task.reminderMinutes != null && task.dueDate != null) const _Meta(icon: Icons.alarm_rounded),
    ];

    return Semantics(
      button: true,
      label: task.title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset - 6, dense ? 4 : 8, OmniDesignTokens.pageInset, dense ? 4 : 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TaskCheck(task: task),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: task.isDone ? TextDecoration.lineThrough : null,
                                  color: task.isDone ? muted : null,
                                ),
                              ),
                            ),
                            if (!task.isDone) PriorityFlag(task.priority),
                          ],
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Wrap(spacing: 10, runSpacing: 2, children: meta),
                        ],
                      ],
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String? text;
  final Color? color;

  const _Meta({required this.icon, this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        if (text != null) ...[
          const SizedBox(width: 3),
          Text(text!, style: theme.textTheme.bodySmall?.copyWith(color: c)),
        ],
      ],
    );
  }
}

/// A project summary: icon, name, status, progress, tasks, target date and
/// next milestone. [grid] lays it out for a two-column grid.
class ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  final bool grid;

  const ProjectCard({super.key, required this.project, required this.onTap, this.grid = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final progress = store.projectProgress(project.id);
    final next = store.nextMilestone(project.id);
    final overdue = store.overdueCountOf(project.id);
    final due = project.dueDate;
    final late = due != null && project.status.isActive && dateOnly(due).isBefore(dateOnly(DateTime.now()));

    final status = OmniStatusPill(
      label: project.isArchived ? 'Archived' : project.status.label,
      color: project.isArchived ? theme.colorScheme.onSurfaceVariant : project.status.color,
    );
    final progressBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                progress.label,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (progress.percent != null)
              Text(
                '${progress.percent}%',
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
          ],
        ),
        const SizedBox(height: 6),
        OmniProgressBar(fraction: progress.fraction, color: project.colorValue),
      ],
    );
    final details = <Widget>[
      if (due != null)
        _Meta(icon: Icons.event_rounded, text: fmt.date(due), color: late ? theme.colorScheme.error : null),
      if (overdue > 0) _Meta(icon: Icons.warning_amber_rounded, text: '$overdue overdue', color: theme.colorScheme.error),
      if (next != null && !grid) _Meta(icon: Icons.flag_rounded, text: next.title),
    ];

    return OmniSurfaceCard(
      onTap: onTap,
      semanticLabel: '${project.name}, ${project.status.label}, ${progress.label}',
      padding: const EdgeInsets.all(14),
      child: grid
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    OmniIconTile(icon: project.iconData, color: project.colorValue, size: 40, iconSize: 20),
                    const Spacer(),
                    if (project.favorite) const Icon(Icons.star_rounded, size: 18, color: OmniDesignTokens.accentAmber),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  project.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                status,
                const Spacer(),
                progressBlock,
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 2, children: details),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    OmniIconTile(icon: project.iconData, color: project.colorValue, size: 44, iconSize: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  project.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (project.favorite) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.star_rounded, size: 16, color: OmniDesignTokens.accentAmber),
                              ],
                            ],
                          ),
                          if (project.description.isNotEmpty)
                            Text(
                              project.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    status,
                  ],
                ),
                const SizedBox(height: 12),
                progressBlock,
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 12, runSpacing: 4, children: details),
                ],
              ],
            ),
    );
  }
}

/// A count with a label, used on Home and Reports. Opens [onTap].
class MetricCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OmniSurfaceCard(
      onTap: onTap,
      semanticLabel: '$label: $value',
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          OmniIconTile(icon: icon, color: color, size: 38, iconSize: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
                ),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A milestone line: flag, title, project, date and its state.
class MilestoneRow extends StatelessWidget {
  final Milestone milestone;
  final VoidCallback onTap;
  final bool showProject;

  const MilestoneRow({super.key, required this.milestone, required this.onTap, this.showProject = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final project = store.project(milestone.projectId);
    final overdue = milestone.isOverdue(DateTime.now());
    final linked = store.milestoneTaskProgress(milestone.id);
    final parts = [
      if (showProject && project != null) project.name,
      if (milestone.dueDate != null) fmt.relativeDay(milestone.dueDate!),
      if (linked.total > 0) linked.label,
    ];
    return OmniMenuRow(
      icon: milestone.isDone ? Icons.flag_circle_rounded : Icons.flag_rounded,
      iconColor: milestone.isDone
          ? OmniDesignTokens.success
          : overdue
          ? theme.colorScheme.error
          : (project?.colorValue ?? OmniDesignTokens.categoryNfc),
      useTile: true,
      title: milestone.title,
      subtitle: parts.isEmpty ? null : parts.join(' · '),
      onTap: onTap,
      trailing: milestone.isDone
          ? const OmniStatusPill(label: 'Reached', color: OmniDesignTokens.success)
          : overdue
          ? OmniStatusPill(label: 'Overdue', color: theme.colorScheme.error)
          : null,
    );
  }
}

/// Header line "Section name · 3" used inside grouped lists.
class GroupHeader extends StatelessWidget {
  final String title;
  final int? count;
  final Widget? trailing;

  const GroupHeader(this.title, {super.key, this.count, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 14, OmniDesignTokens.pageInset - 4, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == null ? title : '$title · $count',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Status filter progress summary: "3 of 8 done · 38%".
String progressSummary(Progress p) =>
    p.total == 0 ? 'No tasks yet' : '${p.label} · ${p.percent}%';

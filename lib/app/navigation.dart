import 'package:flutter/material.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/features/templates/template_library.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/calendar/calendar_page.dart';
import 'package:omni_plan/features/goals/goal_pages.dart';
import 'package:omni_plan/features/milestones/milestone_pages.dart';
import 'package:omni_plan/features/projects/project_detail_page.dart';
import 'package:omni_plan/features/projects/project_editor_page.dart';
import 'package:omni_plan/features/reports/reports_page.dart';
import 'package:omni_plan/features/tasks/task_detail_page.dart';
import 'package:omni_plan/features/tasks/task_editor_page.dart';
import 'package:omni_plan/features/templates/templates_page.dart';
import 'package:provider/provider.dart';

// One place for "open this record", so every list, search result and
// notification leads to the same screen.

Future<T?> _push<T>(BuildContext context, Widget page) =>
    Navigator.push<T>(context, MaterialPageRoute(builder: (_) => page));

Future<void> openTask(BuildContext context, PlanTask task) {
  context.read<PlanStore>().markTaskOpened(task);
  return _push(context, TaskDetailPage(taskId: task.id));
}

Future<void> openProject(BuildContext context, Project project, {int tab = 0}) {
  context.read<PlanStore>().markProjectOpened(project);
  return _push(context, ProjectDetailPage(projectId: project.id, initialTab: tab));
}

Future<void> openGoal(BuildContext context, Goal goal) =>
    _push(context, GoalDetailPage(goalId: goal.id));

Future<void> openMilestone(BuildContext context, Milestone m) =>
    _push(context, MilestoneDetailPage(milestoneId: m.id));

/// Opens what an activity entry or notification points at, when it still
/// exists. Returns false when it is gone.
bool openEntity(BuildContext context, EntityKind? kind, String? id) {
  final store = context.read<PlanStore>();
  switch (kind) {
    case EntityKind.task:
      final t = store.task(id);
      if (t == null) return false;
      openTask(context, t);
      return true;
    case EntityKind.project:
      final p = store.project(id);
      if (p == null) return false;
      openProject(context, p);
      return true;
    case EntityKind.milestone:
      final m = store.milestone(id);
      if (m == null) return false;
      openMilestone(context, m);
      return true;
    case EntityKind.goal:
      final g = store.goal(id);
      if (g == null) return false;
      openGoal(context, g);
      return true;
    case EntityKind.template:
    case EntityKind.backup:
    case null:
      return false;
  }
}

Future<PlanTask?> newTask(
  BuildContext context, {
  String? projectId,
  String? sectionId,
  String? parentId,
  String? milestoneId,
  DateTime? dueDate,
  bool recurring = false,
}) => _push<PlanTask>(
  context,
  TaskEditorPage(
    projectId: projectId,
    sectionId: sectionId,
    parentId: parentId,
    milestoneId: milestoneId,
    dueDate: dueDate,
    recurring: recurring,
  ),
);

Future<void> editTask(BuildContext context, PlanTask task) =>
    _push(context, TaskEditorPage(taskId: task.id));

/// "New project": asks whether to start from a blank project or from a
/// template. A template opens the library to browse and choose from; a blank
/// project opens the editor. Either way the new project ends up opened.
Future<void> newProject(BuildContext context) async {
  final fromTemplate = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheet) => OmniBottomSheetScaffold(
      title: 'New project',
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OmniMenuRow(
            icon: Icons.create_new_folder_rounded,
            iconColor: OmniDesignTokens.categoryConverters,
            useTile: true,
            title: 'Blank project',
            subtitle: 'Start empty and add your own tasks',
            onTap: () => Navigator.pop(sheet, false),
          ),
          OmniMenuRow(
            icon: Icons.dashboard_customize_rounded,
            iconColor: OmniDesignTokens.categoryBusiness,
            useTile: true,
            title: 'From a template',
            subtitle: 'Browse ${TemplateLibrary.templateCount} ready-made plans and pick one',
            onTap: () => Navigator.pop(sheet, true),
          ),
        ],
      ),
    ),
  );
  if (fromTemplate == null || !context.mounted) return;
  if (fromTemplate) {
    await openTemplates(context);
    return;
  }
  final created = await _push<Project>(context, const ProjectEditorPage());
  if (created != null && context.mounted) {
    await openProject(context, created);
  }
}

Future<void> editProject(BuildContext context, Project p) =>
    _push(context, ProjectEditorPage(projectId: p.id));

Future<void> newGoal(BuildContext context) async {
  final created = await _push<Goal>(context, const GoalEditorPage());
  if (created != null && context.mounted) await openGoal(context, created);
}

Future<void> newMilestone(BuildContext context, {String? projectId}) =>
    _push(context, MilestoneEditorPage(projectId: projectId));

Future<void> openTemplates(BuildContext context) =>
    _push(context, const TemplatesPage());

Future<void> openCalendar(BuildContext context, {String? projectId}) =>
    _push(context, CalendarPage(projectId: projectId));

Future<void> openReports(BuildContext context) => _push(context, const ReportsPage());

Future<void> openGoals(BuildContext context) => _push(context, const GoalsPage());

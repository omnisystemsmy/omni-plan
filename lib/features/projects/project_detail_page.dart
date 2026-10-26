import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/export_service.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/rules.dart';
import 'package:omni_plan/features/calendar/calendar_page.dart';
import 'package:omni_plan/features/pro/plan_service.dart';
import 'package:omni_plan/features/pro/pro_gate.dart';
import 'package:omni_plan/features/projects/timeline_view.dart';
import 'package:omni_plan/features/reports/charts.dart';
import 'package:omni_plan/features/reports/reports_page.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/shared/share_file.dart';
import 'package:omni_plan/features/tasks/task_views.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// The workspace of one project: overview, tasks by section, board,
/// calendar, timeline, milestones, notes and resources, and reports. All of
/// them show the same records.
class ProjectDetailPage extends StatelessWidget {
  final String projectId;
  final int initialTab;

  const ProjectDetailPage({super.key, required this.projectId, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    final project = context.watch<PlanStore>().project(projectId);
    if (project == null) {
      return Scaffold(
        appBar: omniListAppBar(context, 'Project'),
        body: const OmniEmptyState(
          icon: Icons.search_off_rounded,
          title: 'This project no longer exists',
          message: 'It may have been deleted.',
        ),
      );
    }
    return _ProjectWorkspace(project: project, initialTab: initialTab);
  }
}

enum _Menu { edit, favorite, duplicate, template, csv, pdf, archive, restore, delete }

class _ProjectWorkspace extends StatelessWidget {
  final Project project;
  final int initialTab;

  const _ProjectWorkspace({required this.project, required this.initialTab});

  static const tabs = ['Overview', 'Tasks', 'Board', 'Calendar', 'Timeline', 'Milestones', 'Notes', 'Reports'];

  Future<void> _menu(BuildContext context, _Menu m) async {
    final store = context.read<PlanStore>();
    final navigator = Navigator.of(context);
    switch (m) {
      case _Menu.edit:
        await editProject(context, project);
      case _Menu.favorite:
        await store.toggleFavoriteProject(project);
      case _Menu.duplicate:
        Project? copy;
        if (await runPlanAction(context, () async => copy = await store.duplicateProject(project)) && context.mounted) {
          showPlanSnack(context, 'Project duplicated');
          navigator.pushReplacement(MaterialPageRoute(builder: (_) => ProjectDetailPage(projectId: copy!.id)));
        }
      case _Menu.template:
        if (!await ProGate.ensure(context, ProCapability.customTemplates) || !context.mounted) return;
        final name = await _askName(context, project.name);
        if (name == null || !context.mounted) return;
        if (await runPlanAction(context, () => store.saveProjectAsTemplate(project, name: name)) && context.mounted) {
          showPlanSnack(context, 'Saved to My templates');
        }
      case _Menu.csv:
        if (!await ProGate.ensure(context, ProCapability.csvExport) || !context.mounted) return;
        await shareGeneratedFile(
          context,
          () => ExportService.writeCsv('${project.name} tasks', ExportService.tasksCsv(store, projectId: project.id)),
          mimeType: 'text/csv',
          doneMessage: 'Tasks exported',
        );
      case _Menu.pdf:
        if (!await ProGate.ensure(context, ProCapability.pdfReports) || !context.mounted) return;
        await shareGeneratedFile(
          context,
          () async => ExportService.writeFile(
            '${ExportService.safeName('${project.name} report')}.pdf',
            await ExportService.projectReportPdf(store, project),
          ),
          mimeType: 'application/pdf',
          doneMessage: 'Report shared',
        );
      case _Menu.archive:
        if (await runPlanAction(context, () => store.archiveProject(project)) && context.mounted) {
          navigator.pop();
          showPlanSnack(
            context,
            '${project.name} archived with its tasks',
            action: SnackBarAction(label: 'Undo', onPressed: () => store.restoreProject(project)),
          );
        }
      case _Menu.restore:
        await runPlanAction(context, () => store.restoreProject(project));
      case _Menu.delete:
        final count = store.tasksOfProject(project.id, includeArchived: true).length;
        final mode = await showDialog<ProjectDeleteMode>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Delete project?'),
            content: Text(
              count == 0
                  ? '"${project.name}", its sections and milestones will be deleted for good.'
                  : '"${project.name}" has $count ${count == 1 ? 'task' : 'tasks'}. Delete them too, or keep them as tasks without a project? Sections and milestones are deleted either way.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
              if (count > 0)
                TextButton(onPressed: () => Navigator.pop(d, ProjectDeleteMode.keepTasks), child: const Text('Keep tasks')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => Navigator.pop(d, ProjectDeleteMode.deleteTasks),
                child: Text(count == 0 ? 'Delete' : 'Delete all'),
              ),
            ],
          ),
        );
        if (mode == null || !context.mounted) return;
        if (await runPlanAction(context, () => store.deleteProject(project, mode)) && context.mounted) {
          navigator.pop();
          showPlanSnack(context, 'Project deleted');
        }
    }
  }

  static Future<String?> _askName(BuildContext context, String initial) async {
    final c = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Save as template'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Template name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialTab.clamp(0, tabs.length - 1),
      child: Scaffold(
        appBar: AppBar(
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          toolbarHeight: 64,
          centerTitle: true,
          title: Text(
            project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          actions: [
            PopupMenuButton<_Menu>(
              tooltip: 'More options',
              onSelected: (m) => _menu(context, m),
              itemBuilder: (_) => [
                const PopupMenuItem(value: _Menu.edit, child: Text('Edit project')),
                PopupMenuItem(value: _Menu.favorite, child: Text(project.favorite ? 'Remove from favourites' : 'Add to favourites')),
                const PopupMenuItem(value: _Menu.duplicate, child: Text('Duplicate')),
                const PopupMenuItem(value: _Menu.template, child: Text('Save as template')),
                const PopupMenuItem(value: _Menu.csv, child: Text('Export tasks (CSV)')),
                const PopupMenuItem(value: _Menu.pdf, child: Text('Project report (PDF)')),
                if (project.isArchived)
                  const PopupMenuItem(value: _Menu.restore, child: Text('Restore'))
                else
                  const PopupMenuItem(value: _Menu.archive, child: Text('Archive')),
                const PopupMenuItem(value: _Menu.delete, child: Text('Delete')),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in tabs) Tab(text: t)],
          ),
        ),
        body: TabBarView(
          children: [
            _Overview(project: project),
            _Tasks(project: project),
            _Board(project: project),
            PlanCalendar(projectId: project.id, allowProjectFilter: false),
            ProjectTimeline(project: project),
            _Milestones(project: project),
            _Notes(project: project),
            _ProjectReports(project: project),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Add task',
          backgroundColor: OmniDesignTokens.primary,
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          onPressed: () => newTask(context, projectId: project.id),
          child: const Icon(Icons.add_rounded),
        ),
      ),
    );
  }
}

// --- Overview ---

class _Overview extends StatelessWidget {
  final Project project;
  const _Overview({required this.project});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final now = DateTime.now();
    final tasks = store.tasksOfProject(project.id);
    final progress = progressOf(tasks);
    final overdue = tasks.where((t) => t.isOverdue(now)).toList();
    final upcoming = tasks.where((t) => !t.isDone && t.dueDate != null && !t.isOverdue(now)).take(5).toList();
    final milestones = store.milestonesOf(project.id).where((m) => !m.isDone).take(3).toList();
    final goal = store.goal(project.goalId);
    final ids = {project.id, for (final t in store.tasksOfProject(project.id, includeArchived: true)) t.id};
    final activity = store.activity.where((a) => a.entityId != null && ids.contains(a.entityId)).take(6).toList();
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(0, 12, 0, 96 + bottom),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
          child: OmniSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    OmniIconTile(icon: project.iconData, color: project.colorValue, size: 48, iconSize: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OmniStatusPill(
                            label: project.isArchived ? 'Archived' : project.status.label,
                            color: project.isArchived ? theme.colorScheme.onSurfaceVariant : project.status.color,
                          ),
                          if (project.priority != Priority.none)
                            OmniStatusPill(label: project.priority.label, color: project.priority.color, icon: Icons.flag_rounded),
                          if (project.category.isNotEmpty) OmniStatusPill(label: project.category, color: theme.colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ],
                ),
                if (project.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(project.description, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      progress.percent == null ? '—' : '${progress.percent}%',
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(progress.label, style: theme.textTheme.bodySmall)),
                  ],
                ),
                const SizedBox(height: 8),
                OmniProgressBar(fraction: progress.fraction, color: project.colorValue, height: 8),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    if (project.startDate != null) Text('Start ${fmt.date(project.startDate!)}', style: theme.textTheme.bodySmall),
                    if (project.dueDate != null) Text('Target ${fmt.date(project.dueDate!)}', style: theme.textTheme.bodySmall),
                    Text('${progress.remaining} remaining', style: theme.textTheme.bodySmall),
                    if (overdue.isNotEmpty)
                      Text('${overdue.length} overdue', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                  ],
                ),
                if (goal != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => openGoal(context, goal),
                    child: Text('Goal: ${goal.title}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (tasks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 12, OmniDesignTokens.pageInset, 0),
            child: ChartCard(
              title: 'Tasks by status',
              child: BreakdownBars(
                items: [
                  for (final s in TaskStatus.values) (s.label, tasks.where((t) => t.status == s).length, s.icon),
                ],
              ),
            ),
          ),
        if (overdue.isNotEmpty) ...[
          const GroupHeader('Overdue'),
          for (final t in overdue) TaskRow(task: t, showProject: false, onTap: () => openTask(context, t)),
        ],
        if (upcoming.isNotEmpty) ...[
          const GroupHeader('Upcoming deadlines'),
          for (final t in upcoming) TaskRow(task: t, showProject: false, onTap: () => openTask(context, t)),
        ],
        if (milestones.isNotEmpty) ...[
          const GroupHeader('Next milestones'),
          for (final m in milestones) MilestoneRow(milestone: m, showProject: false, onTap: () => openMilestone(context, m)),
        ],
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(OmniDesignTokens.pageInset),
            child: OmniInlineEmpty(
              icon: Icons.add_task_rounded,
              title: 'No tasks yet',
              message: 'Add the first task of this project',
              onTap: () => newTask(context, projectId: project.id),
            ),
          ),
        if (activity.isNotEmpty) ...[
          const GroupHeader('Recent activity'),
          for (final a in activity)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset, vertical: 4),
              child: Text('${a.action} · ${a.title} · ${fmt.relativeDay(a.at)}', style: theme.textTheme.bodySmall),
            ),
        ],
      ],
    );
  }
}

// --- Tasks by section ---

class _Tasks extends StatefulWidget {
  final Project project;
  const _Tasks({required this.project});

  @override
  State<_Tasks> createState() => _TasksState();
}

class _TasksState extends State<_Tasks> {
  bool _showDone = false;
  String _query = '';
  TaskSort _sort = TaskSort.smart;

  Future<String?> _askSection(String title, [String initial = '']) async {
    final c = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Section name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final p = widget.project;
    final q = _query.trim().toLowerCase();
    final all = store.tasksOfProject(p.id).where((t) => !t.isSubtask).toList()
      ..sort((a, b) => compareTasks(a, b, _sort));
    final visible = all
        .where((t) => (_showDone || !t.isDone) && (q.isEmpty || '${t.title} ${t.description} ${t.tags.join(' ')}'.toLowerCase().contains(q)))
        .toList();
    final sections = store.sectionsOf(p.id);
    final doneCount = all.where((t) => t.isDone).length;
    final bottom = MediaQuery.paddingOf(context).bottom;

    List<Widget> group(ProjectSection? s) {
      final items = visible.where((t) => s == null ? store.section(t.sectionId) == null : t.sectionId == s.id).toList();
      if (s == null && items.isEmpty) return const [];
      return [
        GroupHeader(
          s?.name ?? 'No section',
          count: items.length,
          trailing: s == null
              ? null
              : PopupMenuButton<String>(
                  tooltip: 'Section options',
                  onSelected: (v) async {
                    switch (v) {
                      case 'add':
                        await newTask(context, projectId: p.id, sectionId: s.id);
                      case 'rename':
                        final name = await _askSection('Rename section', s.name);
                        if (name != null && context.mounted) await runPlanAction(context, () => store.renameSection(s, name));
                      case 'up':
                        await store.moveSection(s, -1);
                      case 'down':
                        await store.moveSection(s, 1);
                      case 'delete':
                        final ok = await confirmAction(
                          context,
                          title: 'Delete section?',
                          message: 'The section "${s.name}" is removed. Its tasks stay in the project without a section.',
                          confirmLabel: 'Delete section',
                        );
                        if (ok && context.mounted) await store.deleteSection(s);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'add', child: Text('Add task here')),
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'up', child: Text('Move up')),
                    PopupMenuItem(value: 'down', child: Text('Move down')),
                    PopupMenuItem(value: 'delete', child: Text('Delete section')),
                  ],
                ),
        ),
        for (final t in items) ...[
          TaskRow(task: t, showProject: false, onTap: () => openTask(context, t)),
          for (final sub in store.subtasksOf(t.id))
            if (_showDone || !sub.isDone)
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: TaskRow(task: sub, showProject: false, dense: true, onTap: () => openTask(context, sub)),
              ),
        ],
        if (s != null && items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 0, OmniDesignTokens.pageInset, 4),
            child: TextButton.icon(
              onPressed: () => newTask(context, projectId: p.id, sectionId: s.id),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add a task'),
            ),
          ),
      ];
    }

    return ListView(
      padding: EdgeInsets.only(top: 12, bottom: 96 + bottom),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
          child: OmniSearchField(
            hintText: 'Search this project...',
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset - 4, 4, OmniDesignTokens.pageInset - 8, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              FilterChip(
                label: Text(doneCount == 0 ? 'Completed' : 'Completed ($doneCount)'),
                selected: _showDone,
                onSelected: (v) => setState(() => _showDone = v),
              ),
              const Spacer(),
              PopupMenuButton<TaskSort>(
                tooltip: 'Sort',
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => [for (final s in TaskSort.values) PopupMenuItem(value: s, child: Text(s.label))],
                icon: const Icon(Icons.sort_rounded),
              ),
              TextButton.icon(
                onPressed: () async {
                  final name = await _askSection('New section');
                  if (name != null && context.mounted) await runPlanAction(context, () => store.addSection(p.id, name));
                },
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('Section'),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
            ],
          ),
        ),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: OmniEmptyState(
              icon: Icons.checklist_rounded,
              title: 'No tasks yet',
              message: 'Add tasks, and group them into sections such as phases or weeks.',
              actionLabel: 'Add task',
              onAction: () => newTask(context, projectId: p.id),
            ),
          )
        else ...[
          ...group(null),
          for (final s in sections) ...group(s),
        ],
      ],
    );
  }
}

// --- Board ---

class _Board extends StatelessWidget {
  final Project project;
  const _Board({required this.project});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    return TaskBoard(
      tasks: store.tasksOfProject(project.id).where((t) => !t.isSubtask).toList(),
      showProject: false,
      onAdd: (status) async {
        final created = await newTask(context, projectId: project.id);
        if (created != null && created.status != status) await store.setTaskStatus(created, status);
      },
    );
  }
}

// --- Milestones ---

class _Milestones extends StatelessWidget {
  final Project project;
  const _Milestones({required this.project});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final list = store.milestonesOf(project.id);
    final progress = milestoneProgress(list);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.only(top: 12, bottom: 96 + bottom),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
          child: OmniSectionHeader(
            title: list.isEmpty ? 'Milestones' : 'Milestones · ${progress.done}/${progress.total} reached',
            actionLabel: 'Add',
            onAction: () => newMilestone(context, projectId: project.id),
          ),
        ),
        if (list.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 4, OmniDesignTokens.pageInset, 8),
            child: OmniProgressBar(fraction: progress.fraction, color: OmniDesignTokens.categoryNfc),
          ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: OmniEmptyState(
              icon: Icons.flag_outlined,
              title: 'No milestones yet',
              message: 'Milestones mark the checkpoints of a project, such as "Design approved" or "Launch".',
              actionLabel: 'Add milestone',
              onAction: () => newMilestone(context, projectId: project.id),
            ),
          ),
        for (final m in list) MilestoneRow(milestone: m, showProject: false, onTap: () => openMilestone(context, m)),
      ],
    );
  }
}

// --- Notes and resources ---

class _Notes extends StatefulWidget {
  final Project project;
  const _Notes({required this.project});

  @override
  State<_Notes> createState() => _NotesState();
}

class _NotesState extends State<_Notes> {
  late final TextEditingController _notes = TextEditingController(text: widget.project.notes);
  final _link = TextEditingController();
  bool _changed = false;

  @override
  void dispose() {
    _notes.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    final store = context.read<PlanStore>();
    final current = store.project(widget.project.id)!;
    if (await runPlanAction(context, () => store.saveProject(current.copyWith(notes: _notes.text.trim()))) && mounted) {
      setState(() => _changed = false);
      showPlanSnack(context, 'Notes saved');
    }
  }

  Future<void> _addResource() async {
    final text = _link.text.trim();
    if (text.isEmpty) return;
    final store = context.read<PlanStore>();
    final current = store.project(widget.project.id)!;
    if (await runPlanAction(context, () => store.saveProject(current.copyWith(resources: [...current.resources, text])))) {
      _link.clear();
    }
  }

  Future<void> _open(String r) async {
    final uri = Uri.tryParse(r.startsWith('http') ? r : 'https://$r');
    if (uri == null || !(uri.host.contains('.'))) {
      showPlanSnack(context, 'This is not a web link.');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showPlanSnack(context, 'The link could not be opened.');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final resources = store.project(widget.project.id)?.resources ?? const [];
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 12, OmniDesignTokens.pageInset, 96 + bottom),
      children: [
        const OmniSectionHeader(title: 'Notes'),
        const SizedBox(height: 10),
        TextField(
          controller: _notes,
          minLines: 6,
          maxLines: 16,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) {
            if (!_changed) setState(() => _changed = true);
          },
          decoration: const InputDecoration(hintText: 'Decisions, ideas, context for this project...'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _changed ? _saveNotes : null, child: const Text('Save notes')),
        ),
        const SizedBox(height: OmniDesignTokens.sectionGap),
        const OmniSectionHeader(title: 'Resources'),
        const SizedBox(height: 4),
        Text('Links and references for the project.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final (i, r) in resources.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link_rounded),
            title: Text(r, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => _open(r),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                final current = store.project(widget.project.id)!;
                final next = [...current.resources]..removeAt(i);
                store.saveProject(current.copyWith(resources: next));
              },
            ),
          ),
        TextField(
          controller: _link,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _addResource(),
          decoration: InputDecoration(
            hintText: 'Add a link or reference',
            suffixIcon: IconButton(tooltip: 'Add', onPressed: _addResource, icon: const Icon(Icons.add_rounded)),
          ),
        ),
      ],
    );
  }
}

// --- Reports ---

class _ProjectReports extends StatefulWidget {
  final Project project;
  const _ProjectReports({required this.project});

  @override
  State<_ProjectReports> createState() => _ProjectReportsState();
}

class _ProjectReportsState extends State<_ProjectReports> {
  ReportRange _range = ReportRange.month;

  @override
  Widget build(BuildContext context) => ReportsView(
    range: _range,
    projectId: widget.project.id,
    embedded: true,
    onRange: (r) => setState(() => _range = r),
  );
}

import 'package:flutter/material.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_form_kit.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_plan_fields.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/tasks/task_pickers.dart';
import 'package:provider/provider.dart';

/// Create or edit a task. Only the title is required; everything else sits
/// in sections, the optional ones folded away as in the Omni Docs form.
/// Pops with the saved task.
class TaskEditorPage extends StatefulWidget {
  final String? taskId;
  final String? projectId;
  final String? sectionId;
  final String? parentId;
  final String? milestoneId;
  final DateTime? dueDate;
  final bool recurring;

  const TaskEditorPage({
    super.key,
    this.taskId,
    this.projectId,
    this.sectionId,
    this.parentId,
    this.milestoneId,
    this.dueDate,
    this.recurring = false,
  });

  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  late PlanTask _task;
  late final bool _isNew;
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();
  final _tags = TextEditingController();
  final _checkItem = TextEditingController();
  final _subtask = TextEditingController();
  final List<String> _newSubtasks = [];
  bool _saving = false;
  bool _dirty = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final store = context.read<PlanStore>();
    final existing = store.task(widget.taskId);
    _isNew = existing == null;
    _task = existing ??
        store.draftTask(
          projectId: widget.projectId,
          sectionId: widget.sectionId,
          parentId: widget.parentId,
          milestoneId: widget.milestoneId,
          dueDate: widget.dueDate == null ? null : dateOnly(widget.dueDate!),
        );
    if (_isNew && widget.recurring) {
      final due = _task.dueDate ?? dateOnly(DateTime.now());
      _task = _task.copyWith(
        dueDate: due,
        recurrence: Recurrence(frequency: RecurrenceFrequency.weekly, weekdays: [due.weekday]),
      );
    }
    _title.text = _task.title;
    _description.text = _task.description;
    _notes.text = _task.notes;
    _tags.text = _task.tags.join(', ');
    for (final c in [_title, _description, _notes, _tags]) {
      c.addListener(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _notes, _tags, _checkItem, _subtask]) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(PlanTask next) => setState(() {
    _task = next;
    _dirty = true;
  });

  PlanTask _collect() => _task.copyWith(
    title: _title.text,
    description: _description.text.trim(),
    notes: _notes.text.trim(),
    tags: {
      for (final t in _tags.text.split(','))
        if (t.trim().isNotEmpty) t.trim().replaceAll('#', ''),
    }.toList(),
  );

  Future<void> _save() async {
    if (_saving) return;
    final store = context.read<PlanStore>();
    final task = _collect();
    final error = store.validateTask(task);
    if (error != null) {
      setState(() => _titleError = task.title.trim().isEmpty ? error : null);
      if (task.title.trim().isNotEmpty) showPlanSnack(context, error);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await store.saveTask(task);
      for (final (i, title) in _newSubtasks.indexed) {
        await store.saveTask(
          store.draftTask(parentId: saved.id, projectId: saved.projectId, sectionId: saved.sectionId)
              .copyWith(title: title, position: i),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, saved);
      showPlanSnack(context, _isNew ? 'Task added' : 'Changes saved');
    } on PlanStoreException catch (e) {
      if (mounted) showPlanSnack(context, e.message);
    } catch (e) {
      if (mounted) showPlanSnack(context, 'The task could not be saved: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return confirmAction(
      context,
      title: 'Discard changes?',
      message: 'What you entered on this page will be lost.',
      confirmLabel: 'Discard',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final project = store.project(_task.projectId);
    final sections = project == null ? const <ProjectSection>[] : store.sectionsOf(project.id);
    final milestones = project == null ? const <Milestone>[] : store.milestonesOf(project.id);
    final parent = store.task(_task.parentId);
    final timed = _task.dueMinutes != null;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: omniListAppBar(
          context,
          _isNew ? (parent == null ? 'New task' : 'New subtask') : 'Edit task',
        ),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 0, OmniDesignTokens.pageInset, 24),
          children: [
            if (parent != null) ...[
              const SizedBox(height: 12),
              Text('Subtask of "${parent.title}"', style: theme.textTheme.bodySmall),
            ],
            OmniFormSection(
              title: 'Task',
              children: [
                TextField(
                  controller: _title,
                  autofocus: _isNew,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(labelText: 'Task title *', errorText: _titleError),
                  onChanged: (_) {
                    if (_titleError != null) setState(() => _titleError = null);
                  },
                ),
                OmniTextArea(label: 'Description', controller: _description, minLines: 3),
              ],
            ),
            OmniFormSection(
              title: 'Schedule',
              children: [
                OmniTapField(
                  label: 'Due date',
                  value: _task.dueDate == null ? null : fmt.date(_task.dueDate!),
                  icon: Icons.calendar_today_rounded,
                  onTap: () async {
                    final d = await pickDate(context, _task.dueDate);
                    if (d == null) return;
                    _set(_task.copyWith(
                      dueDate: d,
                      reminderMinutes: _task.dueDate == null && _task.reminderMinutes == null
                          ? store.prefs.defaultReminderMinutes
                          : null,
                    ));
                  },
                  onClear: () => _set(_task.copyWith(clearDue: true, clearReminder: true, clearRecurrence: true)),
                ),
                if (_task.dueDate != null)
                  OmniTapField(
                    label: 'Due time',
                    value: timed ? fmt.time(_task.dueMinutes!) : 'All day',
                    icon: Icons.schedule_rounded,
                    onTap: () async {
                      final m = await pickTime(context, _task.dueMinutes, use24h: store.prefs.use24h);
                      if (m != null) _set(_task.copyWith(dueMinutes: m));
                    },
                    onClear: timed ? () => _set(_task.copyWith(clearDueTime: true)) : null,
                  ),
                OmniTapField(
                  label: 'Start date',
                  value: _task.startDate == null ? null : fmt.date(_task.startDate!),
                  icon: Icons.play_circle_outline_rounded,
                  helper: 'When work on it begins; used by the timeline.',
                  onTap: () async {
                    final d = await pickDate(context, _task.startDate ?? _task.dueDate);
                    if (d != null) _set(_task.copyWith(startDate: d));
                  },
                  onClear: () => _set(_task.copyWith(clearStart: true)),
                ),
                if (_task.dueDate != null) ...[
                  OmniTapField(
                    label: 'Reminder',
                    value: PlanFormat.reminderLabel(_task.reminderMinutes, timed: timed),
                    icon: Icons.alarm_rounded,
                    onTap: () async {
                      final options = timed ? PlanFormat.timedReminderOptions : PlanFormat.allDayReminderOptions;
                      final picked = await pickOption<int>(
                        context,
                        title: 'Reminder',
                        icon: Icons.alarm_rounded,
                        noneLabel: 'No reminder',
                        current: _task.reminderMinutes,
                        options: [for (final o in options) (o, PlanFormat.reminderLabel(o, timed: timed))],
                      );
                      if (picked == null) return;
                      _set(picked.value == null
                          ? _task.copyWith(clearReminder: true)
                          : _task.copyWith(reminderMinutes: picked.value));
                    },
                  ),
                  OmniTapField(
                    label: 'Repeat',
                    value: _task.recurrence?.summary ?? 'Does not repeat',
                    icon: Icons.repeat_rounded,
                    onTap: () async {
                      final picked = await pickRecurrence(context, _task.recurrence, _task.dueDate);
                      if (picked == null) return;
                      _set(picked.value == null
                          ? _task.copyWith(clearRecurrence: true)
                          : _task.copyWith(recurrence: picked.value));
                    },
                  ),
                ] else
                  Text('Add a due date to set a reminder or repeat.', style: theme.textTheme.bodySmall),
                OmniTapField(
                  label: 'Estimated duration',
                  value: _task.estimateMinutes == null ? null : fmt.duration(_task.estimateMinutes!),
                  icon: Icons.timer_outlined,
                  onTap: () async {
                    final picked = await pickOption<int>(
                      context,
                      title: 'Estimated duration',
                      icon: Icons.timer_outlined,
                      noneLabel: 'No estimate',
                      current: _task.estimateMinutes,
                      options: [for (final o in estimateOptions) (o, fmt.duration(o))],
                    );
                    if (picked == null) return;
                    _set(picked.value == null
                        ? _task.copyWith(clearEstimate: true)
                        : _task.copyWith(estimateMinutes: picked.value));
                  },
                  onClear: () => _set(_task.copyWith(clearEstimate: true)),
                ),
              ],
            ),
            OmniFormSection(
              title: 'Organise',
              children: [
                if (parent == null)
                  OmniTapField(
                    label: 'Project',
                    value: project?.name ?? 'No project',
                    icon: Icons.folder_outlined,
                    onTap: () async {
                      final picked = await pickProject(context, _task.projectId);
                      if (picked == null) return;
                      _set(picked.value == null
                          ? _task.copyWith(clearProject: true, clearSection: true, clearMilestone: true)
                          : _task.copyWith(projectId: picked.value, clearSection: true, clearMilestone: true));
                    },
                  ),
                if (sections.isNotEmpty)
                  OmniTapField(
                    label: 'Section',
                    value: store.section(_task.sectionId)?.name,
                    icon: Icons.view_agenda_outlined,
                    onTap: () async {
                      final picked = await pickOption<String>(
                        context,
                        title: 'Section',
                        icon: Icons.view_agenda_outlined,
                        noneLabel: 'No section',
                        current: _task.sectionId,
                        options: [for (final s in sections) (s.id, s.name)],
                      );
                      if (picked == null) return;
                      _set(picked.value == null
                          ? _task.copyWith(clearSection: true)
                          : _task.copyWith(sectionId: picked.value));
                    },
                    onClear: () => _set(_task.copyWith(clearSection: true)),
                  ),
                if (milestones.isNotEmpty)
                  OmniTapField(
                    label: 'Milestone',
                    value: store.milestone(_task.milestoneId)?.title,
                    icon: Icons.flag_outlined,
                    onTap: () async {
                      final picked = await pickOption<String>(
                        context,
                        title: 'Milestone',
                        icon: Icons.flag_outlined,
                        noneLabel: 'No milestone',
                        current: _task.milestoneId,
                        options: [for (final m in milestones) (m.id, m.title)],
                      );
                      if (picked == null) return;
                      _set(picked.value == null
                          ? _task.copyWith(clearMilestone: true)
                          : _task.copyWith(milestoneId: picked.value));
                    },
                    onClear: () => _set(_task.copyWith(clearMilestone: true)),
                  ),
                const OmniFieldLabel('Priority'),
                PriorityPicker(value: _task.priority, onChanged: (p) => _set(_task.copyWith(priority: p))),
                OmniSegmented<TaskStatus>(
                  label: 'Status',
                  dense: true,
                  options: [for (final s in TaskStatus.values) OmniOption(s, s.label)],
                  value: _task.status,
                  onChanged: (s) => _set(_task.copyWith(status: s)),
                ),
                TextField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    helperText: 'Separate with commas, for example: urgent, client',
                  ),
                ),
              ],
            ),
            OmniFormSection(
              title: 'Checklist',
              collapsible: true,
              initiallyOpen: _task.checklist.isNotEmpty,
              children: [
                for (final c in _task.checklist)
                  Row(
                    children: [
                      Checkbox(
                        value: c.done,
                        onChanged: (v) => _set(_task.copyWith(
                          checklist: [for (final x in _task.checklist) x.id == c.id ? x.copyWith(done: v == true) : x],
                        )),
                      ),
                      Expanded(child: Text(c.title)),
                      IconButton(
                        tooltip: 'Remove ${c.title}',
                        onPressed: () => _set(_task.copyWith(
                          checklist: [for (final x in _task.checklist) if (x.id != c.id) x],
                        )),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                _AddLine(
                  controller: _checkItem,
                  hint: 'Add a checklist item',
                  onAdd: (text) => _set(_task.copyWith(checklist: [
                    ..._task.checklist,
                    ChecklistItem(id: store.newId(), title: text),
                  ])),
                ),
              ],
            ),
            if (_isNew && parent == null)
              OmniFormSection(
                title: 'Subtasks',
                collapsible: true,
                children: [
                  for (final (i, s) in _newSubtasks.indexed)
                    Row(
                      children: [
                        const Icon(Icons.subdirectory_arrow_right_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s)),
                        IconButton(
                          tooltip: 'Remove $s',
                          onPressed: () => setState(() => _newSubtasks.removeAt(i)),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                  _AddLine(
                    controller: _subtask,
                    hint: 'Add a subtask',
                    onAdd: (text) => setState(() {
                      _newSubtasks.add(text);
                      _dirty = true;
                    }),
                  ),
                ],
              ),
            OmniFormSection(
              title: 'Notes and links',
              collapsible: true,
              initiallyOpen: _task.notes.isNotEmpty,
              children: [OmniTextArea(label: 'Notes', controller: _notes, hint: 'Links, references, anything useful')],
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 12 + bottom),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(_isNew ? 'Save task' : 'Save changes'),
            ),
          ),
        ),
      ),
    );
  }
}

/// A text field with an add button, for checklist items and subtasks.
class _AddLine extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onAdd;

  const _AddLine({required this.controller, required this.hint, required this.onAdd});

  void _add() {
    final t = controller.text.trim();
    if (t.isEmpty) return;
    onAdd(t);
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _add(),
      decoration: InputDecoration(
        hintText: hint,
        suffixIcon: IconButton(tooltip: 'Add', onPressed: _add, icon: const Icon(Icons.add_rounded)),
      ),
    );
  }
}

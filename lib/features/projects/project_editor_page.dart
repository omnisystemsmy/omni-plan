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

/// Create or edit a project. Pops with the saved project.
class ProjectEditorPage extends StatefulWidget {
  final String? projectId;

  const ProjectEditorPage({super.key, this.projectId});

  @override
  State<ProjectEditorPage> createState() => _ProjectEditorPageState();
}

class _ProjectEditorPageState extends State<ProjectEditorPage> {
  late Project _p;
  late final Project? _original;
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  bool _dirty = false;
  String? _nameError;

  bool get _isNew => _original == null;

  @override
  void initState() {
    super.initState();
    final store = context.read<PlanStore>();
    _original = store.project(widget.projectId);
    _p = _original ?? store.draftProject();
    _name.text = _p.name;
    _description.text = _p.description;
    _notes.text = _p.notes;
    for (final c in [_name, _description, _notes]) {
      c.addListener(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _set(Project p) => setState(() {
    _p = p;
    _dirty = true;
  });

  Future<void> _save() async {
    if (_saving) return;
    final store = context.read<PlanStore>();
    final next = _p.copyWith(name: _name.text, description: _description.text.trim(), notes: _notes.text.trim());
    final error = store.validateProject(next);
    if (error != null) {
      if (next.name.trim().isEmpty) {
        setState(() => _nameError = error);
      } else {
        showPlanSnack(context, error);
      }
      return;
    }
    // Moving the start date never moves the tasks unless the person says so.
    int shift = 0;
    final old = _original?.startDate;
    final now = next.startDate;
    if (!_isNew && old != null && now != null && old != now && store.tasksOfProject(next.id).any((t) => t.dueDate != null)) {
      final days = dateOnly(now).difference(dateOnly(old)).inDays;
      final move = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Move task dates too?'),
          content: Text(
            'The start date moved by ${days.abs()} ${days.abs() == 1 ? 'day' : 'days'} ${days > 0 ? 'later' : 'earlier'}. '
            'Move every dated task and milestone of this project by the same amount?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep task dates')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Move them')),
          ],
        ),
      );
      if (move == null) return;
      if (move) shift = days;
    }
    setState(() => _saving = true);
    try {
      final saved = await store.saveProject(next);
      if (shift != 0) await store.shiftProjectDates(saved, shift);
      if (!mounted) return;
      Navigator.pop(context, saved);
      showPlanSnack(context, _isNew ? 'Project created' : 'Changes saved');
    } on PlanStoreException catch (e) {
      if (mounted) showPlanSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final goal = store.goal(_p.goalId);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = !_dirty ||
            await confirmAction(
              context,
              title: 'Discard changes?',
              message: 'What you entered on this page will be lost.',
              confirmLabel: 'Discard',
            );
        if (leave && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: omniListAppBar(context, _isNew ? 'New project' : 'Edit project'),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 0, OmniDesignTokens.pageInset, 24),
          children: [
            OmniFormSection(
              title: 'Project',
              children: [
                TextField(
                  controller: _name,
                  autofocus: _isNew,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: 'Project name *', errorText: _nameError),
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                ),
                OmniTextArea(label: 'Description', controller: _description, minLines: 3),
                DropdownButtonFormField<String>(
                  initialValue: planCategories.contains(_p.category) ? _p.category : '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('No category')),
                    for (final c in planCategories) DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => _set(_p.copyWith(category: v ?? '')),
                ),
              ],
            ),
            OmniFormSection(
              title: 'Schedule',
              children: [
                OmniTapField(
                  label: 'Start date',
                  value: _p.startDate == null ? null : fmt.date(_p.startDate!),
                  icon: Icons.play_circle_outline_rounded,
                  onTap: () async {
                    final d = await pickDate(context, _p.startDate);
                    if (d != null) _set(_p.copyWith(startDate: d));
                  },
                  onClear: () => _set(_p.copyWith(clearStart: true)),
                ),
                OmniTapField(
                  label: 'Target completion date',
                  value: _p.dueDate == null ? null : fmt.date(_p.dueDate!),
                  icon: Icons.flag_outlined,
                  onTap: () async {
                    final d = await pickDate(context, _p.dueDate ?? _p.startDate);
                    if (d != null) _set(_p.copyWith(dueDate: d));
                  },
                  onClear: () => _set(_p.copyWith(clearDue: true)),
                ),
              ],
            ),
            OmniFormSection(
              title: 'Status and priority',
              children: [
                OmniSegmented<ProjectStatus>(
                  label: 'Status',
                  dense: true,
                  options: [for (final s in ProjectStatus.values) OmniOption(s, s.label)],
                  value: _p.status,
                  onChanged: (s) => _set(_p.copyWith(status: s)),
                ),
                const OmniFieldLabel('Priority'),
                PriorityPicker(value: _p.priority, onChanged: (v) => _set(_p.copyWith(priority: v))),
                OmniTapField(
                  label: 'Goal',
                  value: goal?.title,
                  icon: Icons.flag_rounded,
                  helper: 'The project’s tasks count towards the goal’s progress.',
                  onTap: () async {
                    final picked = await pickOption<String>(
                      context,
                      title: 'Goal',
                      icon: Icons.flag_rounded,
                      noneLabel: 'No goal',
                      current: _p.goalId,
                      options: [for (final g in store.goals) (g.id, g.title)],
                    );
                    if (picked == null) return;
                    _set(picked.value == null ? _p.copyWith(clearGoal: true) : _p.copyWith(goalId: picked.value));
                  },
                  onClear: () => _set(_p.copyWith(clearGoal: true)),
                ),
              ],
            ),
            OmniFormSection(
              title: 'Look',
              collapsible: true,
              initiallyOpen: _isNew,
              children: [
                const OmniFieldLabel('Colour'),
                ColorPicker(value: _p.color, onChanged: (c) => _set(_p.copyWith(color: c))),
                const OmniFieldLabel('Icon'),
                IconPicker(value: _p.icon, color: _p.colorValue, onChanged: (i) => _set(_p.copyWith(icon: i))),
              ],
            ),
            OmniFormSection(
              title: 'Notes',
              collapsible: true,
              initiallyOpen: _p.notes.isNotEmpty,
              children: [OmniTextArea(label: 'Project notes', controller: _notes)],
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 12 + bottom),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(_isNew ? 'Create project' : 'Save changes'),
            ),
          ),
        ),
      ),
    );
  }
}

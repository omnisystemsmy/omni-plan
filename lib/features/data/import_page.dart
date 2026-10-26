import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/data/task_import.dart';
import 'package:omni_plan/features/pro/plan_service.dart';
import 'package:omni_plan/features/pro/pro_gate.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:provider/provider.dart';

/// Opens the CSV import, for Pro.
Future<void> openImport(BuildContext context) async {
  if (!await ProGate.ensure(context, ProCapability.csvImport) || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportPage()));
}

/// Import tasks from a CSV file: choose the file, match columns to fields,
/// check every row, then confirm.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  String? _fileName;
  List<List<String>> _rows = const [];
  Map<ImportField, int> _mapping = {};
  bool _createProjects = true;
  bool _includeDuplicates = false;
  bool _busy = false;

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null) return;
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    final rows = parseCsv(text);
    if (!mounted) return;
    if (rows.length < 2) {
      showPlanSnack(context, 'The file needs a header row and at least one task.');
      return;
    }
    setState(() {
      _fileName = file!.name;
      _rows = rows;
      _mapping = guessMapping(rows.first);
    });
  }

  Future<void> _import(ImportPlan plan) async {
    final count = plan.valid + (_includeDuplicates ? plan.duplicates : 0);
    final ok = await confirmAction(
      context,
      title: 'Import $count tasks?',
      message: [
        if (plan.newProjects.isNotEmpty) '${plan.newProjects.length} new projects will be created.',
        if (plan.invalid > 0) '${plan.invalid} rows with problems are skipped.',
        if (plan.duplicates > 0 && !_includeDuplicates) '${plan.duplicates} duplicates are skipped.',
      ].join(' ').ifEmpty('Every row is ready.'),
      confirmLabel: 'Import',
      destructive: false,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final store = context.read<PlanStore>();
    try {
      final result = await runImport(store, plan, includeDuplicates: _includeDuplicates);
      if (!mounted) return;
      Navigator.pop(context);
      showPlanSnack(
        context,
        '${result.created} tasks imported${result.projectsCreated == 0 ? '' : ', ${result.projectsCreated} projects created'}',
      );
    } catch (e) {
      if (mounted) showPlanSnack(context, 'The import stopped: $e. Tasks saved before the error were kept.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final header = _rows.isEmpty ? const <String>[] : _rows.first;
    final hasTitle = _mapping.containsKey(ImportField.title);
    final plan = _rows.isEmpty || !hasTitle
        ? null
        : planImport(store, _rows, _mapping, createProjects: _createProjects, maxRows: ProLimits.importRows);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: omniListAppBar(context, 'Import tasks'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 24),
        children: [
          Text(
            'Bring tasks in from a spreadsheet saved as CSV. The first row must name the columns. '
            'A CSV exported from Omni Plan can be imported as it is.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          OmniSurfaceCard(
            onTap: _busy ? null : _pick,
            child: Row(
              children: [
                const OmniIconTile(icon: Icons.upload_file_rounded, color: OmniDesignTokens.categoryFiles),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fileName ?? 'Choose a CSV file', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(_rows.isEmpty ? 'Up to ${ProLimits.importRows} rows' : '${_rows.length - 1} rows · ${header.length} columns',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: OmniDesignTokens.sectionGap),
            const OmniSectionHeader(title: 'Match columns'),
            const SizedBox(height: 8),
            for (final f in ImportField.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<int?>(
                  initialValue: _mapping[f],
                  isExpanded: true,
                  decoration: InputDecoration(labelText: f == ImportField.title ? '${f.label} *' : f.label),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Not imported')),
                    for (final (i, h) in header.indexed)
                      DropdownMenuItem<int?>(value: i, child: Text(h.trim().isEmpty ? 'Column ${i + 1}' : h, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() {
                    _mapping = {..._mapping}..remove(f);
                    if (v != null) {
                      _mapping.removeWhere((_, idx) => idx == v);
                      _mapping[f] = v;
                    }
                  }),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Create projects that do not exist yet'),
              value: _createProjects,
              onChanged: (v) => setState(() => _createProjects = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Import duplicates too'),
              subtitle: const Text('Same title, due date and project as an existing task'),
              value: _includeDuplicates,
              onChanged: (v) => setState(() => _includeDuplicates = v),
            ),
            if (!hasTitle)
              Text('Choose which column holds the task title.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            if (plan != null) ...[
              const SizedBox(height: OmniDesignTokens.sectionGap),
              const OmniSectionHeader(title: 'Check'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OmniStatusPill(label: '${plan.valid} ready', color: OmniDesignTokens.success, icon: Icons.check_rounded),
                  if (plan.duplicates > 0) OmniStatusPill(label: '${plan.duplicates} duplicates', color: OmniDesignTokens.accentAmber),
                  if (plan.invalid > 0) OmniStatusPill(label: '${plan.invalid} with problems', color: theme.colorScheme.error),
                  if (plan.newProjects.isNotEmpty) OmniStatusPill(label: '${plan.newProjects.length} new projects', color: theme.colorScheme.primary),
                ],
              ),
              const SizedBox(height: 8),
              for (final r in plan.rows.take(8))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    !r.ok ? Icons.error_outline_rounded : (r.duplicate ? Icons.copy_rounded : Icons.check_circle_outline_rounded),
                    color: !r.ok ? theme.colorScheme.error : (r.duplicate ? OmniDesignTokens.accentAmber : OmniDesignTokens.success),
                  ),
                  title: Text(r.task?.title ?? 'Row ${r.line}'),
                  subtitle: Text(!r.ok ? r.problems.join(' · ') : [if (r.projectName != null) r.projectName!, if (r.duplicate) 'duplicate'].join(' · ')),
                ),
              if (plan.rows.length > 8) Text('and ${plan.rows.length - 8} more rows', style: theme.textTheme.bodySmall),
              if (plan.rows.any((r) => !r.ok)) ...[
                const SizedBox(height: 8),
                Text('Rows with problems', style: theme.textTheme.titleSmall),
                for (final r in plan.rows.where((r) => !r.ok).take(20))
                  Text('Row ${r.line}: ${r.problems.join(', ')}', style: theme.textTheme.bodySmall),
              ],
            ],
          ],
        ],
      ),
      bottomNavigationBar: plan == null
          ? null
          : Padding(
              padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 12 + bottom),
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _busy || (plan.valid + (_includeDuplicates ? plan.duplicates : 0)) == 0 ? null : () => _import(plan),
                  icon: const Icon(Icons.download_done_rounded),
                  label: Text('Import ${plan.valid + (_includeDuplicates ? plan.duplicates : 0)} tasks'),
                ),
              ),
            ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

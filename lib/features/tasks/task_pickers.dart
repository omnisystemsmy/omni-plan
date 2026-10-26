import 'package:flutter/material.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/core/widgets/omni_plan_fields.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:provider/provider.dart';

/// Result wrapper so "no project" can be told apart from "dismissed".
class Picked<T> {
  final T? value;
  const Picked(this.value);
}

Future<Picked<String>?> pickProject(BuildContext context, String? current, {bool allowNone = true}) {
  final store = context.read<PlanStore>();
  final projects = store.projects..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return showModalBottomSheet<Picked<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => OmniBottomSheetScaffold(
      title: 'Project',
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
      child: Flexible(
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (allowNone)
                OmniMenuRow(
                  icon: Icons.inbox_rounded,
                  useTile: true,
                  title: 'No project',
                  selected: current == null,
                  trailing: current == null ? const Icon(Icons.check_rounded) : const SizedBox.shrink(),
                  onTap: () => Navigator.pop(sheet, const Picked<String>(null)),
                ),
              for (final p in projects)
                OmniMenuRow(
                  icon: p.iconData,
                  iconColor: p.colorValue,
                  useTile: true,
                  title: p.name,
                  subtitle: p.status.label,
                  selected: current == p.id,
                  trailing: current == p.id ? const Icon(Icons.check_rounded) : const SizedBox.shrink(),
                  onTap: () => Navigator.pop(sheet, Picked(p.id)),
                ),
              if (projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No projects yet. Create one from the New button.'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A choice from [options] with a "none" entry; dismissing returns null.
Future<Picked<T>?> pickOption<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T? current,
  String? noneLabel,
  IconData icon = Icons.circle_outlined,
}) {
  return showModalBottomSheet<Picked<T>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => OmniBottomSheetScaffold(
      title: title,
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
      child: Flexible(
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (noneLabel != null)
                OmniMenuRow(
                  icon: Icons.block_rounded,
                  title: noneLabel,
                  selected: current == null,
                  trailing: current == null ? const Icon(Icons.check_rounded) : const SizedBox.shrink(),
                  onTap: () => Navigator.pop(sheet, Picked<T>(null)),
                ),
              for (final (value, label) in options)
                OmniMenuRow(
                  icon: icon,
                  title: label,
                  selected: current == value,
                  trailing: current == value ? const Icon(Icons.check_rounded) : const SizedBox.shrink(),
                  onTap: () => Navigator.pop(sheet, Picked<T>(value)),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

const List<int> estimateOptions = [15, 30, 45, 60, 90, 120, 180, 240, 480];

/// Edits a repeat rule. Returns Picked(null) for "Does not repeat".
Future<Picked<Recurrence>?> pickRecurrence(BuildContext context, Recurrence? current, DateTime? due) {
  return showModalBottomSheet<Picked<Recurrence>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RecurrenceSheet(initial: current, due: due),
  );
}

class _RecurrenceSheet extends StatefulWidget {
  final Recurrence? initial;
  final DateTime? due;
  const _RecurrenceSheet({required this.initial, required this.due});

  @override
  State<_RecurrenceSheet> createState() => _RecurrenceSheetState();
}

class _RecurrenceSheetState extends State<_RecurrenceSheet> {
  RecurrenceFrequency? _freq;
  int _interval = 1;
  Set<int> _days = {};
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _freq = r?.frequency ?? RecurrenceFrequency.weekly;
    _interval = r?.interval ?? 1;
    _days = {...?r?.weekdays};
    if (_days.isEmpty && widget.due != null) _days = {widget.due!.weekday};
    _end = r?.endDate;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = PlanFormat(context.read<PlanStore>().prefs);
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final freq = _freq!;
    final rule = Recurrence(
      frequency: freq,
      interval: _interval,
      weekdays: freq == RecurrenceFrequency.weekly ? (_days.toList()..sort()) : const [],
      endDate: _end,
    );
    final next = widget.due == null ? null : rule.next(widget.due!);
    return OmniBottomSheetScaffold(
      title: 'Repeat',
      child: Flexible(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in RecurrenceFrequency.values)
                    ChoiceChip(
                      label: Text(f.label),
                      selected: f == freq,
                      onSelected: (_) => setState(() => _freq = f),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('Every $_interval ${freq.unit}${_interval == 1 ? '' : 's'}', style: theme.textTheme.bodyLarge)),
                  IconButton(
                    tooltip: 'Less often',
                    onPressed: _interval > 1 ? () => setState(() => _interval--) : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  IconButton(
                    tooltip: 'More',
                    onPressed: _interval < 30 ? () => setState(() => _interval++) : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
              if (freq == RecurrenceFrequency.weekly) ...[
                const SizedBox(height: 8),
                Text('On', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(names[d - 1]),
                        selected: _days.contains(d),
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              OmniTapField(
                label: 'Ends (optional)',
                value: _end == null ? null : fmt.date(_end!),
                icon: Icons.event_busy_rounded,
                onTap: () async {
                  final d = await pickDate(context, _end ?? widget.due);
                  if (d != null) setState(() => _end = d);
                },
                onClear: () => setState(() => _end = null),
              ),
              const SizedBox(height: 12),
              Text(
                next == null
                    ? 'Completing the task adds the next one on its new due date.'
                    : 'When you complete it, the next one is added for ${fmt.date(next)}.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, const Picked<Recurrence>(null)),
                        child: const Text('Does not repeat'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, Picked(rule)),
                        child: const Text('Done'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Priority choice as tinted chips.
class PriorityPicker extends StatelessWidget {
  final Priority value;
  final ValueChanged<Priority> onChanged;

  const PriorityPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in Priority.values)
          ChoiceChip(
            avatar: p == Priority.none ? null : Icon(Icons.flag_rounded, size: 16, color: value == p ? Colors.white : p.color),
            label: Text(p.label),
            selected: value == p,
            onSelected: (_) => onChanged(p),
          ),
      ],
    );
  }
}

/// Colour swatches from [planColors].
class ColorPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const ColorPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in planColors)
          Semantics(
            button: true,
            selected: c.toARGB32() == value,
            label: 'Colour',
            child: InkResponse(
              onTap: () => onChanged(c.toARGB32()),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: c.toARGB32() == value
                      ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                      : null,
                ),
                child: c.toARGB32() == value ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// Icon choice from [planIcons], tinted with [color].
class IconPicker extends StatelessWidget {
  final String value;
  final Color color;
  final ValueChanged<String> onChanged;

  const IconPicker({super.key, required this.value, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in planIcons.entries)
          Semantics(
            button: true,
            selected: e.key == value,
            label: e.key,
            child: InkWell(
              borderRadius: BorderRadius.circular(OmniDesignTokens.radiusControl),
              onTap: () => onChanged(e.key),
              child: e.key == value
                  ? OmniIconTile(icon: e.value, color: color, size: 44, solid: true)
                  : OmniIconTile(icon: e.value, color: color, size: 44),
            ),
          ),
      ],
    );
  }
}

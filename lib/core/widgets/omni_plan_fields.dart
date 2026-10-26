import 'package:flutter/material.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';

// Form pieces for the planning editors, taken from the Omni Docs document
// form (section title with accent bar and "Optional" fold, read-only date
// field with pick and clear buttons) so the editors look like the Details
// tab of Omni Docs.

/// Same look as the Omni Docs form section title: accent bar and bold
/// title that wraps instead of overflowing.
class OmniFormSectionTitle extends StatelessWidget {
  final String title;

  const OmniFormSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 16,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(OmniDesignTokens.radiusPill),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// A form section; when [collapsible], it folds behind an "Optional" toggle
/// like the Omni Docs "Document control" section.
class OmniFormSection extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final bool collapsible;
  final bool initiallyOpen;

  const OmniFormSection({
    super.key,
    required this.title,
    required this.children,
    this.collapsible = false,
    this.initiallyOpen = false,
  });

  @override
  State<OmniFormSection> createState() => _OmniFormSectionState();
}

class _OmniFormSectionState extends State<OmniFormSection> {
  late bool _open = !widget.collapsible || widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: OmniDesignTokens.sectionGap),
        if (widget.collapsible)
          InkWell(
            borderRadius: BorderRadius.circular(OmniDesignTokens.radiusControl),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: OmniFormSectionTitle(widget.title)),
                  Text('Optional', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: OmniDesignTokens.fastMotion,
                    child: Icon(
                      Icons.expand_more_rounded,
                      semanticLabel: _open ? 'Hide ${widget.title}' : 'Show ${widget.title}',
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          OmniFormSectionTitle(widget.title),
        if (_open) ...[
          const SizedBox(height: 12),
          for (final c in widget.children) ...[c, const SizedBox(height: 12)],
        ],
      ],
    );
  }
}

/// A read-only field that shows [value] and runs [onTap] to change it, with
/// an optional clear button. Used for dates, times and pickers.
class OmniTapField extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final String? helper;
  final String? errorText;

  const OmniTapField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon = Icons.expand_more_rounded,
    this.onClear,
    this.helper,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return Semantics(
      button: true,
      label: hasValue ? '$label, $value' : label,
      child: InkWell(
        borderRadius: BorderRadius.circular(OmniDesignTokens.radiusControl),
        onTap: onTap,
        child: InputDecorator(
          isEmpty: !hasValue,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            helperMaxLines: 3,
            errorText: errorText,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasValue && onClear != null)
                  IconButton(
                    tooltip: 'Clear $label',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onClear,
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(icon, size: 20),
                ),
              ],
            ),
          ),
          child: Text(
            hasValue ? value! : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Shows the date picker; null when dismissed.
Future<DateTime?> pickDate(BuildContext context, DateTime? current, {DateTime? first}) {
  return showDatePicker(
    context: context,
    initialDate: current ?? DateTime.now(),
    firstDate: first ?? DateTime(2000),
    lastDate: DateTime(2100),
  );
}

/// Shows the time picker; minutes after midnight, or null when dismissed.
Future<int?> pickTime(BuildContext context, int? current, {bool use24h = false}) async {
  final now = TimeOfDay.now();
  final picked = await showTimePicker(
    context: context,
    initialTime: current == null
        ? TimeOfDay(hour: now.hour + 1 > 23 ? 23 : now.hour + 1, minute: 0)
        : TimeOfDay(hour: current ~/ 60, minute: current % 60),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24h),
      child: child!,
    ),
  );
  return picked == null ? null : picked.hour * 60 + picked.minute;
}

/// A text area with its label above, as in the Omni Docs form ("API
/// purpose *").
class OmniTextArea extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final int minLines;

  const OmniTextArea({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.minLines = 4,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: minLines + 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint, alignLabelWithHint: true),
        ),
      ],
    );
  }
}

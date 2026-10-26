import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';

// Small charts drawn with plain widgets, so they follow the theme and stay
// readable without a charting dependency.
//
// Colours were checked with the dataviz palette validator: one hue for a
// single series, and for the two-series planned-vs-done chart a teal and an
// indigo that stay apart for colour-blind readers (light: #00AEB4 / #5967C8,
// dark: #009CA2 / #6F7CD6). Values are always written out as well, and each
// bar has a tooltip, so nothing depends on colour alone.

class ChartColors {
  final Color primary;
  final Color secondary;

  const ChartColors(this.primary, this.secondary);

  static ChartColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? const ChartColors(Color(0xFF009CA2), Color(0xFF6F7CD6))
      : const ChartColors(Color(0xFF00AEB4), Color(0xFF5967C8));
}

/// One bar per item, labelled under the bar, value above it.
class ColumnChart extends StatelessWidget {
  final List<(String, int)> items;
  final double height;
  final String unit;

  const ColumnChart({super.key, required this.items, this.height = 150, this.unit = 'tasks'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ChartColors.of(context).primary;
    final max = items.fold<int>(0, (m, i) => math.max(m, i.$2));
    return SizedBox(
      height: height + 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (label, value) in items)
            Expanded(
              child: Tooltip(
                message: '$label: $value $unit',
                triggerMode: TooltipTriggerMode.tap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (value > 0)
                        Text('$value', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Container(
                        height: max == 0 ? 2 : math.max(2, height * value / max),
                        decoration: BoxDecoration(
                          color: value == 0 ? theme.dividerColor : color,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Two bars per item (planned and done), with a legend.
class PairedColumnChart extends StatelessWidget {
  final List<(String, int, int)> items;
  final String firstLabel;
  final String secondLabel;
  final double height;

  const PairedColumnChart({
    super.key,
    required this.items,
    required this.firstLabel,
    required this.secondLabel,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChartColors.of(context);
    final max = items.fold<int>(0, (m, i) => math.max(m, math.max(i.$2, i.$3)));
    Widget bar(int v, Color c, String tip) => Expanded(
      child: Tooltip(
        message: tip,
        triggerMode: TooltipTriggerMode.tap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (v > 0) Text('$v', style: theme.textTheme.labelSmall?.copyWith(fontSize: 9, fontWeight: FontWeight.w700)),
            Container(
              height: max == 0 ? 2 : math.max(2, height * v / max),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: v == 0 ? theme.dividerColor : c,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
          ],
        ),
      ),
    );
    Widget legend(Color c, String l) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(l, style: theme.textTheme.bodySmall),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 16, children: [legend(colors.secondary, firstLabel), legend(colors.primary, secondLabel)]),
        const SizedBox(height: 10),
        SizedBox(
          height: height + 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (label, a, b) in items)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              bar(a, colors.secondary, '$label: $a $firstLabel'.toLowerCase()),
                              bar(b, colors.primary, '$label: $b $secondLabel'.toLowerCase()),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(label, maxLines: 1, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Labelled horizontal bars for a breakdown (tasks by status or priority).
/// Each row names its category, so the bar colour is never the only cue.
class BreakdownBars extends StatelessWidget {
  final List<(String, int, IconData?)> items;

  const BreakdownBars({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ChartColors.of(context).primary;
    final total = items.fold<int>(0, (n, i) => n + i.$2);
    final max = items.fold<int>(0, (m, i) => math.max(m, i.$2));
    return Column(
      children: [
        for (final (label, value, icon) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Tooltip(
              message: total == 0 ? '$label: 0' : '$label: $value (${(value * 100 / total).round()}%)',
              triggerMode: TooltipTriggerMode.tap,
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                  ],
                  SizedBox(width: 96, child: Text(label, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: max == 0 ? 2 : math.max(2, c.maxWidth * value / max),
                          height: 12,
                          decoration: BoxDecoration(
                            color: value == 0 ? theme.dividerColor : color,
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text('$value', textAlign: TextAlign.right, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A big number with a caption (the "not a chart" case).
class StatNumber extends StatelessWidget {
  final String value;
  final String label;

  const StatNumber({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Card wrapper for a chart with its title.
class ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const ChartCard({super.key, required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(OmniDesignTokens.cardPadding),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(OmniDesignTokens.radiusCard),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

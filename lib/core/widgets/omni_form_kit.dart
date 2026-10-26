import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';

// The form controls of Omni Tools (CalcField and CalcSegmented), under Omni
// Docs names: a text field with its label above, and the pill selector used
// for the Sign in / Create account tabs. They look and move the same as in
// Omni Tools.

class OmniOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const OmniOption(this.value, this.label, {this.icon});
}

/// Pill track, full width, with a highlight that slides to the selected
/// option. Scrolls sideways when there are many options.
class OmniSegmented<T> extends StatelessWidget {
  final List<OmniOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? label;

  /// Tighter padding and smaller text for 4+ options.
  final bool dense;

  const OmniSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedBg = theme.colorScheme.primary;
    final totalChars = options.fold<int>(0, (n, o) => n + o.label.length);
    final scrollable = options.length > 5 || totalChars > 30;

    Widget segment(OmniOption<T> o) {
      final isSelected = o.value == value;
      final fg = isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!isSelected) HapticFeedback.selectionClick();
          onChanged(o.value);
        },
        child: AnimatedContainer(
          duration: OmniDesignTokens.mediumMotion,
          curve: Curves.easeOutCubic,
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 16),
          alignment: Alignment.center,
          // In a fixed-width selector the sliding highlight below draws the
          // selected background; only a scrolling one paints it here.
          decoration: BoxDecoration(
            color: isSelected && scrollable ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(OmniDesignTokens.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (o.icon != null) ...[
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: fg),
                  duration: const Duration(milliseconds: 240),
                  builder: (context, c, _) => Icon(o.icon, size: 16, color: c),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  style: (theme.textTheme.labelLarge ?? const TextStyle())
                      .copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
                        fontSize: dense ? 12 : 13,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: Text(o.label),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final index = options.indexWhere((o) => o.value == value);
    final track = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? OmniDesignTokens.darkSurface
            : OmniDesignTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(OmniDesignTokens.radiusPill),
        border: Border.all(color: theme.dividerColor),
      ),
      child: scrollable
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final o in options) segment(o)]),
            )
          : Stack(
              children: [
                if (index >= 0)
                  Positioned.fill(
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment(
                        options.length < 2
                            ? 0
                            : -1 + 2 * index / (options.length - 1),
                        0,
                      ),
                      child: FractionallySizedBox(
                        widthFactor: 1 / options.length,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: selectedBg,
                            borderRadius: BorderRadius.circular(
                              OmniDesignTokens.radiusPill,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    for (final o in options) Expanded(child: segment(o)),
                  ],
                ),
              ],
            ),
    );

    if (label == null) return track;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [OmniFieldLabel(label!), track],
    );
  }
}

class OmniFieldLabel extends StatelessWidget {
  final String text;

  const OmniFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Text input with the label above and a rounded field below, full width.
class OmniField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final TextInputType keyboardType;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const OmniField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.suffix,
    this.obscureText = false,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label.isNotEmpty) OmniFieldLabel(label),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          maxLines: 1,
          obscureText: obscureText,
          autofillHints: autofillHints,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';

/// Wraps [child] with a gentle press-down scale. Uses a [Listener] so it never
/// competes with the child's own tap handling.
class OmniPressScale extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double scale;

  const OmniPressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
  });

  @override
  State<OmniPressScale> createState() => _OmniPressScaleState();
}

class _OmniPressScaleState extends State<OmniPressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: OmniDesignTokens.fastMotion,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Fade + slide-up entrance. Give each sibling an increasing [index] for a
/// staggered reveal. Plays once when first built.
class OmniReveal extends StatelessWidget {
  final Widget child;
  final int index;

  const OmniReveal({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    final delay = (index.clamp(0, 8)) * 45;
    final total = 320 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class OmniSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final bool elevated;
  final bool showBorder;
  final Color? color;
  final Color? borderColor;
  final Gradient? gradient;
  final bool enabled;
  final bool selected;
  final String? semanticLabel;

  const OmniSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(OmniDesignTokens.cardPadding),
    this.onTap,
    this.borderRadius,
    this.elevated = false,
    this.showBorder = true,
    this.color,
    this.borderColor,
    this.gradient,
    this.enabled = true,
    this.selected = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final radius =
        borderRadius ?? BorderRadius.circular(OmniDesignTokens.radiusCard);
    final decoration = BoxDecoration(
      color: gradient != null
          ? null
          : color ??
                (selected
                    ? theme.colorScheme.primaryContainer
                    : theme.cardColor),
      gradient: gradient,
      borderRadius: radius,
      border: selected
          ? Border.all(color: theme.colorScheme.primary, width: 1.5)
          : showBorder
          ? Border.all(
              color: borderColor ?? theme.dividerColor.withValues(alpha: 0.9),
              width: 1,
            )
          : null,
      boxShadow: isLight
          ? [
              elevated
                  ? OmniDesignTokens.elevatedShadow
                  : OmniDesignTokens.cardShadow,
            ]
          : const [],
    );

    final content = Padding(padding: padding, child: child);
    final isInteractive = enabled && onTap != null;
    final semantic = Semantics(
      button: onTap != null,
      enabled: enabled,
      selected: selected,
      label: semanticLabel,
      child: content,
    );
    if (!isInteractive) {
      return Container(decoration: decoration, child: semantic);
    }

    // Shadow lives on an outer box: Ink clips shadows to a square rect.
    return OmniPressScale(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: decoration.boxShadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: Ink(
            decoration: decoration.copyWith(boxShadow: const []),
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              overlayColor: _interactiveOverlay(theme),
              child: semantic,
            ),
          ),
        ),
      ),
    );
  }
}

WidgetStateProperty<Color?> _interactiveOverlay(ThemeData theme) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.disabled)) {
      return Colors.transparent;
    }
    if (states.contains(WidgetState.pressed)) {
      return theme.colorScheme.primary.withValues(alpha: 0.10);
    }
    if (states.contains(WidgetState.focused)) {
      return theme.colorScheme.primary.withValues(alpha: 0.1);
    }
    if (states.contains(WidgetState.hovered)) {
      return theme.colorScheme.primary.withValues(alpha: 0.06);
    }
    return null;
  });
}

/// Large page title with optional subtitle and trailing action.
class OmniPageTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const OmniPageTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class OmniSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const OmniSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(OmniDesignTokens.radiusPill),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    if (actionLabel == null || onAction == null) {
      return titleWidget;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        titleWidget,
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: theme.brightness == Brightness.light
                ? OmniDesignTokens.primaryDeep
                : theme.colorScheme.primary,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(actionLabel!),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_forward_rounded, size: 15),
            ],
          ),
        ),
      ],
    );
  }
}

class OmniMenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showDivider;
  final Color? iconColor;
  final Widget? trailing;
  final bool enabled;
  final bool selected;
  final String? semanticLabel;

  /// Renders the icon inside a tinted rounded tile (uses [iconColor]).
  final bool useTile;

  const OmniMenuRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showDivider = false,
    this.iconColor,
    this.trailing,
    this.enabled = true,
    this.selected = false,
    this.semanticLabel,
    this.useTile = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = iconColor ?? theme.colorScheme.primary;
    final row = Semantics(
      button: onTap != null,
      enabled: enabled,
      selected: selected,
      label: semanticLabel ?? (subtitle == null ? title : '$title, $subtitle'),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          overlayColor: _interactiveOverlay(theme),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: useTile ? 64 : OmniDesignTokens.controlHeight,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: useTile ? 10 : 8,
              ),
              child: Row(
                children: [
                  if (useTile)
                    OmniIconTile(
                      icon: icon,
                      color: enabled ? accent : theme.disabledColor,
                      size: 42,
                      iconSize: 21,
                    )
                  else
                    Icon(
                      icon,
                      size: 22,
                      color: enabled ? accent : theme.disabledColor,
                    ),
                  SizedBox(width: useTile ? 14 : 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: enabled ? null : theme.disabledColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: enabled ? null : theme.disabledColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing ??
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: enabled
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.disabledColor,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!showDivider) {
      return row;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        Divider(
          height: 1,
          indent: useTile ? 72 : 50,
          endIndent: 16,
          color: theme.dividerColor,
        ),
      ],
    );
  }
}

class OmniCompactActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;
  final bool enabled;
  final bool selected;

  const OmniCompactActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
    this.enabled = true,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;

    return OmniSurfaceCard(
      onTap: onTap,
      enabled: enabled,
      selected: selected,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      borderRadius: BorderRadius.circular(OmniDesignTokens.radiusCard),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OmniIconTile(icon: icon, color: accent, size: 46, iconSize: 23),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class OmniIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final bool circular;

  /// Solid colour fill with a white icon instead of a soft tint.
  final bool solid;

  const OmniIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize = 22,
    this.circular = false,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: solid ? null : color.withValues(alpha: isDark ? 0.22 : 0.13),
        gradient: solid
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(color, Colors.white, 0.18)!,
                  Color.lerp(color, Colors.black, 0.12)!,
                ],
              )
            : null,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(size * 0.32),
        boxShadow: solid
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.32),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Icon(icon, color: solid ? Colors.white : color, size: iconSize),
    );
  }
}

/// Horizontally scrolling single-select chips.
class OmniFilterChips<T> extends StatelessWidget {
  final List<({T value, String label, IconData? icon})> items;
  final T selected;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry padding;

  const OmniFilterChips({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(
      horizontal: OmniDesignTokens.pageInset,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final isSelected = item.value == selected;
          final fg = isSelected
              ? Colors.white
              : theme.colorScheme.onSurfaceVariant;
          return OmniPressScale(
            scale: 0.95,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              decoration: ShapeDecoration(
                color: isSelected ? OmniDesignTokens.primary : theme.cardColor,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: isSelected ? Colors.transparent : theme.dividerColor,
                  ),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelected(item.value);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.icon != null) ...[
                          TweenAnimationBuilder<Color?>(
                            tween: ColorTween(end: fg),
                            duration: const Duration(milliseconds: 240),
                            builder: (context, c, _) =>
                                Icon(item.icon, size: 16, color: c),
                          ),
                          const SizedBox(width: 6),
                        ],
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          style:
                              (theme.textTheme.labelMedium ?? const TextStyle())
                                  .copyWith(
                                    color: fg,
                                    fontWeight: FontWeight.w600,
                                  ),
                          child: Text(item.label),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class OmniEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final double iconSize;

  const OmniEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.iconSize = 44,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: iconSize + 64,
                  height: iconSize + 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primary.withValues(alpha: 0.07),
                  ),
                ),
                Container(
                  width: iconSize + 36,
                  height: iconSize + 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primary.withValues(alpha: 0.13),
                  ),
                  child: Icon(icon, size: iconSize, color: primary),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(actionLabel!),
              ),
            ],
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 4),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact inline empty message for sections inside a scrolling page.
class OmniInlineEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color? accent;
  final VoidCallback? onTap;

  const OmniInlineEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;
    return OmniSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          OmniIconTile(icon: icon, color: color, size: 44, iconSize: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OmniSearchField extends StatelessWidget {
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilter;
  final VoidCallback? onClear;
  final bool hasActiveFilter;
  final bool enabled;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  const OmniSearchField({
    super.key,
    required this.hintText,
    this.onChanged,
    this.onFilter,
    this.onClear,
    this.hasActiveFilter = false,
    this.enabled = true,
    this.controller,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(OmniDesignTokens.radiusPill),
      borderSide: BorderSide(color: theme.dividerColor),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OmniDesignTokens.radiusPill),
        boxShadow: theme.brightness == Brightness.light
            ? const [
                BoxShadow(
                  color: Color(0x0D202124),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ]
            : const [],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        onChanged: onChanged,
        minLines: 1,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          border: pill,
          enabledBorder: pill,
          focusedBorder: pill.copyWith(
            borderSide: BorderSide(
              color: theme.colorScheme.primary,
              width: 1.5,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: onFilter == null && onClear == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onClear != null)
                      IconButton(
                        onPressed: onClear,
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    if (onFilter != null)
                      IconButton(
                        onPressed: onFilter,
                        tooltip: 'Filter files',
                        icon: Icon(
                          Icons.tune_rounded,
                          color: hasActiveFilter
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The shared Pro marker used by Omni Tools. Keep the compact badge and the
/// larger header badge on the same visual system.
class OmniProBadge extends StatelessWidget {
  final bool large;

  const OmniProBadge({super.key, this.large = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const amber = OmniDesignTokens.accentAmber;

    return Semantics(
      label: 'Pro',
      excludeSemantics: true,
      child: Container(
        padding: large
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            amber.withValues(alpha: isDark ? 0.24 : 0.2),
            theme.colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: amber.withValues(alpha: 0.6), width: 0.8),
        ),
        child: Text(
          'PRO',
          style: TextStyle(
            fontFamily: OmniDesignTokens.fontFamily,
            fontSize: large ? 12.5 : 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: large ? 0.9 : 0.6,
            height: 1.2,
            color: isDark ? amber : const Color(0xFF9A5B00),
          ),
        ),
      ),
    );
  }
}

class OmniStatusPill extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? backgroundColor;
  final IconData? icon;
  final String? semanticLabel;

  const OmniStatusPill({
    super.key,
    required this.label,
    this.color,
    this.backgroundColor,
    this.icon,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = color ?? theme.colorScheme.primary;

    return Semantics(
      label: semanticLabel ?? label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor ?? foreground.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(OmniDesignTokens.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: OmniDesignTokens.actionWeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OmniBottomSheetScaffold extends StatelessWidget {
  final Widget child;
  final String? title;
  final EdgeInsetsGeometry padding;
  final bool showHandle;

  const OmniBottomSheetScaffold({
    super.key,
    required this.child,
    this.title,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
    this.showHandle = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(OmniDesignTokens.radiusLargeCard),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHandle) ...[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(
                        OmniDesignTokens.radiusPill,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (title != null) ...[
                Text(
                  title!,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: OmniDesignTokens.titleWeight,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

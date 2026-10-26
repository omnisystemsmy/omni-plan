import 'package:flutter/material.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';

/// App bar shared by the flat list pages (Settings, Account, Help, About).
AppBar omniListAppBar(BuildContext context, String title) {
  final theme = Theme.of(context);
  return AppBar(
    backgroundColor: theme.appBarTheme.backgroundColor,
    foregroundColor: theme.appBarTheme.foregroundColor,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
    centerTitle: true,
    toolbarHeight: 64,
    title: Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

/// A titled group of rows separated by hairlines, with no card around it.
/// Same look as the History list.
class OmniListSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const OmniListSection({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OmniDesignTokens.pageInset,
              0,
              OmniDesignTokens.pageInset,
              8,
            ),
            child: OmniSectionHeader(title: title!),
          ),
        ...children,
      ],
    );
  }
}

/// Icon tile + title + subtitle + switch, matching [OmniMenuRow].
class OmniSwitchRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const OmniSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return OmniMenuRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

/// Plain label / value line used on the Account page.
class OmniInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const OmniInfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: OmniDesignTokens.pageInset,
        vertical: 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(width: 16),
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

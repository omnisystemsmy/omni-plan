import 'package:flutter/material.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';

/// A bottom sheet that lets the user pick one of [options]. Resolves to the
/// chosen value, or null if dismissed.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<({T value, String label, IconData? icon})> options,
  required T current,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return OmniBottomSheetScaffold(
        title: title,
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
        child: Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final o in options)
                  OmniMenuRow(
                    icon: o.icon ?? Icons.circle_outlined,
                    title: o.label,
                    selected: o.value == current,
                    onTap: () => Navigator.pop(sheetContext, o.value),
                    trailing: o.value == current
                        ? Icon(
                            Icons.check_rounded,
                            color: theme.colorScheme.primary,
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

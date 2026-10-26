import 'dart:io';

import 'package:flutter/material.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a generated file to the system share sheet (save to Files, Drive,
/// email...), as Omni Docs does for its exports.
Future<void> shareGeneratedFile(
  BuildContext context,
  Future<File> Function() build, {
  required String mimeType,
  required String doneMessage,
}) async {
  File file;
  try {
    file = await build();
  } catch (e) {
    if (context.mounted) showPlanSnack(context, 'The file could not be created: $e');
    return;
  }
  try {
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mimeType)]),
    );
    if (!context.mounted) return;
    if (result.status == ShareResultStatus.success) {
      showPlanSnack(context, doneMessage);
    }
  } catch (e) {
    if (context.mounted) showPlanSnack(context, 'The file was created but could not be shared: $e');
  }
}

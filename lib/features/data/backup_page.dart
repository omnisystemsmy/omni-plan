import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/backup_service.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/services/reminder_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// Backup and restore, in the Omni Docs layout. A backup is written,
/// read back and checked before it is offered to the share sheet.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  String? _last;

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    final store = context.read<PlanStore>();
    try {
      final json = BackupService.build(store);
      final dir = await getApplicationDocumentsDirectory();
      final file = await BackupService.write(json, dir);
      final name = file.uri.pathSegments.last;
      await store.addNotice(
        key: 'backup:${DateTime.now().toIso8601String()}',
        type: NoticeType.backup,
        title: 'Backup created',
        body: name,
        targetKind: EntityKind.backup,
      );
      if (!mounted) return;
      setState(() => _last = name);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')]));
    } catch (e) {
      if (mounted) showPlanSnack(context, 'The backup could not be created: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final store = context.read<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final bytes = picked?.files.single.bytes;
    if (bytes == null || !mounted) return;
    BackupPreview preview;
    try {
      preview = BackupService.inspect(utf8.decode(bytes, allowMalformed: false), store);
    } on BackupException catch (e) {
      showPlanSnack(context, e.message);
      return;
    } catch (_) {
      showPlanSnack(context, 'This is not an Omni Plan backup. The file could not be read.');
      return;
    }
    if (!mounted) return;

    final lines = [
      if (preview.createdAt != null) 'Made ${fmt.dateTime(preview.createdAt!)}${preview.appVersion == null ? '' : ' (Omni Plan ${preview.appVersion})'}',
      '${preview.count('projects')} projects, ${preview.count('tasks')} tasks, ${preview.count('milestones')} milestones, ${preview.count('goals')} goals, ${preview.count('templates')} own templates',
      if (preview.overlapping > 0) '${preview.overlapping} records are already on this device',
      if (preview.skipped > 0) '${preview.skipped} unreadable entries will be left out',
      if (preview.repairedLinks > 0) '${preview.repairedLinks} links to missing records will be removed',
    ];
    final mode = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $l')),
            const SizedBox(height: 8),
            const Text(
              'Add missing keeps everything you have and adds what is not here yet. Replace all makes this device match the backup exactly.',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, 'merge'), child: const Text('Add missing')),
          FilledButton(onPressed: () => Navigator.pop(d, 'replace'), child: const Text('Replace all')),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    if (mode == 'replace') {
      final ok = await confirmAction(
        context,
        title: 'Replace all plans?',
        message: 'Every project, task, goal and setting of this account on this device is replaced by the backup. Plans that are not in the backup are lost.',
        confirmLabel: 'Replace all',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      String message;
      if (mode == 'replace') {
        await BackupService.restoreReplacing(preview, store);
        message = 'Backup restored: ${preview.count('projects')} projects and ${preview.count('tasks')} tasks';
      } else {
        final added = await BackupService.restoreMerging(preview, store);
        message = added == 0 ? 'Nothing new to add. Everything in the backup is already here.' : '$added records added from the backup';
      }
      ReminderService.instance.scheduleSync(store);
      await store.addNotice(
        key: 'restore:${DateTime.now().toIso8601String()}',
        type: NoticeType.backup,
        title: 'Backup restored',
        body: message,
        targetKind: EntityKind.backup,
      );
      if (mounted) showPlanSnack(context, message);
    } on PlanStoreException catch (e) {
      if (mounted) showPlanSnack(context, e.message);
    } catch (e) {
      if (mounted) showPlanSnack(context, 'The restore failed and nothing was changed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    return Scaffold(
      appBar: omniListAppBar(context, 'Backup and restore'),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 0, OmniDesignTokens.pageInset, 16),
            child: Text(
              'Save your planning data to a backup file and restore it when needed, on this phone or a new one.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          OmniListSection(
            title: 'Backup',
            children: [
              OmniMenuRow(
                icon: Icons.save_alt_rounded,
                useTile: true,
                title: 'Create backup',
                subtitle: '${store.allProjects.length} projects and ${store.allTasks.length} tasks',
                enabled: !_busy,
                onTap: _create,
              ),
              OmniMenuRow(
                icon: Icons.restore_rounded,
                useTile: true,
                title: 'Restore backup',
                subtitle: 'Choose an .${BackupService.extension} file',
                enabled: !_busy,
                onTap: _restore,
              ),
            ],
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          if (_last != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 12, OmniDesignTokens.pageInset, 0),
              child: Text('Last backup: $_last', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: OmniDesignTokens.sectionGap),
          const OmniListSection(title: "What's in a backup", children: []),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
            child: Text(
              'Projects, sections, tasks and subtasks with checklists, repeats, reminders and dependencies; milestones; goals; '
              'your own templates and favourites; planning preferences; history and notifications.\n\n'
              'Not included: the app theme and your Omni account. A restore is checked first: a damaged or edited file is refused, and nothing is changed until you confirm.\n\n'
              'CSV and PDF exports are not backups.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

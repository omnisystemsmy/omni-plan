import 'package:flutter/material.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/theme/theme_provider.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/export_service.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/preferences.dart';
import 'package:omni_plan/features/data/backup_page.dart';
import 'package:omni_plan/features/data/import_page.dart';
import 'package:omni_plan/features/pro/plan_service.dart';
import 'package:omni_plan/features/pro/pro_gate.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/shared/share_file.dart';
import 'package:omni_plan/features/tasks/task_pickers.dart';
import 'package:omni_plan/services/reminder_service.dart';
import 'package:provider/provider.dart';

void _push(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));

/// Settings, in the Omni Docs settings layout: appearance first, then the
/// planning areas.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Scaffold(
      appBar: omniListAppBar(context, 'Settings'),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          OmniListSection(
            title: 'Appearance',
            children: [
              OmniSwitchRow(
                icon: Icons.brightness_auto_rounded,
                title: 'Use system theme',
                subtitle: 'Follow your device appearance',
                value: theme.isSystem,
                onChanged: (v) => context.read<ThemeProvider>().setThemeMode(v ? ThemeMode.system : ThemeMode.light),
              ),
              OmniSwitchRow(
                icon: Icons.dark_mode_rounded,
                title: 'Dark mode',
                subtitle: theme.isSystem ? 'Turn off system theme to choose' : null,
                value: theme.isDark,
                onChanged: theme.isSystem ? null : (v) => context.read<ThemeProvider>().toggleTheme(v),
              ),
            ],
          ),
          const SizedBox(height: OmniDesignTokens.sectionGap),
          OmniListSection(
            title: 'General',
            children: [
              OmniMenuRow(
                icon: Icons.tune_rounded,
                title: 'Planning defaults',
                subtitle: 'Priority, views, dates, week start and reminders',
                onTap: () => _push(context, const PlanningDefaultsPage()),
              ),
              OmniMenuRow(
                icon: Icons.notifications_outlined,
                title: 'Notification settings',
                subtitle: 'Reminders and alerts',
                onTap: () => _push(context, const NotificationSettingsPage()),
              ),
              OmniMenuRow(
                icon: Icons.shield_outlined,
                title: 'Data and privacy',
                subtitle: 'Storage, backup, export and deletion',
                onTap: () => _push(context, const DataPrivacyPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Every planning preference. Each row changes something the app does.
class PlanningDefaultsPage extends StatelessWidget {
  const PlanningDefaultsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final p = store.prefs;
    final fmt = PlanFormat(p);
    Future<void> set(PlanPreferences next) => store.updatePrefs(next);

    Future<void> choose<T>(String title, List<(T, String)> options, T current, PlanPreferences Function(T) apply) async {
      final picked = await pickOption<T>(context, title: title, options: options, current: current);
      if (picked?.value != null) await set(apply(picked!.value as T));
    }

    return Scaffold(
      appBar: omniListAppBar(context, 'Planning defaults'),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          OmniListSection(
            title: 'New tasks',
            children: [
              OmniMenuRow(
                icon: Icons.flag_outlined,
                title: 'Default priority',
                subtitle: p.defaultPriority.label,
                onTap: () => choose('Default priority', [for (final x in Priority.values) (x, x.label)], p.defaultPriority,
                    (v) => p.copyWith(defaultPriority: v)),
              ),
              OmniMenuRow(
                icon: Icons.radio_button_checked_rounded,
                title: 'Default status',
                subtitle: p.defaultTaskStatus.label,
                onTap: () => choose(
                  'Default status',
                  [for (final x in TaskStatus.values) if (x != TaskStatus.done) (x, x.label)],
                  p.defaultTaskStatus,
                  (v) => p.copyWith(defaultTaskStatus: v),
                ),
              ),
              OmniMenuRow(
                icon: Icons.alarm_rounded,
                title: 'Default reminder',
                subtitle: '${PlanFormat.reminderLabel(p.defaultReminderMinutes, timed: true)} (tasks with a due date)',
                onTap: () async {
                  final picked = await pickOption<int>(
                    context,
                    title: 'Default reminder',
                    noneLabel: 'No reminder',
                    current: p.defaultReminderMinutes,
                    options: [for (final o in PlanFormat.timedReminderOptions) (o, PlanFormat.reminderLabel(o, timed: true))],
                  );
                  if (picked == null) return;
                  await set(picked.value == null
                      ? p.copyWith(clearDefaultReminder: true)
                      : p.copyWith(defaultReminderMinutes: picked.value));
                },
              ),
              OmniSwitchRow(
                icon: Icons.checklist_rounded,
                title: 'Tick the checklist when a task is completed',
                subtitle: 'Otherwise checklist items keep their own state',
                value: p.completeChecklistWithTask,
                onChanged: (v) => set(p.copyWith(completeChecklistWithTask: v)),
              ),
            ],
          ),
          const SizedBox(height: OmniDesignTokens.sectionGap),
          OmniListSection(
            title: 'Views',
            children: [
              OmniMenuRow(
                icon: Icons.view_list_rounded,
                title: 'My Tasks opens as',
                subtitle: p.defaultTaskView.label,
                onTap: () => choose('My Tasks opens as', [for (final x in TaskView.values) (x, x.label)], p.defaultTaskView,
                    (v) => p.copyWith(defaultTaskView: v)),
              ),
              OmniMenuRow(
                icon: Icons.grid_view_rounded,
                title: 'Projects view',
                subtitle: p.projectsAsGrid ? 'Grid' : 'List',
                onTap: () => choose('Projects view', const [(false, 'List'), (true, 'Grid')], p.projectsAsGrid,
                    (v) => p.copyWith(projectsAsGrid: v)),
              ),
              OmniMenuRow(
                icon: Icons.calendar_month_rounded,
                title: 'Calendar opens as',
                subtitle: p.defaultCalendarView.label,
                onTap: () => choose('Calendar opens as', [for (final x in CalendarView.values) (x, x.label)],
                    p.defaultCalendarView, (v) => p.copyWith(defaultCalendarView: v)),
              ),
            ],
          ),
          const SizedBox(height: OmniDesignTokens.sectionGap),
          OmniListSection(
            title: 'Dates and times',
            children: [
              OmniMenuRow(
                icon: Icons.view_week_rounded,
                title: 'Week starts on',
                subtitle: p.weekStart == 7 ? 'Sunday' : 'Monday',
                onTap: () => choose('Week starts on', const [(1, 'Monday'), (7, 'Sunday')], p.weekStart,
                    (v) => p.copyWith(weekStart: v)),
              ),
              OmniMenuRow(
                icon: Icons.event_rounded,
                title: 'Date format',
                subtitle: fmt.date(DateTime.now()),
                onTap: () => choose('Date format', [for (final x in DateStyle.values) (x, x.example)], p.dateStyle,
                    (v) => p.copyWith(dateStyle: v)),
              ),
              OmniSwitchRow(
                icon: Icons.schedule_rounded,
                title: '24-hour time',
                subtitle: fmt.time(15 * 60 + 30),
                value: p.use24h,
                onChanged: (v) => set(p.copyWith(use24h: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What is scheduled on the device and listed in Notifications. Saved per
/// account, and applied at once.
class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final reminders = context.watch<ReminderService>();
    final p = store.prefs;
    Future<void> set(PlanPreferences next) async {
      await store.updatePrefs(next);
      ReminderService.instance.scheduleSync(store);
      await store.refreshNotices();
    }

    final status = !reminders.supported
        ? 'Device reminders are not available on this device.'
        : reminders.permissionGranted == false
        ? 'Notifications are turned off for Omni Plan in your phone settings, so reminders cannot appear.'
        : '${reminders.scheduledCount} upcoming ${reminders.scheduledCount == 1 ? 'reminder is' : 'reminders are'} scheduled on this device.';

    return Scaffold(
      appBar: omniListAppBar(context, 'Notification settings'),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          OmniListSection(
            title: 'Alerts',
            children: [
              OmniSwitchRow(
                icon: Icons.alarm_rounded,
                title: 'Task reminders',
                subtitle: 'Device notifications at the reminder time you set',
                value: p.notifyReminders,
                onChanged: (v) => set(p.copyWith(notifyReminders: v)),
              ),
              OmniSwitchRow(
                icon: Icons.today_rounded,
                title: 'Due today',
                subtitle: 'Listed in Notifications each morning',
                value: p.notifyDueToday,
                onChanged: (v) => set(p.copyWith(notifyDueToday: v)),
              ),
              OmniSwitchRow(
                icon: Icons.warning_amber_rounded,
                title: 'Overdue tasks',
                subtitle: 'Listed once a day while a task is overdue',
                value: p.notifyOverdue,
                onChanged: (v) => set(p.copyWith(notifyOverdue: v)),
              ),
              OmniSwitchRow(
                icon: Icons.flag_rounded,
                title: 'Milestones',
                subtitle: p.milestoneLeadDays == 0
                    ? 'On the milestone day'
                    : '${p.milestoneLeadDays} ${p.milestoneLeadDays == 1 ? 'day' : 'days'} ahead',
                value: p.notifyMilestones,
                onChanged: (v) => set(p.copyWith(notifyMilestones: v)),
              ),
              if (p.notifyMilestones)
                OmniMenuRow(
                  icon: Icons.timelapse_rounded,
                  title: 'Milestone notice',
                  subtitle: 'How early milestones are announced',
                  onTap: () async {
                    final picked = await pickOption<int>(
                      context,
                      title: 'Announce milestones',
                      current: p.milestoneLeadDays,
                      options: const [(0, 'On the day'), (1, '1 day ahead'), (3, '3 days ahead'), (7, 'A week ahead')],
                    );
                    if (picked?.value != null) await set(p.copyWith(milestoneLeadDays: picked!.value));
                  },
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(OmniDesignTokens.pageInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: Theme.of(context).textTheme.bodySmall),
                if (reminders.supported && reminders.permissionGranted != true) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await ReminderService.instance.requestPermission();
                      if (ok) ReminderService.instance.scheduleSync(store);
                    },
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Allow notifications'),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Reminders are scheduled on this phone and work offline. Nothing is sent to a server.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the plans live and what can be done with them.
class DataPrivacyPage extends StatelessWidget {
  const DataPrivacyPage({super.key});

  Future<void> _exportAll(BuildContext context) async {
    if (!await ProGate.ensure(context, ProCapability.csvExport) || !context.mounted) return;
    final store = context.read<PlanStore>();
    await shareGeneratedFile(
      context,
      () => ExportService.writeCsv('Omni Plan tasks', ExportService.tasksCsv(store, includeArchived: true)),
      mimeType: 'text/csv',
      doneMessage: 'Tasks exported',
    );
  }

  Future<void> _clear(BuildContext context) async {
    final store = context.read<PlanStore>();
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Delete all plans on this device?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Every project, task, goal, milestone, template and setting of this account on this device is deleted. Your Omni account is not affected. This cannot be undone; make a backup first if you may need them.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                onChanged: (_) => set(() {}),
                decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: controller.text.trim() == 'DELETE' ? () => Navigator.pop(d, true) : null,
              child: const Text('Delete everything'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (ok != true || !context.mounted) return;
    if (await runPlanAction(context, store.clearAll) && context.mounted) {
      await ReminderService.instance.cancelAll();
      if (context.mounted) showPlanSnack(context, 'All plans on this device were deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: omniListAppBar(context, 'Data and privacy'),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          OmniListSection(
            title: 'Storage',
            children: [
              OmniInfoRow(label: 'Projects', value: '${store.allProjects.length}'),
              OmniInfoRow(label: 'Tasks', value: '${store.allTasks.length}'),
              OmniInfoRow(label: 'Goals', value: '${store.goals.length + store.archivedGoals.length}'),
              OmniInfoRow(label: 'Stored entries', value: '${store.storedEntryCount}'),
              if (store.unreadableCount > 0)
                OmniInfoRow(label: 'Unreadable entries skipped', value: '${store.unreadableCount}'),
              const OmniInfoRow(label: 'Where', value: 'On this device, for this account'),
            ],
          ),
          const SizedBox(height: OmniDesignTokens.sectionGap),
          OmniListSection(
            title: 'Your data',
            children: [
              OmniMenuRow(
                icon: Icons.settings_backup_restore_rounded,
                title: 'Backup and restore',
                subtitle: 'A complete copy of your plans in one file',
                onTap: () => _push(context, const BackupPage()),
              ),
              OmniMenuRow(
                icon: Icons.table_view_outlined,
                title: 'Export all tasks (CSV)',
                subtitle: 'For spreadsheets; not a backup',
                trailing: const OmniProBadge(),
                onTap: () => _exportAll(context),
              ),
              OmniMenuRow(
                icon: Icons.upload_file_outlined,
                title: 'Import tasks (CSV)',
                subtitle: 'Preview, map columns and check before importing',
                trailing: const OmniProBadge(),
                onTap: () => openImport(context),
              ),
              OmniMenuRow(
                icon: Icons.history_toggle_off_rounded,
                title: 'Clear history',
                subtitle: 'Remove the list of recent changes',
                onTap: () async {
                  final ok = await confirmAction(
                    context,
                    title: 'Clear history?',
                    message: 'The list of recent changes is emptied. Your plans are not affected.',
                    confirmLabel: 'Clear',
                  );
                  if (ok) await store.clearActivity();
                },
              ),
              OmniMenuRow(
                icon: Icons.delete_sweep_rounded,
                iconColor: theme.colorScheme.error,
                title: 'Delete all plans on this device',
                subtitle: 'Your Omni account stays',
                onTap: () => _clear(context),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(OmniDesignTokens.pageInset),
            child: Text(
              'Omni Plan keeps your projects, tasks and goals on this device, separately for each account that signs in here. '
              'Your Omni account (name, email and plan) is shared with the other Omni apps; your plans are not uploaded. '
              'Exports and backups contain your plan titles, notes and dates: share them only with people you trust.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

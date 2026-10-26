import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/profile/settings_pages.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:provider/provider.dart';

/// The Omni Docs notifications screen (back, title, settings button), filled
/// with this account's planning alerts, grouped Today / Earlier.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final notices = store.notices;
    final today = dateOnly(DateTime.now());
    final todays = notices.where((n) => dateOnly(n.at) == today).toList();
    final earlier = notices.where((n) => dateOnly(n.at) != today).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (store.unreadNotices > 0)
            IconButton(
              tooltip: 'Mark all as read',
              onPressed: store.markAllNoticesRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              if (v == 'settings') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationSettingsPage()));
              } else if (v == 'clear') {
                final ok = await confirmAction(
                  context,
                  title: 'Clear notifications?',
                  message: 'Every notification in this list is removed. Reminders already scheduled on the device are not affected.',
                  confirmLabel: 'Clear',
                );
                if (ok) await store.clearNotices();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'settings', child: Text('Notification settings')),
              if (notices.isNotEmpty) const PopupMenuItem(value: 'clear', child: Text('Clear all')),
            ],
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: notices.isEmpty
          ? const OmniEmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications yet',
              message: 'Due, overdue and milestone alerts appear here, following your notification settings.',
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                if (todays.isNotEmpty) ...[
                  const _Heading('Today'),
                  for (final n in todays) _NoticeTile(notice: n),
                ],
                if (earlier.isNotEmpty) ...[
                  const _Heading('Earlier'),
                  for (final n in earlier) _NoticeTile(notice: n),
                ],
              ],
            ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 8),
    child: OmniSectionHeader(title: text),
  );
}

/// The notification row of Omni Tools and Omni Docs: tinted icon tile,
/// title with the time on the right, and the detail below.
class _NoticeTile extends StatelessWidget {
  final PlanNotice notice;
  const _NoticeTile({required this.notice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.read<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final n = notice;
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: theme.colorScheme.errorContainer,
        child: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) => store.dismissNotice(n),
      child: InkWell(
        onTap: () {
          if (!n.read) store.markNoticeRead(n);
          if (!openEntity(context, n.targetKind, n.targetId) && n.targetKind != null) {
            showPlanSnack(context, 'That item no longer exists.');
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 10, OmniDesignTokens.pageInset, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OmniIconTile(icon: n.type.icon, color: n.type.color, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_when(n.at, fmt), style: theme.textTheme.bodySmall),
                      ],
                    ),
                    if (n.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(n.body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (!n.read)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime t, PlanFormat fmt) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    final days = dateOnly(DateTime.now()).difference(dateOnly(t)).inDays;
    if (days == 0) return fmt.time(t.hour * 60 + t.minute);
    if (days == 1) return 'Yesterday';
    if (days < 7) return '$days days ago';
    return fmt.date(t);
  }
}

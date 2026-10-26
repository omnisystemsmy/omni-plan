import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/app_info.dart';
import 'package:omni_plan/core/branding/plan_brand.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/templates/catalogue_data.dart';
import 'package:omni_plan/features/templates/template_library.dart';
import 'package:omni_plan/features/templates/template_sheets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

IconData _kindIcon(EntityKind k) => switch (k) {
  EntityKind.task => Icons.task_alt_rounded,
  EntityKind.project => Icons.folder_rounded,
  EntityKind.milestone => Icons.flag_rounded,
  EntityKind.goal => Icons.emoji_events_outlined,
  EntityKind.template => Icons.dashboard_customize_rounded,
  EntityKind.backup => Icons.settings_backup_restore_rounded,
};

/// Recent changes to this account's plans, newest first.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final entries = store.activity;
    return Scaffold(
      appBar: omniListAppBar(context, 'History'),
      body: entries.isEmpty
          ? const OmniEmptyState(
              icon: Icons.history_rounded,
              title: 'No history yet',
              message: 'Your planning activity will appear here.',
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                const OmniListSection(title: 'Recent activity', children: []),
                for (final a in entries)
                  OmniMenuRow(
                    icon: _kindIcon(a.kind),
                    title: a.title,
                    subtitle: '${a.action} · ${fmt.relativeDay(a.at)}, ${fmt.time(a.at.hour * 60 + a.at.minute)}',
                    enabled: a.entityId != null,
                    trailing: a.entityId == null ? const SizedBox.shrink() : null,
                    onTap: () {
                      if (!openEntity(context, a.kind, a.entityId)) {
                        showPlanSnack(context, 'That item no longer exists.');
                      }
                    },
                  ),
              ],
            ),
    );
  }
}

/// Favourite templates and projects.
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final templates = [
      for (final id in store.favoriteTemplates)
        if (TemplateLibrary.byId(id, store.customTemplates) != null) TemplateLibrary.byId(id, store.customTemplates)!,
    ];
    final projects = [for (final p in store.projects) if (p.favorite) p];
    return Scaffold(
      appBar: omniListAppBar(context, 'Favorites'),
      body: templates.isEmpty && projects.isEmpty
          ? const OmniEmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'No favorites yet',
              message: 'Star a template, or add a project to favourites from its menu, to find it quickly here.',
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                if (projects.isNotEmpty) ...[
                  const OmniListSection(title: 'Favorite projects', children: []),
                  for (final p in projects)
                    OmniMenuRow(
                      icon: p.iconData,
                      iconColor: p.colorValue,
                      title: p.name,
                      subtitle: store.projectProgress(p.id).label,
                      onTap: () => openProject(context, p),
                      trailing: IconButton(
                        tooltip: 'Remove from favourites',
                        icon: const Icon(Icons.favorite_rounded),
                        onPressed: () => store.toggleFavoriteProject(p),
                      ),
                    ),
                  const SizedBox(height: OmniDesignTokens.sectionGap),
                ],
                if (templates.isNotEmpty) ...[
                  const OmniListSection(title: 'Favorite templates', children: []),
                  for (final t in templates)
                    OmniMenuRow(
                      icon: t.icon,
                      iconColor: t.color,
                      title: t.name,
                      subtitle: categoryById(t.categoryId).name,
                      onTap: () => showTemplateDetailSheet(context, t),
                      trailing: IconButton(
                        tooltip: 'Remove from favourites',
                        icon: const Icon(Icons.favorite_rounded),
                        onPressed: () => store.toggleFavoriteTemplate(t.id),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

const String _supportEmail = 'omnisystems.root@gmail.com';

class _Faq {
  final String q;
  final String a;
  const _Faq(this.q, this.a);
}

const List<_Faq> _faqs = [
  _Faq('Where are my plans stored?',
      'On this phone, inside Omni Plan, separately for each Omni account that signs in here. They are not uploaded. Use Backup and restore to keep a copy or move to another phone.'),
  _Faq('How do I start quickly?',
      'Tap the + button and choose "Use a template". Pick a plan, set the start date, and every task and milestone is created for you, dated from that day.'),
  _Faq('How is progress worked out?',
      'Progress is the number of tasks marked Done out of all tasks of the project (subtasks included, archived tasks left out). A project with no tasks shows no percentage.'),
  _Faq('How do repeating tasks work?',
      'A repeating task needs a due date. When you complete it, the next one is added with the next due date and a fresh checklist.'),
  _Faq('Why did a reminder not appear?',
      'Reminders need notifications to be allowed for Omni Plan in your phone settings. You can check how many are scheduled in Notification settings.'),
  _Faq('What is the difference between archive and delete?',
      'Archiving puts a task or project away with everything linked to it; you can restore it from Profile > Archive. Deleting removes it for good.'),
  _Faq('Is a CSV or PDF export a backup?',
      'No. Exports are for spreadsheets and sharing. Only a backup file keeps projects, sections, subtasks, milestones, dependencies, goals and settings together.'),
];

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  Future<void> _contact(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 0, OmniDesignTokens.pageInset, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Contact support', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SelectableText(
              _supportEmail,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text('We usually reply within 24 hours.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () async {
                  Navigator.pop(sheet);
                  final uri = Uri(scheme: 'mailto', path: _supportEmail, queryParameters: {'subject': 'Omni Plan support'});
                  final opened = await launchUrl(uri);
                  if (!opened) {
                    await Clipboard.setData(const ClipboardData(text: _supportEmail));
                    if (context.mounted) showPlanSnack(context, 'No email app found. The address was copied.');
                  }
                },
                child: const Text('Write an email'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: _supportEmail));
                  Navigator.pop(sheet);
                  showPlanSnack(context, 'Support email copied.');
                },
                child: const Text('Copy support email'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rate(BuildContext context) async {
    final uri = Uri.parse('https://play.google.com/store/apps/details?id=${AppInfo.packageName}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showPlanSnack(context, 'The store page could not be opened.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: omniListAppBar(context, 'Help & Support'),
    body: ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        OmniListSection(
          children: [
            OmniMenuRow(
              icon: Icons.help_rounded,
              title: 'Help Center',
              subtitle: 'Answers to common questions',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _FaqPage())),
            ),
            OmniMenuRow(
              icon: Icons.mail_rounded,
              title: 'Contact Support',
              subtitle: 'Email the support team',
              onTap: () => _contact(context),
            ),
            OmniMenuRow(
              icon: Icons.star_rounded,
              title: 'Rate App',
              subtitle: 'Open Omni Plan on Google Play',
              onTap: () => _rate(context),
            ),
            OmniMenuRow(
              icon: Icons.feedback_rounded,
              title: 'Send Feedback',
              subtitle: 'Tell us what to improve',
              onTap: () => _feedback(context),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _feedback(BuildContext context) async {
    final c = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          OmniDesignTokens.pageInset,
          0,
          OmniDesignTokens.pageInset,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Send feedback', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Help us improve Omni Plan. Your email app opens with the message.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: c,
              minLines: 5,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'Tell us what you think...'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () async {
                  final text = c.text.trim();
                  if (text.isEmpty) return;
                  await (await SharedPreferences.getInstance()).setString('omni_plan_last_feedback', text);
                  final uri = Uri(
                    scheme: 'mailto',
                    path: _supportEmail,
                    queryParameters: {'subject': 'Omni Plan feedback', 'body': text},
                  );
                  final opened = await launchUrl(uri);
                  if (sheet.mounted) Navigator.pop(sheet);
                  if (context.mounted) {
                    showPlanSnack(
                      context,
                      opened ? 'Send the email to finish.' : 'No email app found. Your feedback was saved on this device.',
                    );
                  }
                },
                child: const Text('Send feedback'),
              ),
            ),
          ],
        ),
      ),
    );
    c.dispose();
  }
}

class _FaqPage extends StatelessWidget {
  const _FaqPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: omniListAppBar(context, 'Help Center'),
    body: ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        for (final f in _faqs)
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
            childrenPadding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 0, OmniDesignTokens.pageInset, 16),
            title: Text(f.q, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            children: [Text(f.a, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5))],
          ),
      ],
    ),
  );
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  void _show(BuildContext context, String title, String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: omniListAppBar(context, 'About'),
    body: ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        const Center(
          child: Column(
            children: [
              PlanLogo(height: 40),
              SizedBox(height: 10),
              Text('Version ${AppInfo.version}'),
            ],
          ),
        ),
        const SizedBox(height: OmniDesignTokens.sectionGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
          child: Text(
            'Omni Plan helps you organise tasks, projects, schedules and goals with ready-made planning templates, right on your device.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
        const SizedBox(height: OmniDesignTokens.sectionGap),
        OmniListSection(
          title: 'Legal & links',
          children: [
            OmniMenuRow(
              icon: Icons.privacy_tip_rounded,
              title: 'Privacy Policy',
              subtitle: 'How we protect your data',
              onTap: () => _show(context, 'Privacy Policy', 'The official privacy policy URL has not been configured yet.'),
            ),
            OmniMenuRow(
              icon: Icons.description_rounded,
              title: 'Terms of Use',
              subtitle: 'Our terms and conditions',
              onTap: () => _show(context, 'Terms of Use', 'The official terms URL has not been configured yet.'),
            ),
            OmniMenuRow(
              icon: Icons.language_rounded,
              title: 'Website',
              subtitle: 'omnisystems.my',
              onTap: () => launchUrl(Uri.parse('https://omnisystems.my'), mode: LaunchMode.externalApplication),
            ),
            OmniMenuRow(
              icon: Icons.code_rounded,
              title: 'Open-source licences',
              subtitle: 'Libraries used by Omni Plan',
              onTap: () => showLicensePage(context: context, applicationName: AppInfo.name, applicationVersion: AppInfo.version),
            ),
            const OmniInfoRow(label: 'Storage', value: 'Plans stay on this device'),
          ],
        ),
      ],
    ),
  );
}

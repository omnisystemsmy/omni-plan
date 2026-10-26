import 'package:flutter/material.dart';
import 'package:omni_plan/app/shell/shell_controller.dart';
import 'package:omni_plan/auth/auth_service.dart';
import 'package:omni_plan/core/backend/supabase_config.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/features/data/backup_page.dart';
import 'package:omni_plan/features/pro/plan_service.dart';
import 'package:omni_plan/features/pro/pro_page.dart';
import 'package:omni_plan/features/profile/account_sheet.dart';
import 'package:omni_plan/features/profile/archive_page.dart';
import 'package:omni_plan/features/profile/profile_extra_pages.dart';
import 'package:omni_plan/features/profile/settings_pages.dart';
import 'package:omni_plan/services/reminder_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Omni Docs Profile page with Omni Plan's rows: same account card, Omni
/// Pro card, section headings, tile rows and account buttons. Account
/// identity comes from Supabase; plans stay on this device, per account.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: PlanService.instance,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    if (!SupabaseConfig.initialized) {
      return const _ProfileContent(user: null);
    }
    return StreamBuilder<AuthState>(
      stream: AuthService().authStateChanges,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        Supabase.instance.client.auth.currentSession,
      ),
      builder: (context, _) =>
          _ProfileContent(user: Supabase.instance.client.auth.currentUser),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  final User? user;
  const _ProfileContent({required this.user});

  String _displayName(User account) {
    final metadata = account.userMetadata?['display_name'];
    if (metadata is String && metadata.trim().isNotEmpty) {
      return metadata.trim();
    }
    final local = (account.email ?? '').split('@').first.trim();
    return local.isEmpty ? 'Omni Plan member' : local;
  }

  Future<String?> _avatarUrl(User account) async {
    final raw = account.userMetadata?['avatar_path'];
    if (raw is! String || raw.isEmpty || !raw.startsWith('${account.id}/')) {
      return null;
    }
    if (raw.contains('..') || raw.contains('\\')) {
      return null;
    }
    try {
      return await Supabase.instance.client.storage
          .from('avatars')
          .createSignedUrl(raw, 600);
    } catch (_) {
      return null;
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      // Reminders belong to the account that set them.
      await ReminderService.instance.cancelAll();
      await AuthService().signOut();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final account = user;
    if (account == null) return;
    final store = context.read<PlanStore>();
    final password = TextEditingController();
    final confirmed = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your Omni identity, and the plans this account keeps on this device. Back up first if you want to keep them.',
            ),
            if (!account.isAnonymous) ...[
              const SizedBox(height: 16),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password to confirm',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, password.text),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    password.dispose();
    if (confirmed == null || !context.mounted) return;
    final scope = store.scope;
    try {
      await AuthService().deleteAccount(
        password: account.isAnonymous ? null : confirmed,
      );
      // The identity is gone; its plans on this device go with it.
      await ReminderService.instance.cancelAll();
      await store.close();
      if (scope != null) await PlanStore.deleteScope(scope);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final bottom = MediaQuery.paddingOf(context).bottom;
    final account = user;
    final name = account == null ? 'Not signed in' : _displayName(account);
    final email = account?.email ?? 'Guest mode';
    final theme = Theme.of(context);
    final isPro = PlanService.instance.isPro;
    final projects = store.projects.length;
    final archived = store.archivedProjects.length + store.archivedTasks.length;

    return ListView(
      padding: EdgeInsets.only(bottom: 96 + bottom),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OmniDesignTokens.pageInset,
            16,
            OmniDesignTokens.pageInset,
            16,
          ),
          child: OmniSurfaceCard(
            padding: const EdgeInsets.all(16),
            onTap: () => showAccountSheet(context, account),
            semanticLabel: 'Omni Account, switch account',
            child: Row(
              children: [
                _ProfileAvatar(user: account, name: name, loadUrl: _avatarUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      OmniStatusPill(
                        label: account == null || account.isAnonymous
                            ? 'Guest · Free plan'
                            : (isPro ? 'Pro plan' : 'Free plan'),
                        color: isPro
                            ? OmniDesignTokens.accentAmber
                            : theme.colorScheme.onSurfaceVariant,
                        backgroundColor: isPro
                            ? OmniDesignTokens.accentAmberSurface
                            : theme.colorScheme.surfaceContainerHighest,
                        icon: Icons.workspace_premium_outlined,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.unfold_more_rounded),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OmniDesignTokens.pageInset,
            0,
            OmniDesignTokens.pageInset,
            20,
          ),
          child: OmniSurfaceCard(
            padding: const EdgeInsets.all(16),
            onTap: () => _push(context, const ProPage()),
            semanticLabel: 'Omni Pro, manage your plan',
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: OmniDesignTokens.accentAmberSurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: OmniDesignTokens.accentAmber,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Omni Pro',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPro
                            ? 'Pro plan · Manage your subscription'
                            : 'Free plan · Explore premium features',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
        OmniListSection(
          title: 'Activity',
          children: [
            OmniMenuRow(
              icon: Icons.history_rounded,
              title: 'History',
              subtitle: '${store.activity.length} recent changes',
              useTile: true,
              showDivider: true,
              onTap: () => _push(context, const HistoryPage()),
            ),
            OmniMenuRow(
              icon: Icons.favorite_rounded,
              title: 'Favorites',
              subtitle:
                  '${store.favoriteTemplates.length} saved templates · ${store.projects.where((p) => p.favorite).length} projects',
              useTile: true,
              showDivider: true,
              onTap: () => _push(context, const FavoritesPage()),
            ),
            OmniMenuRow(
              icon: Icons.folder_rounded,
              title: 'My plans',
              subtitle: '$projects ${projects == 1 ? 'project' : 'projects'} on this device',
              useTile: true,
              showDivider: true,
              onTap: () => context.read<ShellController>().goTo(ShellController.projects),
            ),
            OmniMenuRow(
              icon: Icons.archive_rounded,
              title: 'Archive',
              subtitle: archived == 0 ? 'Archived projects and tasks' : '$archived archived items',
              useTile: true,
              showDivider: true,
              onTap: () => _push(context, const ArchivePage()),
            ),
            OmniMenuRow(
              icon: Icons.settings_backup_restore_rounded,
              title: 'Backup and restore',
              subtitle: 'Save your plans to a file and restore them',
              useTile: true,
              onTap: () => _push(context, const BackupPage()),
            ),
          ],
        ),
        const SizedBox(height: OmniDesignTokens.sectionGap),
        OmniListSection(
          title: 'Account',
          children: [
            OmniMenuRow(
              icon: Icons.settings_rounded,
              title: 'Settings',
              subtitle: 'Appearance and planning preferences',
              useTile: true,
              showDivider: true,
              onTap: () => _push(context, const SettingsPage()),
            ),
            OmniMenuRow(
              icon: Icons.notifications_rounded,
              title: 'Notifications',
              subtitle: 'Reminders and deadline alerts',
              useTile: true,
              showDivider: true,
              onTap: () => _push(context, const NotificationSettingsPage()),
            ),
            OmniMenuRow(
              icon: Icons.shield_rounded,
              title: 'Data and privacy',
              subtitle: 'Storage, export and deletion',
              useTile: true,
              onTap: () => _push(context, const DataPrivacyPage()),
            ),
          ],
        ),
        const SizedBox(height: OmniDesignTokens.sectionGap),
        OmniListSection(
          title: 'Planning configuration',
          children: [
            OmniMenuRow(
              icon: Icons.tune_rounded,
              useTile: true,
              title: 'Planning defaults',
              subtitle: 'Priority, views, week start and reminders',
              onTap: () => _push(context, const PlanningDefaultsPage()),
            ),
          ],
        ),
        OmniListSection(
          title: 'Support',
          children: [
            OmniMenuRow(
              icon: Icons.help_rounded,
              title: 'Help & Support',
              subtitle: 'FAQs, contact, rating and feedback',
              useTile: true,
              showDivider: true,
              onTap: () => _push(context, const HelpSupportPage()),
            ),
            OmniMenuRow(
              icon: Icons.info_rounded,
              title: 'About',
              subtitle: 'App information and policies',
              useTile: true,
              onTap: () => _push(context, const AboutPage()),
            ),
          ],
        ),
        const SizedBox(height: OmniDesignTokens.sectionGap),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OmniDesignTokens.pageInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (account != null)
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _signOut(context),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Log out'),
                  ),
                ),
              if (account != null) const SizedBox(height: 12),
              if (account != null)
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: () => _deleteAccount(context),
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: const Text('Delete account'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: OmniDesignTokens.sectionGap),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final User? user;
  final String name;
  final Future<String?> Function(User) loadUrl;

  const _ProfileAvatar({
    required this.user,
    required this.name,
    required this.loadUrl,
  });

  @override
  Widget build(BuildContext context) {
    final account = user;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    if (account == null) return CircleAvatar(radius: 28, child: Text(initial));
    return FutureBuilder<String?>(
      future: loadUrl(account),
      builder: (context, snapshot) => CircleAvatar(
        radius: 28,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.primary,
        backgroundImage: snapshot.data == null
            ? null
            : NetworkImage(snapshot.data!),
        child: snapshot.data == null
            ? Text(initial, style: const TextStyle(fontWeight: FontWeight.w700))
            : null,
      ),
    );
  }
}

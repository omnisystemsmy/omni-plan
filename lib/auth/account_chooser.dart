import 'package:flutter/material.dart';
import 'package:omni_plan/auth/remembered_accounts.dart';
import 'package:omni_plan/core/branding/plan_brand.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';

class AccountChooser extends StatelessWidget {
  final List<RememberedAccount> accounts;
  final ValueChanged<RememberedAccount> onSelect;
  final VoidCallback onUseAnother;
  final ValueChanged<RememberedAccount> onForget;

  /// Ids of accounts that can sign in with one tap.
  final Set<String> saved;

  /// The account being signed in right now.
  final String? busyId;
  final String? error;

  const AccountChooser({
    super.key,
    required this.accounts,
    required this.onSelect,
    required this.onUseAnother,
    required this.onForget,
    this.saved = const {},
    this.busyId,
    this.error,
  });

  String _initial(RememberedAccount account) {
    final text = account.name.trim().isNotEmpty ? account.name : account.email;
    return text.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            OmniDesignTokens.pageInset + 4,
            36,
            OmniDesignTokens.pageInset + 4,
            28,
          ),
          children: [
            const Center(child: PlanLogo(height: 38)),
            const SizedBox(height: 44),
            Text(
              'Choose an account',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap your account to continue to Omni Plan.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            if (error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(
                    OmniDesignTokens.radiusCard,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: theme.colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            for (final account in accounts) ...[
              _AccountTile(
                account: account,
                initial: _initial(account),
                note: saved.contains(account.id) ? null : 'Password needed',
                busy: busyId == account.id,
                enabled: busyId == null,
                onTap: () => onSelect(account),
                onForget: () => onForget(account),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busyId == null ? onUseAnother : null,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Use another account'),
            ),
            const SizedBox(height: 18),
            Text(
              'Your password is never stored. A saved sign-in is kept in this '
              "device's secure storage until you remove the account here.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final RememberedAccount account;
  final String initial;
  final VoidCallback onTap;
  final VoidCallback onForget;
  final String? note;
  final bool busy;
  final bool enabled;

  const _AccountTile({
    required this.account,
    required this.initial,
    required this.onTap,
    required this.onForget,
    required this.busy,
    required this.enabled,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OmniDesignTokens.radiusCard),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(OmniDesignTokens.radiusCard),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.primary,
                child: Text(
                  initial,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name.isEmpty ? account.email : account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (account.name.isNotEmpty)
                      Text(
                        account.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (note != null)
                      Text(note!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              else
                PopupMenuButton<String>(
                  tooltip: 'Account options',
                  enabled: enabled,
                  onSelected: (_) => onForget(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'forget',
                      child: Text('Remove from this device'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:omni_plan/auth/auth_gate.dart';
import 'package:omni_plan/auth/auth_service.dart';
import 'package:omni_plan/auth/remembered_accounts.dart';
import 'package:omni_plan/auth/session_vault.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Omni Account switcher: the account in use, the other accounts signed in
/// on this device (one tap, using the saved sign-in kept in the secure
/// storage), and the account actions.
Future<void> showAccountSheet(BuildContext context, User? current) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AccountSheet(current: current),
  );
}

class _AccountSheet extends StatefulWidget {
  final User? current;
  const _AccountSheet({required this.current});

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  List<RememberedAccount>? _others;
  Set<String> _saved = const {};
  String? _busyId;
  String? _error;

  User? get _me => widget.current;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await RememberedAccounts.read();
    final others = [
      for (final a in all)
        if (a.id != _me?.id) a,
    ];
    final saved = <String>{
      for (final a in others)
        if (await SessionVault.instance.has(a.id)) a.id,
    };
    if (!mounted) return;
    setState(() {
      _others = others;
      _saved = saved;
    });
  }

  Future<void> _switchTo(RememberedAccount account) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = account.id;
      _error = null;
    });
    try {
      await AuthService().signInRemembered(account);
      if (mounted) Navigator.pop(context);
    } on SavedSignInUnavailable catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      _load();
      final go = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Sign in again'),
          content: Text(
            '${e.message}\n\nLog out of the current account to sign in to ${account.email}? Plans of each account stay on this device and open again when you sign back in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (go == true) {
        AuthGate.emailForNextSignIn = account.email;
        AuthGate.openSignInOnNextSignOut = true;
        try {
          await AuthService().signOut();
          if (mounted) Navigator.pop(context);
        } catch (err) {
          AuthGate.openSignInOnNextSignOut = false;
          if (mounted) {
            setState(() => _error = '$err'.replaceFirst('Exception: ', ''));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _guest() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Use without an account?'),
        content: const Text(
          'You continue as a guest. The account you are in stays saved on this device with its plans; a guest starts with separate, empty plans. Pro features of the account are not available to a guest.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Use as guest'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busyId = 'guest';
      _error = null;
    });
    try {
      await AuthService().signInAsGuest();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _addAccount() async {
    AuthGate.openSignInOnNextSignOut = true;
    AuthGate.emailForNextSignIn = null;
    try {
      // The current account stays saved; the sign-in form opens next.
      await AuthService().signOut();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      AuthGate.openSignInOnNextSignOut = false;
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    }
  }

  void _manage() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => const OmniAccountPage()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = _me;
    final others = _others;
    final guest = me == null || me.isAnonymous;
    final busy = _busyId != null;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          children: [
            const _Heading('Current account'),
            _AccountRow(
              title: guest ? 'Guest' : _name(me),
              subtitle: guest
                  ? 'Using Omni Plan without an account'
                  : (me.email ?? ''),
              initial: guest ? '?' : _name(me),
              trailing: Icon(
                Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const _Heading('Other accounts'),
            if (others == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else if (others.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'No other accounts have been signed in on this device yet.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final a in others)
                _AccountRow(
                  title: a.name.isEmpty ? a.email : a.name,
                  subtitle: a.name.isEmpty ? '' : a.email,
                  note: _saved.contains(a.id) ? null : 'Password needed',
                  initial: a.name.isEmpty ? a.email : a.name,
                  busy: _busyId == a.id,
                  onTap: busy ? null : () => _switchTo(a),
                ),
            const Divider(height: 24),
            OmniMenuRow(
              icon: Icons.person_outline_rounded,
              title: 'Use without an account',
              subtitle: guest
                  ? 'You are already a guest'
                  : 'Continue as a guest on this device',
              enabled: !busy && !guest,
              onTap: busy || guest ? null : _guest,
            ),
            OmniMenuRow(
              icon: Icons.person_add_alt_1_rounded,
              title: 'Add another account',
              subtitle: 'Sign in or create an account',
              onTap: busy ? null : _addAccount,
            ),
            OmniMenuRow(
              icon: Icons.manage_accounts_outlined,
              title: 'Manage your Omni Account',
              subtitle: guest
                  ? 'Sign in to manage an account'
                  : 'Name, email and password',
              enabled: !guest,
              onTap: guest ? null : _manage,
            ),
          ],
        ),
      ),
    );
  }
}

String _name(User? u) {
  final meta = u?.userMetadata?['display_name'];
  if (meta is String && meta.trim().isNotEmpty) return meta.trim();
  final local = (u?.email ?? '').split('@').first.trim();
  return local.isEmpty ? 'Omni Plan member' : local;
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(letterSpacing: .8, fontWeight: FontWeight.w700),
    ),
  );
}

class _AccountRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? note;
  final String initial;
  final bool busy;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _AccountRow({
    required this.title,
    required this.subtitle,
    required this.initial,
    this.note,
    this.busy = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.primary,
              child: Text(
                initial.trim().isEmpty
                    ? '?'
                    : initial.trim().characters.first.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  if (note != null)
                    Text(note!, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              ?trailing,
          ],
        ),
      ),
    );
  }
}

/// What the app can really manage about an Omni Account: its identity details,
/// the display name, and a password-reset email. (There is no web account
/// portal configured in the app.)
class OmniAccountPage extends StatefulWidget {
  const OmniAccountPage({super.key});

  @override
  State<OmniAccountPage> createState() => _OmniAccountPageState();
}

class _OmniAccountPageState extends State<OmniAccountPage> {
  late final TextEditingController _name;
  bool _saving = false;

  User? get _user => Supabase.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _user == null ? '' : _name0(_user!));
  }

  String _name0(User u) {
    final meta = u.userMetadata?['display_name'];
    return meta is String ? meta : '';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _saveName() async {
    final value = _name.text.trim();
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'display_name': value}),
      );
      if (mounted) _say('Name saved.');
    } on AuthException catch (e) {
      if (mounted) _say(e.message);
    } catch (_) {
      if (mounted) _say('Could not save. Check your connection.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset(String email) async {
    try {
      await AuthService().sendPasswordReset(email);
      if (mounted) _say('A password reset message was sent to $email.');
    } catch (e) {
      if (mounted) _say('$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final email = u?.email ?? '';
    return Scaffold(
      appBar: omniListAppBar(context, 'Omni Account'),
      body: u == null
          ? const Center(child: Text('Not signed in.'))
          : ListView(
              padding: const EdgeInsets.all(OmniDesignTokens.pageInset),
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: TextEditingController(text: email),
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _saving ? null : _saveName,
                  child: Text(_saving ? 'Saving...' : 'Save name'),
                ),
                const SizedBox(height: 28),
                OmniListSection(
                  title: 'Security',
                  children: [
                    OmniMenuRow(
                      icon: Icons.lock_reset_rounded,
                      useTile: true,
                      title: 'Reset password',
                      subtitle: u.isAnonymous || email.isEmpty
                          ? 'Not available for a guest'
                          : 'Send a reset message to $email',
                      enabled: email.isNotEmpty && !u.isAnonymous,
                      onTap: email.isEmpty || u.isAnonymous
                          ? null
                          : () => _reset(email),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

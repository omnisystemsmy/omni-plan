import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_plan/app/workspace.dart';
import 'package:omni_plan/auth/account_chooser.dart';
import 'package:omni_plan/auth/auth_page.dart';
import 'package:omni_plan/auth/auth_service.dart';
import 'package:omni_plan/auth/remembered_accounts.dart';
import 'package:omni_plan/auth/session_vault.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Restores the Supabase session before showing the planning workspace. When
/// nobody is signed in and accounts were used on this device, they are offered
/// first: one tap signs in again without typing the email or password.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  /// Set before signing out when the sign-in form should open straight away
  /// (adding another account) instead of the account chooser.
  static bool openSignInOnNextSignOut = false;

  /// The email to put in that form, when known.
  static String? emailForNextSignIn;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  List<RememberedAccount>? _accounts;
  Set<String> _saved = const {};
  bool _showAuth = false;
  String? _email;
  String? _notice;
  String? _busyId;
  StreamSubscription<AuthState>? _events;

  @override
  void initState() {
    super.initState();
    AuthService().startSessionKeeper();
    _load();
    // Back at the chooser after signing out.
    _events = AuthService().authStateChanges.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        final direct = AuthGate.openSignInOnNextSignOut;
        setState(() {
          _showAuth = direct;
          _email = direct ? AuthGate.emailForNextSignIn : null;
          _notice = null;
        });
        AuthGate.openSignInOnNextSignOut = false;
        AuthGate.emailForNextSignIn = null;
        _load();
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final accounts = await RememberedAccounts.read();
    final saved = <String>{
      for (final a in accounts)
        if (await SessionVault.instance.has(a.id)) a.id,
    };
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _saved = saved;
    });
  }

  void _openAuth([String? email]) {
    setState(() {
      _email = email;
      _showAuth = true;
    });
  }

  Future<void> _choose(RememberedAccount account) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = account.id;
      _notice = null;
    });
    try {
      await AuthService().signInRemembered(account);
      // The stream below now holds a session and shows the workspace.
    } on SavedSignInUnavailable catch (e) {
      if (!mounted) return;
      // Fall back to the password form with the email already filled in.
      setState(() {
        _notice = e.message;
        _email = account.email;
        _showAuth = true;
      });
      _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService().authStateChanges,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        Supabase.instance.client.auth.currentSession,
      ),
      builder: (context, snapshot) {
        if (snapshot.data?.session != null) {
          return PlanWorkspace(scope: snapshot.data!.session!.user.id);
        }
        final accounts = _accounts;
        if (accounts == null) {
          return const Scaffold(body: SizedBox.shrink());
        }
        if (_showAuth || accounts.isEmpty) {
          return AuthPage(
            key: ValueKey('auth-$_email'),
            initialEmail: _email,
            notice: _notice,
            onBack: accounts.isEmpty
                ? null
                : () => setState(() {
                    _showAuth = false;
                    _notice = null;
                  }),
          );
        }
        return AccountChooser(
          accounts: accounts,
          saved: _saved,
          busyId: _busyId,
          error: _notice,
          onSelect: _choose,
          onUseAnother: () => _openAuth(),
          onForget: (account) async {
            await AuthService().forgetAccount(account.id);
            await _load();
          },
        );
      },
    );
  }
}

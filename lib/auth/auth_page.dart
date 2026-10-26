import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_plan/auth/auth_service.dart';
import 'package:omni_plan/core/branding/plan_brand.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_form_kit.dart';

enum _AuthMode { signIn, create }

/// One screen to sign in, create an account, reset a password, or carry on as
/// a guest. Same layout, tabs and fields as Omni Tools.
class AuthPage extends StatefulWidget {
  final String? initialEmail;

  /// Shown above the form when the page opens (e.g. a saved sign-in expired).
  final String? notice;

  /// Back to the account chooser, when there is one.
  final VoidCallback? onBack;

  const AuthPage({super.key, this.initialEmail, this.notice, this.onBack});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _auth = AuthService();
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _showPassword = false;
  bool _busy = false;
  bool _guestBusy = false;
  String? _error;

  bool get _create => _mode == _AuthMode.create;

  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail ?? '');
    _error = widget.notice;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate() {
    final email = _email.text.trim();
    if (email.isEmpty) return 'Enter your email.';
    if (!_emailRe.hasMatch(email)) return 'That email does not look right.';
    if (_password.text.isEmpty) return 'Enter your password.';
    if (_create) {
      if (_password.text.length < 6) {
        return 'Use at least 6 characters for your password.';
      }
      if (_confirm.text != _password.text) return 'The passwords do not match.';
    }
    return null;
  }

  void _setError(Object error) {
    if (!mounted) return;
    setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
  }

  Future<void> _submit() async {
    if (_busy || _guestBusy) return;
    FocusScope.of(context).unfocus();
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_create) {
        await _auth.registerWithEmailAndPassword(
          email: _email.text,
          password: _password.text,
        );
      } else {
        await _auth.signInWithEmailAndPassword(
          email: _email.text,
          password: _password.text,
        );
      }
    } catch (e) {
      _setError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    if (_busy || _guestBusy) return;
    setState(() {
      _guestBusy = true;
      _error = null;
    });
    try {
      await _auth.signInAsGuest();
    } catch (e) {
      _setError(e);
    } finally {
      if (mounted) setState(() => _guestBusy = false);
    }
  }

  Future<void> _forgot() async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      builder: (_) => _ResetSheet(initialEmail: _email.text.trim()),
    );
  }

  // --- password strength ---

  ({double value, String label, Color color}) _strength() {
    final p = _password.text;
    var score = 0;
    if (p.length >= 6) score++;
    if (p.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'\d').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p)) {
      score++;
    }
    if (p.isEmpty) return (value: 0, label: '', color: Colors.transparent);
    switch (score) {
      case 0:
      case 1:
        return (value: 0.25, label: 'Weak', color: const Color(0xFFE5547A));
      case 2:
        return (
          value: 0.55,
          label: 'Okay',
          color: OmniDesignTokens.accentAmber,
        );
      case 3:
        return (value: 0.8, label: 'Good', color: OmniDesignTokens.primary);
      default:
        return (value: 1, label: 'Strong', color: const Color(0xFF1B9E5A));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strength = _strength();
    final busy = _busy || _guestBusy;

    final form = <Widget>[
      OmniField(
        label: 'Email',
        hint: 'you@example.com',
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.next,
      ),
      OmniField(
        label: 'Password',
        hint: _create ? 'At least 6 characters' : 'Your password',
        controller: _password,
        keyboardType: TextInputType.visiblePassword,
        obscureText: !_showPassword,
        autofillHints: [
          _create ? AutofillHints.newPassword : AutofillHints.password,
        ],
        textInputAction: _create ? TextInputAction.next : TextInputAction.done,
        onSubmitted: _create ? null : (_) => _submit(),
        suffix: IconButton(
          tooltip: _showPassword ? 'Hide password' : 'Show password',
          icon: Icon(
            _showPassword
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
          ),
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
        onChanged: (_) => setState(() {}),
      ),
      if (_create && _password.text.isNotEmpty)
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: strength.value,
                  minHeight: 5,
                  color: strength.color,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              strength.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: strength.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      if (_create)
        OmniField(
          label: 'Confirm password',
          hint: 'Type it again',
          controller: _confirm,
          keyboardType: TextInputType.visiblePassword,
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            OmniDesignTokens.pageInset + 4,
            16,
            OmniDesignTokens.pageInset + 4,
            28,
          ),
          children: [
            if (widget.onBack != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: busy ? null : widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  label: const Text('Saved accounts'),
                ),
              )
            else
              const SizedBox(height: 12),
            const Center(child: PlanLogo(height: 34)),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topLeft,
                children: [...previous, ?current],
              ),
              child: Column(
                key: ValueKey(_mode),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _create ? 'Create your account' : 'Welcome back',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _create
                        ? 'It only takes a few seconds.'
                        : 'Sign in to pick up where you left off.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            OmniSegmented<_AuthMode>(
              options: const [
                OmniOption(_AuthMode.signIn, 'Sign in'),
                OmniOption(_AuthMode.create, 'Create account'),
              ],
              value: _mode,
              onChanged: (m) => setState(() {
                _mode = m;
                _error = null;
              }),
            ),
            const SizedBox(height: 18),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < form.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    form[i],
                  ],
                ],
              ),
            ),
            if (!_create)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : _forgot,
                  child: const Text('Forgot password?'),
                ),
              )
            else
              const SizedBox(height: 14),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(
                    OmniDesignTokens.radiusCard,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: cs.error,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(_create ? 'Create account' : 'Sign in'),
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: TextButton(
                onPressed: busy ? null : _guest,
                child: _guestBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Continue without an account'),
              ),
            ),
            Center(
              child: Text(
                'You can create an account any time from your profile.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for an email, sends a one-time code, then sets a new password.
class _ResetSheet extends StatefulWidget {
  final String initialEmail;

  const _ResetSheet({required this.initialEmail});

  @override
  State<_ResetSheet> createState() => _ResetSheetState();
}

class _ResetSheetState extends State<_ResetSheet> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );
  final TextEditingController _code = TextEditingController();
  final TextEditingController _newPass = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _newPass.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!_AuthPageState._emailRe.hasMatch(email)) {
      setState(() => _error = 'Enter the email you signed up with.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService().sendPasswordReset(email);
      HapticFeedback.lightImpact();
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length < 6 || code.length > 10) {
      setState(() => _error = 'Enter the code from the email.');
      return;
    }
    if (_newPass.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService().resetPasswordWithCode(
        email: _email.text,
        code: code,
        newPassword: _newPass.text,
      );
      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _spinner() => const SizedBox(
    width: 22,
    height: 22,
    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        OmniDesignTokens.pageInset + 4,
        0,
        OmniDesignTokens.pageInset + 4,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_sent) ...[
            Icon(
              Icons.mark_email_read_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              'Check your email',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'If ${_email.text.trim()} has an account, a code is on its way. '
              'It may take a minute, and check spam too. Enter it below with '
              'your new password.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 16),
            OmniField(
              label: 'Code',
              hint: 'Code from the email',
              controller: _code,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            OmniField(
              label: 'New password',
              hint: 'At least 6 characters',
              controller: _newPass,
              obscureText: _hide,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirm(),
              suffix: IconButton(
                icon: Icon(
                  _hide
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ] else ...[
            Text(
              'Reset your password',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter your email and we will send you a code to choose a new password.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OmniField(
              label: 'Email',
              hint: 'you@example.com',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _send(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : (_sent ? _confirm : _send),
              child: _busy
                  ? _spinner()
                  : Text(_sent ? 'Set new password' : 'Send code'),
            ),
          ),
        ],
      ),
    );
  }
}

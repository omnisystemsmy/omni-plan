import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:omni_plan/auth/remembered_accounts.dart';
import 'package:omni_plan/auth/session_vault.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Central Omni identity client. Omni Plan uses the same Supabase project as
/// Omni Account and Omni Tools, with auth.users.id as the canonical identity.
/// A saved sign-in could not be used; [message] says why, in words for the user.
class SavedSignInUnavailable implements Exception {
  final String message;

  const SavedSignInUnavailable(this.message);

  @override
  String toString() => message;
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  GoTrueClient get _auth => Supabase.instance.client.auth;

  User? get currentUser => _auth.currentUser;
  bool get isGuest => currentUser?.isAnonymous ?? false;
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  Future<User?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = result.user;
      if (user == null) throw Exception('Login failed. Please try again.');
      await _remember(user);
      return user;
    } on AuthException catch (error) {
      throw Exception(_message(error.code, error.message));
    } catch (error) {
      throw Exception(_networkMessage(error));
    }
  }

  Future<User?> registerWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.signUp(
        email: email.trim(),
        password: password,
      );
      final user = result.user;
      if (user == null) throw Exception('Could not create the account.');
      if ((user.identities ?? const []).isEmpty) {
        throw Exception('Email already registered. Please sign in instead.');
      }
      if (result.session == null) {
        throw Exception(
          'Almost done. Check ${email.trim()} for the confirmation link, then sign in.',
        );
      }
      await _remember(user);
      return user;
    } on AuthException catch (error) {
      throw Exception(_message(error.code, error.message));
    } catch (error) {
      throw Exception(_networkMessage(error));
    }
  }

  Future<void> signInAsGuest() async {
    try {
      await _auth.signInAnonymously();
    } on AuthException catch (error) {
      if (error.code == 'anonymous_provider_disabled') {
        throw Exception('Guest mode is not available yet. Please sign in.');
      }
      throw Exception(_message(error.code, error.message));
    } catch (_) {
      throw Exception('Could not start guest mode. Check your connection.');
    }
  }

  StreamSubscription<AuthState>? _keeper;

  /// Keeps the saved sign-in of the account in use up to date. Supabase
  /// replaces the refresh token each time it renews the session, so the saved
  /// one must follow, or choosing the account later would fail.
  void startSessionKeeper() {
    _keeper ??= _auth.onAuthStateChange.listen((state) {
      final session = state.session;
      final user = session?.user;
      if (session == null || user == null || user.isAnonymous) return;
      final token = session.refreshToken;
      if (token != null) SessionVault.instance.save(user.id, token);
    });
    final session = _auth.currentSession;
    final user = session?.user;
    final token = session?.refreshToken;
    if (user != null && !user.isAnonymous && token != null) {
      SessionVault.instance.save(user.id, token);
    }
  }

  /// Signs out on this device only. The account stays in the chooser, with its
  /// saved sign-in, until it is removed there.
  Future<void> signOut() async {
    try {
      await _auth.signOut(scope: SignOutScope.local);
    } on AuthException catch (error) {
      throw Exception(_message(error.code, error.message));
    }
  }

  /// Signs in a remembered account from its saved sign-in. Throws a message
  /// to show when that is not possible (expired, offline), after which the
  /// person can sign in with the password.
  Future<void> signInRemembered(RememberedAccount account) async {
    final token = await SessionVault.instance.read(account.id);
    if (token == null) {
      throw const SavedSignInUnavailable(
        'Enter your password to sign in on this device.',
      );
    }
    try {
      final result = await _auth.setSession(token);
      final user = result.user;
      if (user == null || user.id != account.id) {
        await SessionVault.instance.forget(account.id);
        throw const SavedSignInUnavailable(
          'That sign-in has expired. Enter your password.',
        );
      }
      await _remember(user);
    } on SavedSignInUnavailable {
      rethrow;
    } on AuthException catch (error) {
      // The server no longer accepts the saved sign-in (password changed,
      // signed out everywhere): drop it so it is not tried again.
      await SessionVault.instance.forget(account.id);
      throw SavedSignInUnavailable(
        error.code == 'over_request_rate_limit'
            ? 'Too many attempts. Please try again later.'
            : 'That sign-in has expired. Enter your password.',
      );
    } catch (error) {
      throw SavedSignInUnavailable(_networkMessage(error));
    }
  }

  /// Removes an account from the chooser and deletes its saved sign-in.
  Future<void> forgetAccount(String id) async {
    await RememberedAccounts.forget(id);
    await SessionVault.instance.forget(id);
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (error) {
      if (error.code == 'user_not_found') return;
      throw Exception(_message(error.code, error.message));
    } catch (_) {
      throw Exception('Could not send the reset email. Check your connection.');
    }
  }

  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      await _auth.verifyOTP(
        email: email.trim(),
        token: code.trim(),
        type: OtpType.recovery,
      );
      await _auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      throw Exception(_message(error.code, error.message));
    }
  }

  bool get isEmailUser {
    final user = currentUser;
    return user != null &&
        !user.isAnonymous &&
        (user.identities?.any((item) => item.provider == 'email') ?? true);
  }

  /// Server-side deletion. The service-role key never ships in the app.
  Future<void> deleteAccount({String? password}) async {
    final user = currentUser;
    if (user == null) throw Exception('No user is signed in.');
    try {
      if (!user.isAnonymous) {
        if (!isEmailUser) {
          throw Exception('Manage this account from Omni Account.');
        }
        final email = user.email;
        if (email == null || password == null || password.isEmpty) {
          throw Exception('Enter your password to confirm.');
        }
        try {
          await _auth.signInWithPassword(email: email, password: password);
        } on AuthException {
          throw Exception('That password is not correct.');
        }
      }
      final response = await Supabase.instance.client.functions.invoke(
        'delete-account',
        method: HttpMethod.post,
      );
      if (response.status != 200) {
        throw Exception('Could not delete the account. Please try again.');
      }
      await forgetAccount(user.id);
      await _auth.signOut(scope: SignOutScope.local);
    } on FunctionException catch (error) {
      if (error.status == 401) throw Exception('Please sign in again.');
      throw Exception('Could not delete the account. Please try again later.');
    } on AuthException catch (error) {
      throw Exception(_message(error.code, error.message));
    }
  }

  Future<void> _remember(User user) async {
    final email = user.email;
    if (email == null || email.isEmpty || user.isAnonymous) return;
    await RememberedAccounts.remember(
      id: user.id,
      email: email,
      name: (user.userMetadata?['display_name'] as String?) ?? '',
    );
  }

  String _message(String? code, [String? raw]) {
    switch (code) {
      case 'invalid_credentials':
      case 'user_not_found':
        return 'Incorrect email or password.';
      case 'email_not_confirmed':
        return 'Confirm your email first. Check your inbox for the link.';
      case 'email_exists':
      case 'user_already_exists':
        return 'Email already registered. Please sign in instead.';
      case 'weak_password':
        return 'Choose a stronger password (at least 6 characters).';
      case 'email_address_invalid':
        return 'Enter a valid email address.';
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return 'Too many attempts. Please try again later.';
      case 'otp_expired':
        return 'That code expired or is incorrect. Request a new one.';
    }
    final text = (raw ?? '').toLowerCase();
    if (text.contains('network') || text.contains('socket')) {
      return 'No internet connection. Check it and try again.';
    }
    if (kDebugMode) debugPrint('Auth error: $code $raw');
    return 'Authentication error. Please try again.';
  }

  String _networkMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('connection') ||
        text.contains('failed host lookup') ||
        text.contains('timed out')) {
      return 'No internet connection. Check it and try again.';
    }
    if (kDebugMode) debugPrint('Auth network error: $error');
    return 'Authentication error. Please try again.';
  }
}

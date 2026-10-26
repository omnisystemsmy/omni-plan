import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the vault keeps its one JSON entry. Swappable so tests need no
/// device keystore.
abstract class VaultBackend {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// The device keystore (Android Keystore / iOS Keychain).
class SecureVaultBackend implements VaultBackend {
  static const _key = 'omni_plan_saved_sessions_v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Keeps one refresh token per remembered account in the device keystore, so
/// choosing the account can sign it in again without typing the password.
///
/// Passwords are never stored. A token is only ever kept for an account the
/// person signed in to on this device, it is replaced whenever Supabase issues
/// a new one, and it is deleted when the account is removed from the chooser.
class SessionVault {
  final VaultBackend _backend;

  SessionVault([VaultBackend? backend])
    : _backend = backend ?? SecureVaultBackend();

  static SessionVault instance = SessionVault();

  Future<Map<String, String>> _all() async {
    try {
      final raw = await _backend.read();
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is String && (e.value as String).isNotEmpty)
            '${e.key}': e.value as String,
      };
    } catch (_) {
      // An unreadable store counts as empty: the person just types the
      // password once, and the vault fills up again.
      return {};
    }
  }

  Future<void> _put(Map<String, String> all) async {
    try {
      if (all.isEmpty) {
        await _backend.delete();
      } else {
        await _backend.write(jsonEncode(all));
      }
    } catch (_) {
      // Saving is a convenience; failing to save never blocks signing in.
    }
  }

  Future<String?> read(String userId) async => (await _all())[userId];

  Future<bool> has(String userId) async => await read(userId) != null;

  Future<void> save(String userId, String refreshToken) async {
    if (userId.isEmpty || refreshToken.isEmpty) return;
    final all = await _all();
    if (all[userId] == refreshToken) return;
    all[userId] = refreshToken;
    await _put(all);
  }

  Future<void> forget(String userId) async {
    final all = await _all();
    if (all.remove(userId) != null) await _put(all);
  }
}

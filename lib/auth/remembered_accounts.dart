import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Safe account chooser entries. This intentionally stores no password,
/// refresh token, access token, or session object.
class RememberedAccount {
  final String id;
  final String email;
  final String name;
  final int lastUsedAt;

  const RememberedAccount({
    required this.id,
    required this.email,
    required this.name,
    required this.lastUsedAt,
  });

  factory RememberedAccount.fromJson(Map<String, dynamic> json) {
    return RememberedAccount(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      lastUsedAt: json['lastUsedAt'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'lastUsedAt': lastUsedAt,
  };
}

class RememberedAccounts {
  RememberedAccounts._();

  static const _key = 'omni_plan_remembered_accounts_v1';

  static Future<List<RememberedAccount>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                RememberedAccount.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((account) => account.id.isNotEmpty && account.email.isNotEmpty)
          .toList()
        ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    } catch (_) {
      return [];
    }
  }

  static Future<void> remember({
    required String id,
    required String email,
    String? name,
  }) async {
    final current = await read();
    final next = RememberedAccount(
      id: id,
      email: email,
      name: name?.trim() ?? '',
      lastUsedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final list = [next, ...current.where((item) => item.id != id)];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> forget(String id) async {
    final list = (await read()).where((item) => item.id != id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }
}

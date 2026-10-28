import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'xtream.dart';

/// Saved accounts. Stored in the OS keyring (libsecret / Keychain / Keystore).
/// If no keyring is available the app falls back to plain preferences so login still works.
class AccountStore {
  static const _key = 'accounts';
  // macOS: the legacy keychain works without a provisioning profile / keychain-access-groups entitlement.
  static const _secure = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));

  static List<Account> _parse(String raw) {
    try {
      return [for (final j in jsonDecode(raw) as List) Account.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  static Future<List<Account>> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = await _secure.read(key: _key);
      if (raw != null) return _parse(raw);
      // One-time migration of accounts saved by older versions in plain preferences.
      final legacy = prefs.getString(_key);
      if (legacy != null) {
        final accounts = _parse(legacy);
        await _secure.write(key: _key, value: legacy);
        await prefs.remove(_key);
        return accounts;
      }
      return [];
    } catch (_) {
      final legacy = prefs.getString(_key);
      return legacy == null ? [] : _parse(legacy);
    }
  }

  static Future<void> save(List<Account> accounts) async {
    final json = jsonEncode([for (final a in accounts) a.toJson()]);
    try {
      await _secure.write(key: _key, value: json);
      (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {
      await (await SharedPreferences.getInstance()).setString(_key, json);
    }
  }

  static const _lastKey = 'lastAccount';

  /// Key (host|username) of the account used last, if any.
  static Future<String?> loadLast() async => (await SharedPreferences.getInstance()).getString(_lastKey);

  static Future<void> saveLast(String key) async => (await SharedPreferences.getInstance()).setString(_lastKey, key);
}

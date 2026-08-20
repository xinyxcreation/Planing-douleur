import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';
  static const _emailKey = 'auth_email';
  static const _displayNameKey = 'auth_display_name';
  static const _expiresAtKey = 'auth_expires_at';
  static const _rememberKey = 'auth_remember';

  Future<void> saveSession({
    required String token,
    required String userId,
    required String email,
    String? displayName,
    required String expiresAt,
    required bool rememberMe,
  }) async {
    final sp = await SharedPreferences.getInstance();

    await sp.setString(_tokenKey, token);
    await sp.setString(_userIdKey, userId);
    await sp.setString(_emailKey, email);

    if (displayName != null) {
      await sp.setString(_displayNameKey, displayName);
    } else {
      await sp.remove(_displayNameKey);
    }

    await sp.setString(_expiresAtKey, expiresAt);
    await sp.setBool(_rememberKey, rememberMe);
  }

  Future<Map<String, dynamic>?> loadSession() async {
    final sp = await SharedPreferences.getInstance();

    final token = sp.getString(_tokenKey);
    final userId = sp.getString(_userIdKey);
    final email = sp.getString(_emailKey);
    final expiresAt = sp.getString(_expiresAtKey);

    if (token == null ||
        userId == null ||
        email == null ||
        expiresAt == null) {
      return null;
    }

    final expires = DateTime.tryParse(expiresAt);

    if (expires == null || !expires.isAfter(DateTime.now().toUtc())) {
      await clearSession();
      return null;
    }

    return {
      'token': token,
      'userId': userId,
      'email': email,
      'displayName': sp.getString(_displayNameKey),
      'expiresAt': expiresAt,
      'rememberMe': sp.getBool(_rememberKey) ?? false,
    };
  }

  Future<void> clearSession() async {
    final sp = await SharedPreferences.getInstance();

    await sp.remove(_tokenKey);
    await sp.remove(_userIdKey);
    await sp.remove(_emailKey);
    await sp.remove(_displayNameKey);
    await sp.remove(_expiresAtKey);
    await sp.remove(_rememberKey);
  }
}

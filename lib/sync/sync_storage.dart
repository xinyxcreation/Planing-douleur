import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SyncStorage {
  static const String _cursorPrefix = 'syncCursor_';
  static const String _pendingPrefix = 'pendingSyncChanges_';

  String _cursorKey(String userId) => '$_cursorPrefix$userId';
  String _pendingKey(String userId) => '$_pendingPrefix$userId';

  Future<int> getCursor(String userId) async {
    final preferences = await SharedPreferences.getInstance();

    return preferences.getInt(_cursorKey(userId)) ?? 0;
  }

  Future<void> setCursor(String userId, int cursor) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setInt(
      _cursorKey(userId),
      cursor,
    );
  }

  Future<void> clearCursor(String userId) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_cursorKey(userId));
  }

  Future<List<Map<String, dynamic>>> getPendingChanges(
    String userId,
  ) async {
    final preferences = await SharedPreferences.getInstance();

    final raw = preferences.getString(_pendingKey(userId));

    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw);

    if (decoded is! List) {
      return [];
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
        )
        .toList();
  }

  Future<void> setPendingChanges(
    String userId,
    List<Map<String, dynamic>> changes,
  ) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(
      _pendingKey(userId),
      jsonEncode(changes),
    );
  }

  Future<void> clearPendingChanges(String userId) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_pendingKey(userId));
  }
}

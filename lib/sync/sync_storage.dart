import 'package:shared_preferences/shared_preferences.dart';

class SyncStorage {
  static const String _cursorPrefix = 'syncCursor_';

  String _key(String userId) => '$_cursorPrefix$userId';

  Future<int> getCursor(String userId) async {
    final preferences = await SharedPreferences.getInstance();

    return preferences.getInt(_key(userId)) ?? 0;
  }

  Future<void> setCursor(String userId, int cursor) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setInt(
      _key(userId),
      cursor,
    );
  }

  Future<void> clearCursor(String userId) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_key(userId));
  }
}

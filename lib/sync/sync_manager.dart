import 'api_client.dart';
import 'remote_change.dart';
import 'sync_storage.dart';

class SyncManager {
  SyncManager({
    required this.apiClient,
    required this.storage,
    required this.userId,
    required this.onRemoteChange,
    required this.getPendingChanges,
    required this.clearPendingChanges,
  });

  final ApiClient apiClient;
  final SyncStorage storage;

  String userId;

  final Future<void> Function(RemoteChange change) onRemoteChange;

  final Future<List<Map<String, dynamic>>> Function()
      getPendingChanges;

  final Future<void> Function()
      clearPendingChanges;

  bool _running = false;

  bool get isRunning => _running;

  Future<void> sync() async {
    if (_running) {
      return;
    }

    if (userId.isEmpty) {
      throw StateError('Synchronisation impossible : userId absent.');
    }

    _running = true;

    try {
      // ============================================================
      // 1. PUSH : local -> serveur
      // ============================================================

      final pending = await getPendingChanges();

      if (pending.isNotEmpty) {
        await apiClient.push(pending);
        await clearPendingChanges();
      }

      // ============================================================
      // 2. PULL : serveur -> local
      // ============================================================

      var cursor = await storage.getCursor(userId);

      while (true) {
        final response = await apiClient.getSync(cursor);

        final rawChanges = response['changes'];

        if (rawChanges is! List) {
          throw StateError(
            'Réponse /sync invalide : '
            '"changes" doit être une liste.',
          );
        }

        final changes = rawChanges
            .map(
              (item) => RemoteChange.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();

        for (final change in changes) {
          await onRemoteChange(change);
        }

        final nextCursor =
            (response['nextCursor'] as num?)?.toInt();

        if (nextCursor == null) {
          throw StateError(
            'Réponse /sync invalide : '
            '"nextCursor" absent.',
          );
        }

        await storage.setCursor(userId, nextCursor);

        cursor = nextCursor;

        final hasMore = response['hasMore'] == true;

        if (!hasMore) {
          break;
        }
      }
    } finally {
      _running = false;
    }
  }
}

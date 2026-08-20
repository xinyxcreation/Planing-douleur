import 'remote_change.dart';

class SyncApplier {
  SyncApplier({
    required this.onPainCategory,
    required this.onActivityType,
    required this.onDayEntry,
    required this.onDayPainLevel,
    required this.onDayActivity,
  });

  final Future<void> Function(RemoteChange change)
      onPainCategory;

  final Future<void> Function(RemoteChange change)
      onActivityType;

  final Future<void> Function(RemoteChange change)
      onDayEntry;

  final Future<void> Function(RemoteChange change)
      onDayPainLevel;

  final Future<void> Function(RemoteChange change)
      onDayActivity;

  Future<void> apply(RemoteChange change) async {
    switch (change.entity) {
      case 'pain_category':
        await onPainCategory(change);
        return;

      case 'activity_type':
        await onActivityType(change);
        return;

      case 'day_entry':
        await onDayEntry(change);
        return;

      case 'day_pain_level':
        await onDayPainLevel(change);
        return;

      case 'day_activity':
        await onDayActivity(change);
        return;

      default:
        throw StateError(
          'Entité de synchronisation inconnue : '
          '${change.entity}',
        );
    }
  }
}

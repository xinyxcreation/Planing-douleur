import 'day_activity.dart';
import 'day_pain_level.dart';

class DayEntry {
  DayEntry({
    required this.id,
    required this.entryDate,
    List<DayPainLevel>? painLevels,
    List<DayActivity>? activities,
    this.deletedAt,
  })  : painLevels = List.of(painLevels ?? []),
        activities = List.of(activities ?? []);

  final String id;
  final String entryDate;
  final DateTime? deletedAt;

  final List<DayPainLevel> painLevels;
  final List<DayActivity> activities;

  int maxPain() {
    if (painLevels.isEmpty) return 0;

    return painLevels
        .map((e) => e.level)
        .reduce((a, b) => a > b ? a : b);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entryDate': entryDate,
        'painLevels': painLevels.map((e) => e.toJson()).toList(),
        'activities': activities.map((e) => e.toJson()).toList(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory DayEntry.fromJson(Map<String, dynamic> json) {
    final rawPain = json['painLevels'];
    final rawActivities = json['activities'];

    return DayEntry(
      id: json['id']?.toString() ?? '',
      entryDate: json['entryDate']?.toString() ?? '',
      painLevels: rawPain is List
          ? rawPain
              .whereType<Map>()
              .map(
                (e) => DayPainLevel.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
          : [],
      activities: rawActivities is List
          ? rawActivities
              .whereType<Map>()
              .map(
                (e) => DayActivity.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
          : [],
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.tryParse(
              json['deletedAt'].toString(),
            ),
    );
  }
}

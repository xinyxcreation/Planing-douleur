class DayActivity {
  DayActivity({
    required this.id,
    required this.dayEntryId,
    required this.activityTypeId,
    this.deletedAt,
  });

  final String id;
  final String dayEntryId;
  final String activityTypeId;
  final DateTime? deletedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'dayEntryId': dayEntryId,
        'activityTypeId': activityTypeId,
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory DayActivity.fromJson(Map<String, dynamic> json) {
    return DayActivity(
      id: json['id'] as String,
      dayEntryId: json['dayEntryId'] as String,
      activityTypeId: json['activityTypeId'] as String,
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.tryParse(json['deletedAt'].toString()),
    );
  }
}

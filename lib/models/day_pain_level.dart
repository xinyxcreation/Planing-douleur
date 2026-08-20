class DayPainLevel {
  DayPainLevel({
    required this.id,
    required this.dayEntryId,
    required this.painCategoryId,
    required this.level,
    this.deletedAt,
  });

  final String id;
  final String dayEntryId;
  final String painCategoryId;
  final int level;
  final DateTime? deletedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'dayEntryId': dayEntryId,
        'painCategoryId': painCategoryId,
        'level': level,
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory DayPainLevel.fromJson(Map<String, dynamic> json) {
    return DayPainLevel(
      id: json['id'] as String,
      dayEntryId: json['dayEntryId'] as String,
      painCategoryId: json['painCategoryId'] as String,
      level: (json['level'] as num).toInt(),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.tryParse(json['deletedAt'].toString()),
    );
  }
}

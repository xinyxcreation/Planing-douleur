class ActivityType {
  ActivityType({
    required this.id,
    required this.name,
    required this.position,
    this.deletedAt,
  });

  final String id;
  final String name;
  final int position;
  final DateTime? deletedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'position': position,
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory ActivityType.fromJson(Map<String, dynamic> json) {
    return ActivityType(
      id: json['id'] as String,
      name: json['name'] as String,
      position: (json['position'] as num?)?.toInt() ?? 0,
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.tryParse(json['deletedAt'].toString()),
    );
  }
}

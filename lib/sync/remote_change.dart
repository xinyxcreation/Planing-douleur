class RemoteChange {
  RemoteChange({
    required this.cursor,
    required this.entity,
    required this.entityId,
    required this.operation,
    required this.changedAt,
    this.data,
  });

  final int cursor;
  final String entity;
  final String entityId;
  final String operation;
  final String changedAt;
  final Map<String, dynamic>? data;

  Map<String, dynamic> toJson() {
    return {
      'cursor': cursor,
      'entity': entity,
      'entityId': entityId,
      'operation': operation,
      'changedAt': changedAt,
      'data': data,
    };
  }

  factory RemoteChange.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawData = json['data'];

    return RemoteChange(
      cursor: (json['cursor'] as num).toInt(),
      entity: json['entity'] as String,
      entityId: json['entityId'] as String,
      operation: json['operation'] as String,
      changedAt: json['changedAt'] as String,
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : null,
    );
  }
}

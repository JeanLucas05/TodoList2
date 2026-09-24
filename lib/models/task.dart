class Task {
  const Task({
    this.id,
    required this.title,
    this.description,
    this.completed = false,
    this.dueDateTime,
    required this.createdAt,
    this.categoryId,
  });

  static const _keep = Object();

  final int? id;
  final String title;
  final String? description;
  final bool completed;
  final DateTime? dueDateTime;
  final DateTime createdAt;
  final int? categoryId;

  Task copyWith({
    Object? id = _keep,
    Object? title = _keep,
    Object? description = _keep,
    Object? completed = _keep,
    Object? dueDateTime = _keep,
    Object? createdAt = _keep,
    Object? categoryId = _keep,
  }) {
    return Task(
      id: identical(id, _keep) ? this.id : id as int?,
      title: identical(title, _keep) ? this.title : title as String,
      description: identical(description, _keep)
          ? this.description
          : description as String?,
      completed: identical(completed, _keep)
          ? this.completed
          : completed as bool,
      dueDateTime: identical(dueDateTime, _keep)
          ? this.dueDateTime
          : dueDateTime as DateTime?,
      createdAt: identical(createdAt, _keep)
          ? this.createdAt
          : createdAt as DateTime,
      categoryId:
          identical(categoryId, _keep) ? this.categoryId : categoryId as int?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'title': title,
      'description': description,
      'completed': completed ? 1 : 0,
      'dueDateTime': dueDateTime?.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'categoryId': categoryId,
    };
  }

  factory Task.fromMap(Map<String, Object?> map) {
    return Task(
      id: map['id'] as int?,
      title: map['title'] as String,
      description: map['description'] as String?,
      completed: (map['completed'] as int? ?? 0) != 0,
      dueDateTime: _dateFromMillis(map['dueDateTime'] as int?),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as int?) ?? 0,
      ),
      categoryId: map['categoryId'] as int?,
    );
  }

  static DateTime? _dateFromMillis(int? millis) =>
      millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);

  @override
  String toString() =>
      'Task(id: $id, title: $title, completed: $completed, '
      'dueDateTime: $dueDateTime, categoryId: $categoryId)';
}

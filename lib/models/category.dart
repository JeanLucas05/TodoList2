class Category {
  const Category({this.id, required this.name, this.color});

  static const _keep = Object();

  final int? id;
  final String name;

  /// Optional ARGB color used by the UI (SPEC §4 optional property).
  final int? color;

  Category copyWith({
    Object? id = _keep,
    Object? name = _keep,
    Object? color = _keep,
  }) {
    return Category(
      id: identical(id, _keep) ? this.id : id as int?,
      name: identical(name, _keep) ? this.name : name as String,
      color: identical(color, _keep) ? this.color : color as int?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'name': name,
      'color': color,
    };
  }

  factory Category.fromMap(Map<String, Object?> map) {
    return Category(
      id: map['id'] as int?,
      name: map['name'] as String,
      color: map['color'] as int?,
    );
  }

  @override
  String toString() => 'Category(id: $id, name: $name, color: $color)';
}

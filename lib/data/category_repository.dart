import '../models/category.dart';
import 'app_database.dart';

/// All SQL for categories.
class CategoryRepository {
  CategoryRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<List<Category>> getAll() async {
    final db = await _appDatabase.database;
    final rows = await db.query('categories', orderBy: 'name COLLATE NOCASE');
    return rows.map(Category.fromMap).toList();
  }

  /// Inserts [category] and returns the generated row id.
  Future<int> insert(Category category) async {
    final db = await _appDatabase.database;
    return db.insert('categories', category.toMap());
  }

  Future<int> update(Category category) async {
    final id = category.id;
    if (id == null) throw ArgumentError('Category has no id');
    final db = await _appDatabase.database;
    return db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes the category and detaches its tasks (they become uncategorized).
  ///
  /// The `UPDATE tasks SET categoryId = NULL` runs in the same transaction as
  /// the `DELETE`, so tasks are never left pointing at a missing category.
  Future<int> delete(int id) async {
    final db = await _appDatabase.database;
    return db.transaction((txn) async {
      await txn.update(
        'tasks',
        {'categoryId': null},
        where: 'categoryId = ?',
        whereArgs: [id],
      );
      return txn.delete('categories', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Number of tasks currently attached to [id].
  Future<int> countTasks(int id) async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM tasks WHERE categoryId = ?',
      [id],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['c'] as int?) ?? 0;
  }
}

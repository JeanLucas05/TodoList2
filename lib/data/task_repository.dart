import 'package:sqflite/sqflite.dart';

import '../models/task.dart';
import 'app_database.dart';

/// All SQL for tasks. Methods throw [DatabaseException] on failure so the
/// caller (`TodoController`) can decide how to report it to the user.
class TaskRepository {
  TaskRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<List<Task>> getAll() async {
    final db = await _appDatabase.database;
    final rows = await db.query('tasks', orderBy: 'createdAt DESC');
    return rows.map(Task.fromMap).toList();
  }

  Future<Task?> findById(int id) async {
    final db = await _appDatabase.database;
    final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Task.fromMap(rows.first);
  }

  /// Inserts [task] and returns the generated row id.
  Future<int> insert(Task task) async {
    final db = await _appDatabase.database;
    return db.insert('tasks', task.toMap());
  }

  /// Updates [task] and returns the number of modified rows.
  Future<int> update(Task task) async {
    final id = task.id;
    if (id == null) throw ArgumentError('Task has no id');
    final db = await _appDatabase.database;
    return db.update('tasks', task.toMap(), where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes the task and returns the number of removed rows.
  Future<int> delete(int id) async {
    final db = await _appDatabase.database;
    return db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }
}

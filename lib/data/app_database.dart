import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Owns the SQLite connection and the schema.
///
/// A single connection is opened lazily and reused for the whole app
/// lifetime. Everything SQL-related lives in the repository classes.
class AppDatabase {
  AppDatabase({String? path}) : _explicitPath = path;

  /// Allows tests (and tools) to inject `:memory:` or a temp file.
  final String? _explicitPath;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final String path =
        _explicitPath ?? p.join(await _defaultDirectory(), 'todoapp.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    );
  }

  /// Cross-platform location for app-private data. Falls back to the
  /// factory-provided databases directory if `path_provider` is unavailable
  /// (e.g. inside a bare Dart test).
  Future<String> _defaultDirectory() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return dir.path;
    } catch (e) {
      debugPrint('AppDatabase: path_provider unavailable ($e)');
      return getDatabasesPath();
    }
  }

  Future<void> _onConfigure(Database db) async {
    // Required so that the ON DELETE SET NULL foreign key clause works.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT    NOT NULL,
        color INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE tasks (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        title       TEXT    NOT NULL,
        description TEXT,
        completed   INTEGER NOT NULL DEFAULT 0,
        dueDateTime INTEGER,
        createdAt   INTEGER NOT NULL,
        categoryId  INTEGER,
        FOREIGN KEY (categoryId) REFERENCES categories(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_tasks_category ON tasks(categoryId)',
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}

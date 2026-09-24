import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todoapp/data/app_database.dart';
import 'package:todoapp/data/category_repository.dart';
import 'package:todoapp/data/task_repository.dart';
import 'package:todoapp/models/category.dart';
import 'package:todoapp/models/task.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('todoapp_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String path() => '${tempDir.path}/todoapp.db';

  AppDatabase openDb() => AppDatabase(path: path());

  Task newTask(
    String title, {
    int? categoryId,
    DateTime? dueDateTime,
    bool completed = false,
  }) {
    return Task(
      title: title,
      createdAt: DateTime.now(),
      categoryId: categoryId,
      dueDateTime: dueDateTime,
      completed: completed,
    );
  }

  test('tasks survive closing and reopening the database', () async {
    final first = openDb();
    await TaskRepository(first).insert(newTask('Persist me'));

    final second = openDb();
    final reloaded = await TaskRepository(second).getAll();

    expect(reloaded, hasLength(1));
    expect(reloaded.single.title, 'Persist me');
    expect(reloaded.single.id, isNotNull);

    await first.close();
    await second.close();
  });

  test('round-trips every task field', () async {
    final db = openDb();
    final repo = TaskRepository(db);
    final due = DateTime(2026, 12, 31, 18, 30);

    final categories = CategoryRepository(db);
    final categoryId = await categories.insert(Category(name: 'Work'));

    await repo.insert(
      newTask('Full', categoryId: categoryId, dueDateTime: due),
    );

    final stored = (await repo.getAll()).single;
    expect(stored.title, 'Full');
    expect(stored.completed, isFalse);
    expect(stored.dueDateTime, due);
    expect(stored.categoryId, categoryId);
    expect(
      stored.createdAt.difference(DateTime.now()).inSeconds.abs(),
      lessThan(5),
    );

    await db.close();
  });

  test('update and delete tasks', () async {
    final db = openDb();
    final repo = TaskRepository(db);
    await repo.insert(newTask('Original'));
    final task = (await repo.getAll()).single;

    await repo.update(task.copyWith(title: 'Renamed', completed: true));
    var stored = (await repo.getAll()).single;
    expect(stored.title, 'Renamed');
    expect(stored.completed, isTrue);

    expect(await repo.delete(task.id!), 1);
    expect(await repo.getAll(), isEmpty);

    await db.close();
  });

  test('deleting a category makes its tasks uncategorized', () async {
    final db = openDb();
    final categories = CategoryRepository(db);
    final tasks = TaskRepository(db);

    final categoryId = await categories.insert(Category(name: 'Work'));
    await tasks.insert(newTask('A', categoryId: categoryId));
    await tasks.insert(newTask('B', categoryId: categoryId));
    await tasks.insert(newTask('C'));

    expect(await categories.delete(categoryId), 1);

    final stored = await tasks.getAll();
    expect(stored, hasLength(3));
    expect(stored.where((t) => t.categoryId != null), isEmpty,
        reason: 'all tasks must lose their deleted category');
    expect(await categories.getAll(), isEmpty);

    await db.close();
  });

  test('categories are stored and returned ordered by name', () async {
    final db = openDb();
    final categories = CategoryRepository(db);

    await categories.insert(Category(name: 'Work'));
    await categories.insert(Category(name: 'personal'));
    await categories.insert(Category(name: 'Study'));

    final names = (await categories.getAll()).map((c) => c.name).toList();
    expect(names, ['personal', 'Study', 'Work']);

    await db.close();
  });
}

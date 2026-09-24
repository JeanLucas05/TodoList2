import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todoapp/data/app_database.dart';
import 'package:todoapp/data/category_repository.dart';
import 'package:todoapp/data/task_repository.dart';
import 'package:todoapp/models/task.dart';
import 'package:todoapp/services/notification_service.dart';
import 'package:todoapp/state/todo_controller.dart';

/// Records every notification call so tests can assert the contract from
/// SPEC §10 without touching platform channels.
class _RecordingScheduler implements NotificationScheduler {
  final List<int> synced = <int>[];
  final List<int> cancelled = <int>[];

  @override
  Future<void> syncForTask(Task task) async {
    if (task.id != null) synced.add(task.id!);
  }

  @override
  Future<void> cancelForTask(Task task) async {
    if (task.id != null) cancelled.add(task.id!);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late _RecordingScheduler notifications;
  late TodoController controller;

  setUp(() async {
    db = AppDatabase(path: inMemoryDatabasePath);
    notifications = _RecordingScheduler();
    controller = TodoController(
      taskRepository: TaskRepository(db),
      categoryRepository: CategoryRepository(db),
      notifications: notifications,
    );
    await controller.load();
  });

  tearDown(() async {
    await db.close();
  });

  Future<String?> create(String title, {int? categoryId, DateTime? dueDateTime}) {
    return controller.createTask(
      title: title,
      categoryId: categoryId,
      dueDateTime: dueDateTime,
    );
  }

  group('task CRUD', () {
    test('creates, reads, updates and deletes', () async {
      expect(await create('First'), isNull);
      expect(controller.tasks, hasLength(1));

      final task = controller.tasks.single;
      expect(await controller.updateTask(task.copyWith(title: 'Second')), isNull);
      expect(controller.tasks.single.title, 'Second');

      expect(await controller.deleteTask(controller.tasks.single), isNull);
      expect(controller.tasks, isEmpty);
    });

    test('rejects an empty title', () async {
      final error = await create('   ');
      expect(error, isNotNull);
      expect(controller.tasks, isEmpty);
    });

    test('toggles completed status', () async {
      await create('Toggle');
      final task = controller.tasks.single;

      expect(await controller.toggleCompleted(task), isNull);
      expect(controller.tasks.single.completed, isTrue);

      expect(await controller.toggleCompleted(controller.tasks.single), isNull);
      expect(controller.tasks.single.completed, isFalse);
    });

    test('keeps the data after an explicit reload', () async {
      await create('Persistent');
      await controller.load();
      expect(controller.tasks.single.title, 'Persistent');
    });
  });

  group('category CRUD', () {
    test('creates, renames and deletes', () async {
      expect(await controller.createCategory('Work'), isNull);
      expect(controller.categories.single.name, 'Work');

      final id = controller.categories.single.id!;
      expect(await controller.renameCategory(id, 'Office'), isNull);
      expect(controller.categories.single.name, 'Office');

      expect(await controller.deleteCategory(id), isNull);
      expect(controller.categories, isEmpty);
    });

    test('rejects an empty category name', () async {
      expect(await controller.createCategory('  '), isNotNull);
      expect(controller.categories, isEmpty);
    });

    test('deleting a category detaches its tasks', () async {
      await controller.createCategory('Work');
      final id = controller.categories.single.id!;
      await create('Task A', categoryId: id);
      await create('Task B');

      expect(await controller.deleteCategory(id), isNull);
      expect(controller.tasks, hasLength(2));
      expect(controller.tasks.every((t) => t.categoryId == null), isTrue);
    });

    test('clears a category filter that points at a deleted category',
        () async {
      await controller.createCategory('Work');
      final id = controller.categories.single.id!;
      controller.setCategoryFilter(id);

      await controller.deleteCategory(id);

      expect(controller.categoryFilterId, isNull);
    });
  });

  group('filtering (SPEC §12)', () {
    test('filters by status', () async {
      await create('Pending one');
      await create('Done one');
      await controller.toggleCompleted(
        controller.tasks.firstWhere((t) => t.title == 'Done one'),
      );

      controller.setStatusFilter(StatusFilter.all);
      expect(controller.filteredTasks, hasLength(2));

      controller.setStatusFilter(StatusFilter.completed);
      expect(controller.filteredTasks.map((t) => t.title), ['Done one']);

      controller.setStatusFilter(StatusFilter.pending);
      expect(controller.filteredTasks.map((t) => t.title), ['Pending one']);
    });

    test('filters by category', () async {
      await controller.createCategory('Work');
      await controller.createCategory('Home');
      final work = controller.categories.firstWhere((c) => c.name == 'Work');
      final home = controller.categories.firstWhere((c) => c.name == 'Home');

      await create('At work', categoryId: work.id);
      await create('At home', categoryId: home.id);
      await create('Nowhere');

      controller.setCategoryFilter(work.id);
      expect(controller.filteredTasks.map((t) => t.title), ['At work']);

      controller.setCategoryFilter(null);
      expect(controller.filteredTasks, hasLength(3));
    });

    test('combines status and category filters', () async {
      await controller.createCategory('Work');
      final work = controller.categories.single;

      await create('Open', categoryId: work.id);
      await create('Closed', categoryId: work.id);
      await controller.toggleCompleted(
        controller.tasks.firstWhere((t) => t.title == 'Closed'),
      );
      await create('Other category');

      controller.setCategoryFilter(work.id);
      controller.setStatusFilter(StatusFilter.pending);
      expect(controller.filteredTasks.map((t) => t.title), ['Open']);

      controller.setStatusFilter(StatusFilter.completed);
      expect(controller.filteredTasks.map((t) => t.title), ['Closed']);
    });
  });

  group('notification contract (SPEC §10)', () {
    test('creating a task with a future due date schedules a reminder',
        () async {
      await create('With reminder',
          dueDateTime: DateTime.now().add(const Duration(hours: 2)));
      expect(notifications.synced, hasLength(1));
      expect(notifications.cancelled, isEmpty,
          reason: 'the controller delegates cancel-inside-sync to the service');
    });

    test('creating a task without a due date still syncs; the service decides',
        () async {
      await create('No reminder');
      expect(notifications.synced, hasLength(1),
          reason: 'the controller always delegates the scheduling decision');
      expect(notifications.cancelled, isEmpty);
    });

    test('editing the due date re-syncs the notification', () async {
      await create('Editable',
          dueDateTime: DateTime.now().add(const Duration(hours: 1)));
      notifications.synced.clear();
      notifications.cancelled.clear();

      final task = controller.tasks.single;
      await controller.updateTask(
        task.copyWith(dueDateTime: DateTime.now().add(const Duration(days: 1))),
      );

      expect(notifications.synced, [task.id]);
      expect(notifications.cancelled, isEmpty);
    });

    test('removing the due date re-syncs so the service can cancel', () async {
      await create('Removable',
          dueDateTime: DateTime.now().add(const Duration(hours: 1)));
      notifications.synced.clear();
      notifications.cancelled.clear();

      final task = controller.tasks.single;
      await controller.updateTask(task.copyWith(dueDateTime: null));

      expect(notifications.synced, [task.id]);
      expect(notifications.cancelled, isEmpty);
    });

    test('completing a task re-syncs its notification', () async {
      await create('Completable',
          dueDateTime: DateTime.now().add(const Duration(hours: 1)));
      notifications.synced.clear();

      await controller.toggleCompleted(controller.tasks.single);

      expect(notifications.synced, [controller.tasks.single.id]);
    });

    test('deleting a task cancels its notification', () async {
      await create('Deletable',
          dueDateTime: DateTime.now().add(const Duration(hours: 1)));
      final id = controller.tasks.single.id;
      notifications.synced.clear();
      notifications.cancelled.clear();

      await controller.deleteTask(controller.tasks.single);

      expect(notifications.cancelled, contains(id));
      expect(notifications.synced, isEmpty);
    });
  });
}

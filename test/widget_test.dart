import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todoapp/app.dart';
import 'package:todoapp/data/app_database.dart';
import 'package:todoapp/data/category_repository.dart';
import 'package:todoapp/data/task_repository.dart';
import 'package:todoapp/models/task.dart';
import 'package:todoapp/services/notification_service.dart';
import 'package:todoapp/state/todo_controller.dart';

class _NoNotifications implements NotificationScheduler {
  @override
  Future<void> cancelForTask(Task task) async {}

  @override
  Future<void> syncForTask(Task task) async {}
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late TodoController controller;

  setUp(() async {
    db = AppDatabase(path: inMemoryDatabasePath);
    controller = TodoController(
      taskRepository: TaskRepository(db),
      categoryRepository: CategoryRepository(db),
      notifications: _NoNotifications(),
    );
    await controller.load();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();
  }

  /// sqflite_ffi futures only advance on the real event loop, which the
  /// fake-async test zone never runs. Alternate real turns with pumps
  /// (advancing the fake clock) until [condition] holds, then settle.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int attempts = 100,
  }) async {
    for (var i = 0; i < attempts && !condition(); i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(condition(), isTrue, reason: 'condition never became true');
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state on first launch', (tester) async {
    await pumpApp(tester);

    expect(find.text('Tasks'), findsOneWidget);
    expect(find.textContaining('No tasks yet'), findsOneWidget);
  });

  testWidgets('creates a task from the editor screen', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('New task'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Buy milk');
    await tester.tap(find.text('Create'));
    await pumpUntil(tester, () => find.text('New task').evaluate().isEmpty);

    expect(find.text('Buy milk'), findsOneWidget);
    expect(controller.tasks.single.title, 'Buy milk');
  });

  testWidgets('rejects a task without a title', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
    expect(find.text('New task'), findsOneWidget,
        reason: 'the editor must stay open');
    expect(controller.tasks, isEmpty);
  });

  testWidgets('opens an existing task for editing', (tester) async {
    await tester.runAsync(() => controller.createTask(title: 'Existing task'));
    await pumpApp(tester);

    await tester.tap(find.text('Existing task'));
    await tester.pumpAndSettle();

    expect(find.text('Edit task'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TextFormField).first,
        matching: find.text('Existing task'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('marks a task as completed from the list', (tester) async {
    await tester.runAsync(() => controller.createTask(title: 'To complete'));
    await pumpApp(tester);

    await tester.tap(find.byType(Checkbox));
    await pumpUntil(
        tester,
        () =>
            !controller.isLoading && controller.tasks.single.completed);

    expect(controller.tasks.single.completed, isTrue);
  });

  testWidgets('filters tasks by status', (tester) async {
    await tester.runAsync(() => controller.createTask(title: 'Pending task'));
    await tester.runAsync(() => controller.createTask(title: 'Done task'));
    await tester.runAsync(
      () => controller.toggleCompleted(
        controller.tasks.firstWhere((t) => t.title == 'Done task'),
      ),
    );
    await pumpApp(tester);

    expect(find.text('Pending task'), findsOneWidget);
    expect(find.text('Done task'), findsOneWidget);

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();

    expect(find.text('Done task'), findsOneWidget);
    expect(find.text('Pending task'), findsNothing);

    await tester.tap(find.text('Pending'));
    await tester.pumpAndSettle();

    expect(find.text('Pending task'), findsOneWidget);
    expect(find.text('Done task'), findsNothing);
  });

  testWidgets('navigates to category management and creates a category',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Manage categories'));
    await tester.pumpAndSettle();
    expect(find.text('Categories'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Work');
    await tester.tap(find.text('Add'));
    await pumpUntil(
        tester,
        () =>
            !controller.isLoading && controller.categories.isNotEmpty);

    expect(find.text('Work'), findsOneWidget);
    expect(controller.categories.single.name, 'Work');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Tasks'), findsOneWidget);
  });

  testWidgets('renames a category from the management screen', (tester) async {
    await tester.runAsync(() => controller.createCategory('Work'));
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Manage categories'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final renameField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(renameField, 'Office');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpUntil(
        tester,
        () =>
            !controller.isLoading &&
            controller.categories.single.name == 'Office');

    expect(controller.categories.single.name, 'Office');
  });

  testWidgets('deleting a category keeps its tasks, uncategorized',
      (tester) async {
    await tester.runAsync(() => controller.createCategory('Work'));
    final work = controller.categories.single;
    await tester
        .runAsync(() => controller.createTask(title: 'Assigned', categoryId: work.id));
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Manage categories'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await pumpUntil(
        tester,
        () =>
            !controller.isLoading && controller.categories.isEmpty);

    expect(controller.categories, isEmpty);
    expect(controller.tasks.single.categoryId, isNull);
  });

  testWidgets('deleting a task from the editor removes it', (tester) async {
    await tester.runAsync(() => controller.createTask(title: 'Doomed'));
    await pumpApp(tester);

    await tester.tap(find.text('Doomed'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete task'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await pumpUntil(
        tester,
        () =>
            !controller.isLoading &&
            controller.tasks.isEmpty &&
            find.text('Edit task').evaluate().isEmpty);

    expect(controller.tasks, isEmpty);
    expect(find.textContaining('No tasks yet'), findsOneWidget);
  });
}

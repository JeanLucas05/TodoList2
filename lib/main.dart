import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/category_repository.dart';
import 'data/task_repository.dart';
import 'services/notification_service.dart';
import 'state/todo_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The `sqflite` plugin only registers Android/iOS/macOS implementations,
  // so on desktop (Linux) the FFI implementation of the very same API has to
  // be installed manually. On Android this branch is skipped and the
  // plugin-registered factory is used instead.
  if (!kIsWeb &&
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize notifications before anything can schedule one.
  final notifications = NotificationService.instance;
  await notifications.init();

  final database = AppDatabase();
  final controller = TodoController(
    taskRepository: TaskRepository(database),
    categoryRepository: CategoryRepository(database),
    notifications: notifications,
  );
  await controller.load();

  runApp(TodoApp(controller: controller));

  // Ask for the notification permission after the first frame so startup is
  // never blocked by a system dialog (Android 13+ / iOS).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    notifications.requestPermission().then(
          (granted) => debugPrint('Notification permission granted: $granted'),
          onError: (Object e) =>
              debugPrint('Notification permission request error: $e'),
        );
  });
}

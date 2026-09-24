import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/category_management_screen.dart';
import 'screens/task_editor_screen.dart';
import 'screens/task_list_screen.dart';
import 'state/todo_controller.dart';

/// Root widget: theme + navigation + the shared [TodoController].
class TodoApp extends StatelessWidget {
  const TodoApp({super.key, required this.controller});

  final TodoController controller;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TodoController>.value(
      value: controller,
      child: MaterialApp(
        title: 'Todo App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        initialRoute: TaskListScreen.route,
        routes: <String, WidgetBuilder>{
          TaskListScreen.route: (_) => const TaskListScreen(),
          CategoryManagementScreen.route: (_) =>
              const CategoryManagementScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == TaskEditorScreen.route) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => TaskEditorScreen(
                taskId: TaskEditorScreen.idOf(settings.arguments),
              ),
            );
          }
          return null;
        },
      ),
    );
  }
}

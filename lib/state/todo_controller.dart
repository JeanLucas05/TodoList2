import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:sqflite/sqflite.dart';

import '../data/category_repository.dart';
import '../data/task_repository.dart';
import '../models/category.dart';
import '../models/task.dart';
import '../services/notification_service.dart';

enum StatusFilter { all, pending, completed }

/// Single source of truth for the whole application.
///
/// Screens never touch SQLite or the notification plugin directly: they call
/// one of the methods below, which return `null` on success or a
/// user-facing message on failure (SPEC §13).
class TodoController extends ChangeNotifier {
  TodoController({
    required TaskRepository taskRepository,
    required CategoryRepository categoryRepository,
    NotificationScheduler? notifications,
  })  : _taskRepository = taskRepository,
        _categoryRepository = categoryRepository,
        _notifications = notifications ?? NotificationService.instance;

  final TaskRepository _taskRepository;
  final CategoryRepository _categoryRepository;
  final NotificationScheduler _notifications;

  List<Task> _tasks = <Task>[];
  List<Category> _categories = <Category>[];

  StatusFilter statusFilter = StatusFilter.all;
  int? categoryFilterId;
  bool isLoading = false;
  String? loadError;

  List<Task> get tasks => List<Task>.unmodifiable(_tasks);
  List<Category> get categories => List<Category>.unmodifiable(_categories);

  /// Tasks matching the current status + category filters (SPEC §12).
  List<Task> get filteredTasks {
    return _tasks.where((task) {
      switch (statusFilter) {
        case StatusFilter.all:
          break;
        case StatusFilter.pending:
          if (task.completed) return false;
        case StatusFilter.completed:
          if (!task.completed) return false;
      }
      final filterId = categoryFilterId;
      if (filterId != null && task.categoryId != filterId) return false;
      return true;
    }).toList();
  }

  Task? taskById(int? id) {
    if (id == null) return null;
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  Category? categoryById(int? id) {
    if (id == null) return null;
    for (final category in _categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  String? categoryName(int? id) => categoryById(id)?.name;

  void setStatusFilter(StatusFilter filter) {
    if (statusFilter == filter) return;
    statusFilter = filter;
    notifyListeners();
  }

  void setCategoryFilter(int? id) {
    if (categoryFilterId == id) return;
    categoryFilterId = id;
    notifyListeners();
  }

  /// Re-reads everything from SQLite. Called at startup and after mutations
  /// so the UI always reflects the persisted state.
  Future<String?> load() async {
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      await _readAll();
      return null;
    } catch (e) {
      loadError = 'Could not load data: $e';
      return loadError;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Reload used after a mutation: no loading flag, so the list does not
  /// flash empty while the change is written.
  Future<void> _readAll() async {
    _tasks = await _taskRepository.getAll();
    _categories = await _categoryRepository.getAll();
    _validateCategoryFilter();
  }

  Future<String?> createTask({
    required String title,
    String? description,
    DateTime? dueDateTime,
    int? categoryId,
    bool completed = false,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return 'Title cannot be empty.';
    }
    final task = Task(
      title: trimmed,
      description: _emptyToNull(description),
      completed: completed,
      dueDateTime: dueDateTime,
      createdAt: DateTime.now(),
      categoryId: categoryId,
    );
    try {
      final id = await _taskRepository.insert(task);
      await _notifications.syncForTask(task.copyWith(id: id));
      return _reloadAfterMutation();
    } catch (e) {
      return _message('Could not save the task', e);
    }
  }

  Future<String?> updateTask(Task task) async {
    if (task.id == null) return 'This task no longer exists.';
    final trimmed = task.title.trim();
    if (trimmed.isEmpty) return 'Title cannot be empty.';
    final updated =
        task.copyWith(title: trimmed, description: _emptyToNull(task.description));
    try {
      final rows = await _taskRepository.update(updated);
      if (rows == 0) return 'This task no longer exists.';
      await _notifications.syncForTask(updated);
      return _reloadAfterMutation();
    } catch (e) {
      return _message('Could not update the task', e);
    }
  }

  Future<String?> toggleCompleted(Task task) async {
    return updateTask(task.copyWith(completed: !task.completed));
  }

  Future<String?> deleteTask(Task task) async {
    if (task.id == null) return 'This task no longer exists.';
    try {
      await _notifications.cancelForTask(task);
      final rows = await _taskRepository.delete(task.id!);
      if (rows == 0) return 'This task no longer exists.';
      return _reloadAfterMutation();
    } catch (e) {
      return _message('Could not delete the task', e);
    }
  }

  Future<String?> createCategory(String name, {int? color}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Category name cannot be empty.';
    try {
      await _categoryRepository
          .insert(Category(name: trimmed, color: color));
      return _reloadAfterMutation();
    } catch (e) {
      return _message('Could not create the category', e);
    }
  }

  Future<String?> renameCategory(int id, String name, {int? color}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Category name cannot be empty.';
    final existing = categoryById(id);
    if (existing == null) return 'This category no longer exists.';
    try {
      await _categoryRepository.update(
        existing.copyWith(name: trimmed, color: color ?? existing.color),
      );
      return _reloadAfterMutation();
    } catch (e) {
      return _message('Could not rename the category', e);
    }
  }

  /// Tasks using this category become uncategorized (SPEC §6, Screen 3).
  Future<String?> deleteCategory(int id) async {
    try {
      final rows = await _categoryRepository.delete(id);
      if (rows == 0) return 'This category no longer exists.';
      if (categoryFilterId == id) categoryFilterId = null;
      return _reloadAfterMutation();
    } catch (e) {
      return _message('Could not delete the category', e);
    }
  }

  Future<String?> _reloadAfterMutation() async {
    final error = await load();
    if (error != null) return error;
    // The category filter may point at something that no longer exists.
    _validateCategoryFilter();
    notifyListeners();
    return null;
  }

  void _validateCategoryFilter() {
    final filterId = categoryFilterId;
    if (filterId != null && categoryById(filterId) == null) {
      categoryFilterId = null;
    }
  }

  static String? _emptyToNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _message(String context, Object error) {
    if (error is DatabaseException) {
      return '$context: $error';
    }
    return '$context: $error';
  }
}

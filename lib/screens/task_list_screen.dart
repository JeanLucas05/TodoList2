import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../state/todo_controller.dart';
import '../utils/date_format.dart';
import 'category_management_screen.dart';
import 'task_editor_screen.dart';

/// Screen 1 — task list, filters and the entry point to the other screens.
class TaskListScreen extends StatelessWidget {
  const TaskListScreen({super.key});

  static const String route = '/';

  Future<void> _report(
    BuildContext context,
    Future<String?> action,
  ) async {
    final error = await action;
    if (error == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TodoController>();
    final visible = controller.filteredTasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(
            tooltip: 'Manage categories',
            icon: const Icon(Icons.label_outline),
            onPressed: () => Navigator.of(context)
                .pushNamed(CategoryManagementScreen.route),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(controller: controller),
          if (controller.loadError != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.loadError!,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onErrorContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _report(context, controller.load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: controller.isLoading && controller.tasks.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? _EmptyState(
                        filtered: controller.statusFilter !=
                                StatusFilter.all ||
                            controller.categoryFilterId != null,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _TaskTile(task: visible[index]),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add task',
        onPressed: () => Navigator.of(context).pushNamed(
          TaskEditorScreen.route,
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final TodoController controller;

  @override
  Widget build(BuildContext context) {
    final categories = controller.categories;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in StatusFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (filter) {
                        StatusFilter.all => 'All',
                        StatusFilter.pending => 'Pending',
                        StatusFilter.completed => 'Completed',
                      }),
                      selected: controller.statusFilter == filter,
                      onSelected: (_) =>
                          controller.setStatusFilter(filter),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              isExpanded: true,
              value: controller.categoryFilterId,
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All categories'),
                ),
                for (final category in categories)
                  DropdownMenuItem<int?>(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: controller.setCategoryFilter,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<TodoController>();
    final category = controller.categoryName(task.categoryId);
    final due = task.dueDateTime;
    final overdue =
        due != null && !task.completed && due.isBefore(DateTime.now());

    final subtitleParts = <Widget>[
      if (category != null)
        _MetaItem(icon: Icons.label_outline, text: category),
      if (due != null)
        _MetaItem(
          icon: Icons.schedule,
          text: formatDueDate(due),
          color: overdue ? Theme.of(context).colorScheme.error : null,
        ),
    ];

    return ListTile(
      leading: Checkbox(
        value: task.completed,
        onChanged: (_) => _run(
          context,
          controller.toggleCompleted(task),
        ),
      ),
      title: Text(
        task.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: task.completed
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: task.description == null && subtitleParts.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.description != null)
                  Text(
                    task.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ...subtitleParts,
              ],
            ),
      onTap: () => Navigator.of(context).pushNamed(
        TaskEditorScreen.route,
        arguments: task.id,
      ),
    );
  }

  Future<void> _run(BuildContext context, Future<String?> action) async {
    final error = await action;
    if (error == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error)));
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: style?.color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered ? Icons.filter_alt_off_outlined : Icons.checklist,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              filtered
                  ? 'No tasks match the current filters.'
                  : 'No tasks yet. Tap + to create one.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/todo_controller.dart';

/// Screen 3 — create, rename and delete categories.
///
/// Deleting a category detaches its tasks: they become **uncategorized**
/// (their `categoryId` is set to `NULL` inside the same transaction).
class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  static const String route = '/categories';

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _report(Future<String?> action) async {
    final error = await action;
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _create() async {
    final name = _nameController.text;
    if (name.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Category name cannot be empty.')));
      return;
    }
    final error = await context.read<TodoController>().createCategory(name);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    _nameController.clear();
  }

  Future<void> _rename(int id, String currentName) async {
    final controller = context.read<TodoController>();
    final field = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(
          controller: field,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Do not dispose [field] here: showDialog's future completes as soon as
    // the route starts popping, while the dialog is still in the tree
    // animating out. Disposing then trips "used after dispose" on the next
    // frame. The controller is released with the route.
    if (name == null || !mounted) return;
    await _report(controller.renameCategory(id, name));
  }

  Future<void> _delete(int id, String name) async {
    final controller = context.read<TodoController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          '"$name" will be removed. Tasks using it will not be deleted — '
          'they simply become uncategorized.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _report(controller.deleteCategory(id));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TodoController>();
    final categories = controller.categories;

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'New category',
                      hintText: 'Personal, Work, Study...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: categories.isEmpty
                ? const Center(
                    child: Text('No categories yet. Create one above.'),
                  )
                : ListView.separated(
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(
                            category.color ?? 0xFF9E9E9E,
                          ),
                          child: Text(
                            category.name.isEmpty
                                ? '?'
                                : category.name[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(category.name),
                        subtitle: Text(
                          '${_countFor(controller, category.id)} task(s)',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Rename',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: category.id == null
                                  ? null
                                  : () => _rename(category.id!, category.name),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: category.id == null
                                  ? null
                                  : () => _delete(category.id!, category.name),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  int _countFor(TodoController controller, int? id) {
    if (id == null) return 0;
    var count = 0;
    for (final task in controller.tasks) {
      if (task.categoryId == id) count++;
    }
    return count;
  }
}

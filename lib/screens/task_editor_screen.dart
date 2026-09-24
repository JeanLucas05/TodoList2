import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../state/todo_controller.dart';
import '../utils/date_format.dart';

/// Screen 2 — create or edit a single task.
///
/// Navigation passes only the task **id** as route argument; the editor reads
/// the task from [TodoController] so it always shows the persisted state.
class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({super.key, this.taskId});

  static const String route = '/task';

  /// Reads the id passed with `Navigator.pushNamed(route, arguments: id)`.
  static int? idOf(Object? arguments) {
    if (arguments is int) return arguments;
    if (arguments is String) return int.tryParse(arguments);
    return null;
  }

  final int? taskId;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  Task? _existing;
  DateTime? _dueDateTime;
  int? _categoryId;
  bool _completed = false;
  bool _initialised = false;
  bool _saving = false;

  bool get _isEditing => _existing != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final controller = context.read<TodoController>();
    final task = controller.taskById(widget.taskId);
    if (task != null) {
      _existing = task;
      _titleController.text = task.title;
      _descriptionController.text = task.description ?? '';
      _dueDateTime = task.dueDateTime;
      _categoryId = task.categoryId;
      _completed = task.completed;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _dueDateTime ??
        DateTime(now.year, now.month, now.day, now.hour);
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime(2000)) ? now : initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = _dueDateTime == null
        ? TimeOfDay.fromDateTime(initial)
        : TimeOfDay.fromDateTime(_dueDateTime!);
    setState(() {
      _dueDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final current = _dueDateTime ?? DateTime(now.year, now.month, now.day);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(() {
      _dueDateTime = DateTime(
        current.year,
        current.month,
        current.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final controller = context.read<TodoController>();
    setState(() => _saving = true);

    final String? error;
    final existing = _existing;
    if (existing == null) {
      error = await controller.createTask(
        title: _titleController.text,
        description: _descriptionController.text,
        dueDateTime: _dueDateTime,
        categoryId: _categoryId,
        completed: _completed,
      );
    } else {
      error = await controller.updateTask(
        existing.copyWith(
          title: _titleController.text,
          description: _descriptionController.text,
          dueDateTime: _dueDateTime,
          categoryId: _categoryId,
          completed: _completed,
        ),
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _cancel() async {
    final dirty = _isEditing ||
        _titleController.text.trim().isNotEmpty ||
        _descriptionController.text.trim().isNotEmpty ||
        _dueDateTime != null ||
        _categoryId != null ||
        _completed;
    if (!dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await _confirm(
      title: 'Discard changes?',
      message: 'Your edits will be lost.',
      confirmLabel: 'Discard',
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = _existing;
    if (existing == null) return;
    final confirmed = await _confirm(
      title: 'Delete task?',
      message: '"${existing.title}" will be removed permanently.\n'
          'Its scheduled notification will be cancelled.',
      confirmLabel: 'Delete',
    );
    if (confirmed != true || !mounted) return;

    final error = await context.read<TodoController>().deleteTask(existing);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop();
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TodoController>();

    if (widget.taskId != null && _existing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task')),
        body: const Center(child: Text('This task no longer exists.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit task' : 'New task'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete task',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'What needs to be done?',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty)
                      ? 'Title is required'
                      : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text('Due date & time', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text(
                    _dueDateTime == null
                        ? 'Pick a date'
                        : _dueDateTime.toString().substring(0, 10),
                  ),
                  onPressed: _pickDate,
                ),
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(
                    _dueDateTime == null
                        ? 'Pick a time'
                        : TimeOfDay.fromDateTime(_dueDateTime!)
                            .format(context),
                  ),
                  onPressed: _pickTime,
                ),
                if (_dueDateTime != null)
                  ActionChip(
                    avatar: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear'),
                    onPressed: () => setState(() => _dueDateTime = null),
                  ),
              ],
            ),
            if (_dueDateTime != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Reminder: ${formatDueDate(_dueDateTime!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 24),
            DropdownButtonFormField<int?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('No category'),
                ),
                for (final category in controller.categories)
                  DropdownMenuItem<int?>(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Completed'),
              subtitle: const Text('Mark this task as done'),
              value: _completed,
              onChanged: (value) => setState(() => _completed = value),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _cancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isEditing ? 'Save' : 'Create'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

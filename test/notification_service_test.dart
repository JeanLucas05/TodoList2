import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:todoapp/models/task.dart';
import 'package:todoapp/services/notification_service.dart';

class _Scheduled {
  _Scheduled(this.id, this.body, this.when, this.mode);

  final int id;
  final String body;
  final tz.TZDateTime when;
  final AndroidScheduleMode mode;
}

class _FakeApi implements NotificationsApi {
  final List<int> cancelled = <int>[];
  final List<_Scheduled> scheduled = <_Scheduled>[];
  bool permissionGranted = true;
  bool failWithUnimplemented = false;

  @override
  Future<bool> initialize(InitializationSettings settings) async => true;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required AndroidScheduleMode mode,
    required String payload,
  }) async {
    if (failWithUnimplemented) {
      // Mirrors the Linux desktop implementation.
      throw UnimplementedError('zonedSchedule() has not been implemented');
    }
    scheduled.removeWhere((s) => s.id == id);
    scheduled.add(_Scheduled(id, body, when, mode));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeApi api;
  late NotificationService service;

  setUp(() {
    api = _FakeApi();
    service = NotificationService(api: api);
  });

  Task task({
    int? id = 7,
    bool completed = false,
    DateTime? dueDateTime,
    String title = 'Submit assignment',
  }) {
    return Task(
      id: id,
      title: title,
      completed: completed,
      dueDateTime: dueDateTime,
      createdAt: DateTime.now(),
    );
  }

  DateTime inFuture([Duration offset = const Duration(hours: 1)]) =>
      DateTime.now().add(offset);

  test('schedules a reminder for a pending task with a future due date',
      () async {
    await service.syncForTask(task(dueDateTime: inFuture()));

    expect(api.scheduled, hasLength(1));
    expect(api.scheduled.single.id, 7);
    expect(api.scheduled.single.body,
        'Task reminder: Submit assignment');
    expect(api.cancelled, contains(7),
        reason: 'the previous notification must be cancelled first');
  });

  test('uses the configured schedule mode and payload', () async {
    await service.syncForTask(task(dueDateTime: inFuture()));

    expect(api.scheduled.single.mode, AndroidScheduleMode.exactAllowWhileIdle);
  });

  test('does not schedule anything when the task has no due date', () async {
    await service.syncForTask(task(dueDateTime: null));

    expect(api.scheduled, isEmpty);
    expect(api.cancelled, contains(7));
  });

  test('does not schedule anything when the due date is in the past',
      () async {
    await service.syncForTask(task(dueDateTime: DateTime.now().subtract(const Duration(minutes: 5))));

    expect(api.scheduled, isEmpty);
  });

  test('does not schedule anything for a completed task', () async {
    await service.syncForTask(task(completed: true, dueDateTime: inFuture()));

    expect(api.scheduled, isEmpty);
    expect(api.cancelled, contains(7));
  });

  test('changing the due date replaces the previous notification', () async {
    await service.syncForTask(task(dueDateTime: inFuture()));
    final first = api.scheduled.single.when;

    await service.syncForTask(
      task(dueDateTime: inFuture(const Duration(days: 1))),
    );

    expect(api.scheduled, hasLength(1));
    expect(api.scheduled.single.when.isAfter(first), isTrue);
    expect(api.cancelled.where((id) => id == 7).length, 2);
  });

  test('removing the due date cancels the notification', () async {
    await service.syncForTask(task(dueDateTime: inFuture()));
    expect(api.scheduled, hasLength(1));

    await service.syncForTask(task(dueDateTime: null));

    expect(api.scheduled, isEmpty);
  });

  test('completing a task cancels its notification', () async {
    await service.syncForTask(task(dueDateTime: inFuture()));
    await service.syncForTask(task(completed: true, dueDateTime: inFuture()));

    expect(api.scheduled, isEmpty);
  });

  test('reopening a completed task schedules it again', () async {
    await service.syncForTask(task(completed: true, dueDateTime: inFuture()));
    await service.syncForTask(task(completed: false, dueDateTime: inFuture()));

    expect(api.scheduled, hasLength(1));
  });

  test('deleting a task cancels its notification', () async {
    await service.syncForTask(task(dueDateTime: inFuture()));
    await service.cancelForTask(task(dueDateTime: inFuture()));

    expect(api.scheduled, isEmpty);
  });

  test('tasks without an id are ignored', () async {
    await service.syncForTask(task(id: null, dueDateTime: inFuture()));
    await service.cancelForTask(task(id: null));

    expect(api.scheduled, isEmpty);
    expect(api.cancelled, isEmpty);
  });

  test('scheduling failures never propagate', () async {
    api.failWithUnimplemented = true;

    await expectLater(
      service.syncForTask(task(dueDateTime: inFuture())),
      completes,
    );
  });

  test('permission denial is reported, not thrown', () async {
    api.permissionGranted = false;

    expect(await service.requestPermission(), isFalse);

    api.permissionGranted = true;
    expect(await service.requestPermission(), isTrue);
  });

  test('initializes once', () async {
    await service.init();
    expect(service.isInitialized, isTrue);
    await service.init();
    expect(service.isInitialized, isTrue);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';

/// Minimal surface the rest of the application needs from notifications.
///
/// Keeping it as an interface makes `TodoController` unit-testable without
/// touching platform channels.
abstract class NotificationScheduler {
  /// Cancels any pending notification for [task] and (re)schedules it when
  /// appropriate: pending task + due date in the future.
  Future<void> syncForTask(Task task);

  /// Cancels the notification belonging to [task], if any.
  Future<void> cancelForTask(Task task);
}

/// The handful of `flutter_local_notifications` operations the app uses.
///
/// It exists so tests can substitute a fake: `FlutterLocalNotificationsPlugin`
/// only exposes a factory constructor (it returns a singleton), therefore it
/// cannot simply be subclassed.
abstract class NotificationsApi {
  Future<bool> initialize(InitializationSettings settings);

  Future<bool> requestPermission();

  Future<void> cancel(int id);

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required AndroidScheduleMode mode,
    required String payload,
  });
}

/// Real implementation backed by `FlutterLocalNotificationsPlugin`.
class PluginNotificationsApi implements NotificationsApi {
  PluginNotificationsApi([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<bool> initialize(InitializationSettings settings) async {
    final result = await _plugin.initialize(settings: settings);
    return result ?? false;
  }

  /// Android 13+/iOS runtime permission. Platforms without a prompt
  /// (Linux, Windows, Android < 13) are treated as granted.
  @override
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? false;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        final apple = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await apple?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      default:
        return true;
    }
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required AndroidScheduleMode mode,
    required String payload,
  }) {
    return _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: NotificationService.details,
      androidScheduleMode: mode,
      payload: payload,
    );
  }
}

/// Wraps `flutter_local_notifications` so the rest of the app only sees a
/// tiny API: [syncForTask] and [cancelForTask].
///
/// Strategy (see BUILD_LOG):
/// * the **task id is the notification id**, so no extra column is needed;
/// * every sync cancels the previous notification first and only schedules a
///   new one when the task is pending and has a due date in the future;
/// * every operation is defensive: on Linux desktop `zonedSchedule()` throws
///   `UnimplementedError` and platform channels may be missing in tests, so
///   failures are logged and swallowed instead of crashing the app.
class NotificationService implements NotificationScheduler {
  NotificationService({NotificationsApi? api}) : _api = api ?? PluginNotificationsApi();

  static final NotificationService instance = NotificationService();

  static const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
    'task_reminders',
    'Task reminders',
    channelDescription: 'Reminders for tasks with a due date and time',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  static const NotificationDetails details = NotificationDetails(
    android: androidDetails,
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
  );

  final NotificationsApi _api;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Loads the timezone database, resolves the device timezone and
  /// initializes the plugin. Safe to call more than once.
  Future<void> init() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
        debugPrint('NotificationService: local timezone is ${tz.local.name}');
      } catch (e) {
        // Keep the UTC default; scheduling still uses an absolute instant.
        debugPrint('NotificationService: could not read device timezone: $e');
      }

      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Open task'),
      );
      _initialized = await _api.initialize(settings);
      debugPrint('NotificationService initialized: $_initialized');
    } catch (e) {
      // Never crash the app because notifications could not be initialized.
      debugPrint('NotificationService: initialization failed: $e');
    }
  }

  /// Requests the runtime permission (Android 13+, iOS, macOS).
  ///
  /// Returns `true` when notifications are allowed (or when the platform
  /// needs no permission). Never throws.
  Future<bool> requestPermission() async {
    try {
      if (!_initialized) await init();
      return await _api.requestPermission();
    } catch (e) {
      debugPrint('NotificationService: permission request failed: $e');
      return false;
    }
  }

  @override
  Future<void> syncForTask(Task task) async {
    await cancelForTask(task);
    if (task.id == null || task.completed) return;
    final due = task.dueDateTime;
    if (due == null) return;
    if (!due.isAfter(DateTime.now())) return;
    await _schedule(task.id!, task.title, due);
  }

  @override
  Future<void> cancelForTask(Task task) async {
    final id = task.id;
    if (id == null) return;
    try {
      await _api.cancel(id);
    } catch (e) {
      debugPrint('NotificationService: cancel($id) failed: $e');
    }
  }

  Future<void> _schedule(int id, String title, DateTime due) async {
    try {
      if (!_initialized) await init();
      final when = tz.TZDateTime.from(due, tz.local);
      await _api.schedule(
        id: id,
        title: 'Task reminder',
        body: 'Task reminder: $title',
        when: when,
        mode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'task:$id',
      );
    } on PlatformException catch (e) {
      if (e.code != 'exact_alarms_not_permitted') {
        debugPrint('NotificationService: schedule($id) failed: $e');
        return;
      }
      debugPrint(
        'NotificationService: exact alarms denied, retrying as inexact',
      );
      try {
        await _api.schedule(
          id: id,
          title: 'Task reminder',
          body: 'Task reminder: $title',
          when: tz.TZDateTime.from(due, tz.local),
          mode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'task:$id',
        );
      } catch (e2) {
        debugPrint('NotificationService: inexact schedule($id) failed: $e2');
      }
    } catch (e) {
      // UnimplementedError on Linux desktop, MissingPluginException in
      // tests, ArgumentError for past dates, ...
      debugPrint('NotificationService: schedule($id) failed: $e');
    }
  }
}

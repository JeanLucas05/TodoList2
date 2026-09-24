# Mobile To-Do App (Flutter)

A small mobile to-do application built with Flutter, following the requirements
in [`SPEC.md`](SPEC.md). Development history lives in [`BUILD_LOG.md`](BUILD_LOG.md).

**Features**

- SQLite persistence for tasks and categories (survives restarts)
- Three screens: task list, task editor/detail, category management
- Create / edit / complete / reopen / delete tasks
- Categories: create, rename, delete (its tasks become *uncategorized*)
- Filtering by status (All / Pending / Completed) and by category
- Optional due date **and** time
- Scheduled **local** notifications for future due dates (no push server)
- Notification permission requested safely, failures never crash the app

## Architecture

```
lib/
├── main.dart                     # bootstrap: sqlite factory, notifications, controller
├── app.dart                      # MaterialApp, theme, routes
├── models/                       # Task, Category (immutable + toMap/fromMap)
├── data/                         # AppDatabase (schema) + Task/Category repositories (SQL)
├── services/notification_service.dart
├── state/todo_controller.dart     # single ChangeNotifier: data + filters + operations
├── screens/                      # task_list, task_editor, category_management
└── utils/date_format.dart
```

- **Architecture**: repository pattern for persistence, one `ChangeNotifier`
  (`TodoController`) as the application state layer, screens only talk to the
  controller.
- **State management**: `provider`. Mutations return `Future<String?>`
  (`null` = success) so the UI can show a `SnackBar` with the error.
- **Navigation**: `Navigator.pushNamed`. Only the **task id** is passed to the
  editor, which reloads the task from the controller.
- **SQLite**: `sqflite` on Android, `sqflite_common_ffi` on desktop (identical
  API and schema code).
- **Notifications**: `flutter_local_notifications`. The **task id is the
  notification id**; every change cancels the previous notification first and
  re-schedules only when the task is pending with a future due date.

## Getting started

Requires [Flutter](https://docs.flutter.dev/get-started/install) 3.35+ (Dart 3.9+).

```bash
flutter pub get
flutter analyze
flutter test
```

### Android

Requires a **JDK 17** and the Android SDK (`compileSdk`/`targetSdk` 36,
`minSdk` 24). With the command-line tools only — no Android Studio needed:

```bash
sudo apt install -y openjdk-17-jdk

mkdir -p ~/android-sdk/cmdline-tools && cd ~/android-sdk/cmdline-tools
wget https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
unzip commandlinetools-linux-15859902_latest.zip && mv cmdline-tools latest

export ANDROID_HOME="$HOME/android-sdk"
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
```

Then build:

```bash
flutter build apk --debug     # 138 MB, for development
flutter build apk --release    # 50 MB, installable on a device
flutter run                    # with a device/emulator attached
```

> If the build reports `No Android SDK found. Try setting the ANDROID_HOME
> environment variable`, `ANDROID_HOME` is probably not the problem: Flutter
> actually requires the SDK directory to contain `platform-tools/` **or**
> `licenses/`. That usually means `sdkmanager` never ran — check `java -version`
> first (see BUILD_LOG Entry #10).

Android setup already applied (see BUILD_LOG Entry #7, verified in Entry #10):

- `coreLibraryDesugaring` + `desugar_jdk_libs` and Java 17 in
  `android/app/build.gradle.kts`
- `RECEIVE_BOOT_COMPLETED` / `SCHEDULE_EXACT_ALARM` permissions and the
  `ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver`
  receivers in `AndroidManifest.xml`
- Confirmed present in the merged manifest and in `aapt2 dump badging` of the
  built APK, together with `POST_NOTIFICATIONS` and `VIBRATE`

### Linux desktop

Used during development to run the app without an Android SDK:

```bash
flutter build linux --debug
./build/linux/x64/debug/bundle/todoapp
```

> Linux desktop **cannot schedule notifications** (the plugin has no scheduler
> API there); the code catches `UnimplementedError` and logs it. Everything
> else — persistence, screens, filters, categories — works.

If `flutter test` or the Linux binary fails with
`Unable to open a database` / `libsqlite3.so` errors on a machine that only has
the runtime library, either install `libsqlite3-dev` or expose the symlink:

```bash
mkdir -p /tmp/libs
ln -sf /lib/x86_64-linux-gnu/libsqlite3.so.0 /tmp/libs/libsqlite3.so
export LD_LIBRARY_PATH=/tmp/libs:$LD_LIBRARY_PATH
```

## Tests

```bash
flutter test
```

46 tests across four files:

| File | Covers |
| --- | --- |
| `test/app_database_test.dart` | SQLite schema, persistence across reopen, category delete → uncategorized |
| `test/todo_controller_test.dart` | CRUD + validation, filters, notification contract |
| `test/notification_service_test.dart` | schedule/cancel gating, error handling, permissions |
| `test/widget_test.dart` | end-to-end UI flows on a real in-memory database |

## Database schema

```sql
CREATE TABLE categories (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  name  TEXT    NOT NULL,
  color INTEGER
);

CREATE TABLE tasks (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  title       TEXT    NOT NULL,
  description TEXT,
  completed   INTEGER NOT NULL DEFAULT 0,   -- 0 | 1
  dueDateTime INTEGER,                      -- epoch millis, NULL = no due date
  createdAt   INTEGER NOT NULL,             -- epoch millis
  categoryId  INTEGER,
  FOREIGN KEY (categoryId) REFERENCES categories(id) ON DELETE SET NULL
);
```

The database file is created in the platform's application support directory
(e.g. `~/.local/share/br.edu.ifpe.todoapp/todoapp.db` on Linux).

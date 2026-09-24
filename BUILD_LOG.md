# BUILD_LOG — Mobile To-Do App (Flutter)

Development history of the project. Entries are appended as work progresses; older entries are not rewritten.

---

## Entry #1 — Project initialization

### Prompt / Request

> "leia os .md da raiz do projeto, meu ambiente atual e no WSL ok?" / "comece a implementar"

Read `SPEC.md` and `PROMPT.md` from the repository root and start implementing the specification.

### Decision Summary

- Environment: WSL2 (Ubuntu 24.04.4 LTS, kernel 6.6.87.2-microsoft-standard-WSL2). Flutter had to be installed first (it was not present); the user installed Flutter 3.35.5 (stable, Dart 3.9.2) manually.
- Project created with `flutter create --project-name todoapp --org br.edu.ifpe --platforms=android,linux`. Android is the target platform per `PROMPT.md`; the Linux desktop target was also enabled so the app can be built and executed locally in WSL (no Android SDK/emulator available in this environment yet).
- Initial dependency selection (see Entry #2 for justification):
  - `provider` — state management;
  - `sqflite` + `sqflite_common_ffi` — SQLite persistence on Android and on desktop during development;
  - `path_provider` — cross-platform database file location;
  - `flutter_local_notifications` + `timezone` + `flutter_timezone` — scheduled local notifications with correct local timezone.
- Architecture direction: repository pattern (data layer) + a single `ChangeNotifier` controller (state layer) + screens (UI). Rationale is documented in a later entry.

### Actions Performed

- Installed Flutter 3.35.5 in WSL (user executed the download/extract steps).
- Ran `flutter --disable-analytics`.
- Created the Flutter project skeleton in the repository root (42 files: `lib/`, `android/`, `linux/`, `test/`, `pubspec.yaml`, analysis options).
- Added dependencies via `flutter pub add provider sqflite sqflite_common_ffi path_provider flutter_local_notifications timezone flutter_timezone`.
- Inspected the installed package sources (`flutter_local_notifications` 20.1.0, `sqflite_common` 2.5.6) to confirm the exact APIs available (`zonedSchedule`, `requestNotificationsPermission`, `requestExactAlarmsPermission`, `AndroidScheduleMode`, `databaseFactory` setter).

### Result

Project skeleton created and dependencies resolved successfully (`flutter pub add` reported `Got dependencies`).

### Problems / Errors

- Flutter, Dart and the Android toolchain were not installed in the environment (`which flutter` empty, `java: command not found`, no Android SDK).
- No Android SDK/emulator exists in WSL, so APK builds/device runs are not possible yet (still pending; see later entries).

### Fixes Attempted

- Flutter SDK installed by the user following the commands provided by the agent; `flutter doctor` now reports Flutter and the Linux toolchain as available. Android toolchain remains missing.

### Current Status

Completed

---

## Entry #2 — Documentation and configuration decisions (before code)

### Prompt / Request

> "comece a implementar"

Start implementing the specification (the SPEC requires `BUILD_LOG.md` to be created before any code and kept updated).

### Decision Summary

Key technical choices for the implementation:

- **SQLite**: `sqflite` on Android/iOS and `sqflite_common_ffi` (same API, same schema code) on desktop. Chosen because `PROMPT.md` explicitly lists `sqflite`/`drift` as candidates; `sqflite` was picked over `drift` to keep the project small and dependency-light (no code generation, raw SQL kept simple and explicit for an educational app).
- **State management**: `provider` with one `ChangeNotifier` (`TodoController`) holding tasks, categories and the active filters. A single controller avoids wiring two notifiers that both need each other's data (the task list must show category names); considered Riverpod/Bloc but rejected as unnecessary complexity for an app of this size (SPEC §15).
- **Architecture**: repository pattern — `TaskRepository`/`CategoryRepository` own all SQL; `TodoController` orchestrates repository calls and notification scheduling; screens only talk to the controller.
- **Navigation**: `Navigator.push` with routes; when opening an existing task only the task **id** is passed and the editor reloads the task from the controller (SPEC §7 option "pass only the task ID" — avoids stale/duplicated state).
- **Category deletion strategy**: tasks of a deleted category become **uncategorized** (`categoryId = NULL`), done inside the same transaction as the delete (SPEC §6, Screen 3).
- **Filtering**: loaded once from SQLite and filtered **in memory** in `TodoController.filteredTasks`. The dataset of an educational app is small; in-memory filtering keeps a single source of truth and makes the UI refresh trivial (SPEC §12).
- **Notifications**: `flutter_local_notifications` with `zonedSchedule` using a `TZDateTime` built from the device timezone obtained via `flutter_timezone`. The **task id is used as the notification id** (no extra column needed). On every change the old notification is cancelled first and then re-scheduled if the task is pending with a future due date. Android 13+ permission requested with `requestNotificationsPermission()`; exact alarms are attempted first (`AndroidScheduleMode.exactAllowWhileIdle`) with automatic fallback to `inexactAllowWhileIdle` if the exact-alarm permission is denied.
- **Date storage**: `dueDateTime` and `createdAt` stored as epoch milliseconds (`INTEGER`) in SQLite; nullable `dueDateTime` means "no due date".
- **Category extra field**: optional `color` (`INTEGER`, nullable) — allowed by SPEC §4.

### Actions Performed

- Created `BUILD_LOG.md` (this file) before writing any application code.
- Documented the decisions above.

### Result

Decisions recorded; ready to implement.

### Problems / Errors

None.

### Fixes Attempted

None needed.

### Current Status

Completed

---

## Entry #3 — Models and SQLite data layer

### Prompt / Request

> "comece a implementar" / "continue"

Implement the data model and the persistence layer described in SPEC §§3–5.

### Decision Summary

- Created `lib/models/task.dart` and `lib/models/category.dart` as plain immutable Dart classes with `copyWith`, `toMap` and `fromMap`. Timestamps are converted to/from epoch milliseconds at this boundary so no other layer deals with integers.
- `copyWith` uses a private `_keep` sentinel instead of nullable parameters, otherwise it would be impossible to clear `dueDateTime`/`categoryId` when the user removes them (SPEC §9 "task due date removed").
- Created `lib/data/app_database.dart` as the single owner of the connection and the schema (version 1, `onCreate`, `PRAGMA foreign_keys = ON` in `onConfigure`). Repositories only contain SQL; screens never see a `Database`.
- Schema: `categories(id, name, color)` and `tasks(id, title, description, completed, dueDateTime, createdAt, categoryId)` plus `idx_tasks_category`. `categoryId` has `FOREIGN KEY ... ON DELETE SET NULL` as a safety net; the repository still performs an explicit `UPDATE tasks SET categoryId = NULL` inside the same transaction as the `DELETE`, so the behavior is correct even if the pragma is not applied.
- `AppDatabase` accepts an optional `path` so tests can use `:memory:` or a temp file. The default location is `path_provider.getApplicationSupportDirectory()`, falling back to `getDatabasesPath()` when `path_provider` is unavailable.
- Repositories **throw** `DatabaseException` instead of returning error strings, so `insert` can return the generated row id (needed to pair a task with its notification id). `TodoController` converts exceptions into user-facing messages.

### Actions Performed

- Created `lib/models/task.dart`, `lib/models/category.dart`.
- Created `lib/data/app_database.dart`, `lib/data/task_repository.dart`, `lib/data/category_repository.dart`.

### Result

Data layer complete; schema verified later against the file produced by a real run (see Entry #8).

### Problems / Errors

- `Sqflite.firstIntValue(...)` does not exist in the installed `sqflite` version (it is a top-level `firstIntValue` in `sqflite_common/utils`, not a member of the `Sqflite` class).

### Fixes Attempted

- Replaced it with a plain `rows.first['c'] as int? ?? 0` in `CategoryRepository.countTasks`.

### Current Status

Completed

---

## Entry #4 — Notification service and its testable seam

### Prompt / Request

> "continue"

Implement SPEC §§9–11 (due dates, scheduled local notifications, permission handling).

### Decision Summary

- Added a small `NotificationScheduler` interface (`syncForTask` / `cancelForTask`) so `TodoController` can be unit-tested without platform channels, and a slightly larger `NotificationsApi` interface (`initialize` / `requestPermission` / `cancel` / `schedule`) so `NotificationService` itself is testable.
- Reason for `NotificationsApi`: `FlutterLocalNotificationsPlugin` exposes only a **factory constructor returning a singleton**, so it cannot be subclassed to inject a fake. `PluginNotificationsApi` is the real adapter, `_FakeApi` in the test is the fake.
- `syncForTask` is the single entry point and always: cancels the notification with the same id first, then schedules a new one **only if** the task has an id, is not completed, has a due date, and that due date is in the future. This one method covers all six behaviours required by SPEC §10.
- Notification id = task id (already decided in Entry #2); payload is `task:<id>` so the app can open the task from a notification later.
- Scheduling tries `AndroidScheduleMode.exactAllowWhileIdle`; if the platform throws `PlatformException('exact_alarms_not_permitted')` it retries once with `inexactAllowWhileIdle`. Everything else (`UnimplementedError` on Linux desktop, `MissingPluginException` in tests, past dates) is caught and logged with `debugPrint` — the app never crashes because of a notification.
- Timezone: `tzdata.initializeTimeZones()` + `FlutterTimezone.getLocalTimezone()` → `tz.setLocalLocation(...)`. If the platform channel fails, the UTC default is kept; the notification still fires at the correct **instant** because `TZDateTime.from(dateTime, location)` preserves the epoch instant.
- Permission: `requestPermission()` is called once, after the first frame (`addPostFrameCallback` in `main.dart`), so startup is never blocked by a system dialog. It returns `false` instead of throwing when denied; Linux/Windows are treated as granted (no prompt exists).

### Actions Performed

- Created `lib/services/notification_service.dart` (`NotificationScheduler`, `NotificationsApi`, `PluginNotificationsApi`, `NotificationService`).

### Result

Notification layer implemented and covered by `test/notification_service_test.dart` (14 tests).

### Problems / Errors

- `_plugin.initialize(...)` takes a **named** parameter `settings`, not a positional one (caught by `flutter analyze`).

### Fixes Attempted

- Changed to `_plugin.initialize(settings: settings)`.

### Current Status

Completed

---

## Entry #5 — State management and the three screens

### Prompt / Request

> "continue"

Implement SPEC §§6, 7, 12, 13, 16 (three screens, navigation, filtering, error handling, UI refresh).

### Decision Summary

- `TodoController` (single `ChangeNotifier`, provided with `provider`) owns `_tasks`, `_categories`, `statusFilter`, `categoryFilterId`, `isLoading` and `loadError`.
- Every mutation returns `Future<String?>`: `null` = success, non-null = a user-facing message that the screen shows in a `SnackBar`. This keeps error handling (SPEC §13) in one place instead of try/catch blocks scattered over the UI.
- `load()` is used at startup and shows the loading flag; `_reloadAfterMutation()` re-reads both tables without toggling `isLoading`, so the list does not flash empty after every change.
- Filtering is in-memory in `filteredTasks` (already decided in Entry #2); a deleted category also clears `categoryFilterId` so the dropdown can never point at a missing item (which would trip Flutter's `DropdownButton` assertion).
- Navigation: `MaterialApp.routes` for the task list and category management, `onGenerateRoute` for the editor because it needs a route argument. The editor receives **only the task id** (`TaskEditorScreen.idOf(settings.arguments)`) and looks the task up through `TodoController.taskById`, so it always shows persisted state and cannot hold a stale copy.
- Editor details: `Form` + validator for the required title, separate date and time pickers plus a "Clear" chip for the due date, `SwitchListTile` for `completed`, a confirmation dialog before discarding changes and before deleting.
- Category screen: inline create field, rename dialog, delete confirmation whose message explains that tasks become uncategorized.
- `lib/utils/date_format.dart` formats dates without adding the `intl` package.

### Actions Performed

- Created `lib/state/todo_controller.dart`.
- Created `lib/screens/task_list_screen.dart` (Screen 1), `lib/screens/task_editor_screen.dart` (Screen 2), `lib/screens/category_management_screen.dart` (Screen 3).
- Created `lib/utils/date_format.dart`, `lib/app.dart`, rewrote `lib/main.dart`.

### Result

Three screens wired to persistent data; `flutter analyze` clean after the fixes below.

### Problems / Errors

First `flutter analyze` reported 19 issues. The relevant ones:

1. `Undefined name 'Platform'` in `main.dart` — `Platform` lives in `dart:io`, not in `package:flutter/foundation.dart`.
2. `The name 'Category' is defined in ... flutter/foundation.dart and ... models/category.dart` — `package:flutter/foundation.dart` exports a `Category` **annotation** that collides with the model.
3. `_reloadAfterMutation is already defined` — a second copy was left behind while editing `load()`.
4. `The getter 'message' isn't defined for the type 'DatabaseException'` — `_message` is private in `sqflite_common`; only `toString()` is public.
5. `'value' is deprecated ... Use initialValue instead` — `DropdownButtonFormField.value` was deprecated in Flutter 3.33.
6. Unused imports (`path_provider` in `app_database.dart`, `sqflite` in `category_repository.dart`).

### Fixes Attempted

1. Added `import 'dart:io';`.
2. Narrowed the import to `import 'package:flutter/foundation.dart' show ChangeNotifier;`.
3. Removed the duplicated method.
4. Used `'$context: $error'` (i.e. `DatabaseException.toString()`).
5. Switched to `initialValue:` — safe here because the field only changes through its own `onChanged`.
6. Made `path_provider` actually used (`getApplicationSupportDirectory()`) and dropped the unused `sqflite` import.

### Current Status

Completed

---

## Entry #6 — Automated tests

### Prompt / Request

> "Antes de considerar qualquer funcionalidade 'pronta', **compile e execute o projeto** (ou rode os testes automatizados relevantes) para validar." (`PROMPT.md`)

Replace the stock counter test with tests that actually validate the specification.

### Decision Summary

Four test files, 46 tests in total:

- `test/app_database_test.dart` (5) — real SQLite through `sqflite_common_ffi` on a temp file: reopen/persistence, full field round-trip, update/delete, and **"deleting a category makes its tasks uncategorized"**.
- `test/todo_controller_test.dart` (17) — CRUD + validation, category CRUD, both filters and their combination, and the notification contract from SPEC §10 via a `_RecordingScheduler`.
- `test/notification_service_test.dart` (14) — the real gating logic against a `_FakeApi`: schedules only for pending+future, cancel-first, replaces on date change, cancels on clear/complete/delete, never throws, permission denial returns `false`.
- `test/widget_test.dart` (10) — full UI flows with a real in-memory database: empty state, create, validation error keeps the editor open, open-for-edit, toggle from the list, status filters, navigation to category management, rename, delete-with-uncategorized-tasks, delete task from the editor.

`sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi` are set in each test file's `main()`; every test injects a fake `NotificationScheduler`/`NotificationsApi` so no platform channel is touched.

### Actions Performed

- Replaced `test/widget_test.dart` (stock counter test) and added the three files above.

### Result

`flutter test` → **46/46 passing**, `flutter analyze` → **No issues found**.

### Problems / Errors

1. One real test failure: `creating a task without a due date does not schedule` expected `notifications.synced` to be empty, but `TodoController.createTask` always calls `syncForTask` — deciding whether to schedule is the service's job, not the controller's.
2. A **false alarm**: `flutter test` appeared to hang for ~10 minutes. The tests were not hanging — `grep`/`tail` at the end of a pipe do not flush when `timeout` kills the pipeline, so no output appeared.

### Fixes Attempted

1. Rewrote the assertion to `expect(notifications.synced, hasLength(1))` and renamed the test to *"always re-syncs through the service, which decides to schedule"*. The controller contract and the service contract are now asserted separately instead of being mixed.
2. Re-ran the suite redirecting to a file instead of piping through `grep`; all 46 tests finished in ~9 seconds.

### Current Status

Completed

---

## Entry #7 — Android platform configuration

### Prompt / Request

> "Notificações locais: um pacote de notificações locais agendadas (ex.: flutter_local_notifications)" (`PROMPT.md`) / SPEC §10, §11

Configure the Android host project so scheduled notifications actually work.

### Decision Summary

- `android/app/build.gradle.kts`: enabled `isCoreLibraryDesugaringEnabled` and `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` (mandatory for `flutter_local_notifications` 10+), moved Java/Kotlin target from 11 to **17** as required by the plugin README, and set `multiDexEnabled = true`.
- Project AGP is 8.9.1 (≥ the recommended 8.6.0) and Gradle 8.12, so no version bump was needed.
- `AndroidManifest.xml`: added `RECEIVE_BOOT_COMPLETED` and `SCHEDULE_EXACT_ALARM` permissions plus the `ScheduledNotificationReceiver` and `ScheduledNotificationBootReceiver` receivers (with the boot/MY_PACKAGE_REPLACED/QUICKBOOT intent filters). `POST_NOTIFICATIONS` and `VIBRATE` are already declared by the plugin itself since v16.

### Actions Performed

- Modified `android/app/build.gradle.kts` and `android/app/src/main/AndroidManifest.xml`.

### Result

Configuration written and reviewed against the plugin's README. **Not compiled** — see Blocked below.

### Problems / Errors

- There is no Android SDK and no JDK/Java in this WSL environment (`flutter doctor` reports the Android toolchain missing), so `flutter build apk` cannot run here. The configuration could not be validated by a real build.

### Fixes Attempted

- None yet. Installing the Android SDK + a JDK was proposed but not performed (it needs `sudo` and several GB of downloads; the user has not confirmed).

### Current Status

Blocked (needs Android SDK to build/verify). Code and manifest follow the official plugin documentation.

---

## Entry #8 — Desktop build and real execution

### Prompt / Request

> "Whenever possible: build the project; run it; inspect compiler output; test important user flows; fix errors found." (SPEC §19)

### Decision Summary

Linux desktop is used as the executable validation target because no Android SDK exists in this environment. Notifications cannot be *scheduled* there (the plugin documents "Scheduled/pending notifications is currently not supported" for Linux), but everything else — SQLite, screens, navigation, filters, CRUD — runs for real.

### Actions Performed

- `flutter build linux --debug` → `✓ Built build/linux/x64/debug/bundle/todoapp`.
- Executed the binary under WSLg (`DISPLAY=:0`).
- Inspected the generated database with Python's `sqlite3` module.

### Result

- Application started successfully and stayed alive for the full run window.
- Startup log:

  ```
  NotificationService: local timezone is America/Sao_Paulo
  NotificationService initialized: true
  Notification permission granted: true
  ```

  (proves the timezone resolution path works on a real device-like environment)
- Database created at `~/.local/share/br.edu.ifpe.todoapp/todoapp.db` with the expected schema: `tasks`, `categories`, `idx_tasks_category`, `FOREIGN KEY (categoryId) REFERENCES categories(id) ON DELETE SET NULL`.
- Only non-fatal noise: `libEGL` / `MESA-LOADER` / cursor-theme warnings from the headless WSL GPU stack.

### Problems / Errors

1. `libsqlite3.so` (the unversioned development symlink) is not installed in this environment — only `libsqlite3.so.0`. `package:sqlite3` calls `DynamicLibrary.open('libsqlite3.so')`, so both `flutter test` and the desktop binary would fail to open the database.
2. `sudo` requires a password, so `apt install libsqlite3-dev` is not available to the agent.

### Fixes Attempted

1. Created a symlink outside the repository and exposed it through `LD_LIBRARY_PATH`:

   ```bash
   mkdir -p /tmp/opencode/libs
   ln -sf /lib/x86_64-linux-gnu/libsqlite3.so.0 /tmp/opencode/libs/libsqlite3.so
   export LD_LIBRARY_PATH=/tmp/opencode/libs:$LD_LIBRARY_PATH
   ```

   With this, `flutter test` and the built binary both load SQLite successfully. On a normal machine (or inside the Android app, which links SQLite itself) this step is unnecessary.

### Current Status

Completed for the desktop target; the Android target is still blocked by Entry #7.

---

## Entry #9 — Git repository (initialized, commits deferred)

### Prompt / Request

> "Se for solicitado a criar commits Git, mantenha um histórico significativo: cada commit deve representar um passo de implementação, correção ou decisão relevante" (`PROMPT.md`)

### Decision Summary

`git init` was still missing (the project directory was not a repository). The repository was created and the working tree prepared, but the user explicitly decided **not to commit yet** when asked whether the agent should configure `git user.name`/`user.email`. Commits are therefore deferred to a later session/decision.

> *Correction:* an earlier draft of this entry claimed the commits had already been written. That was wrong — no commit exists yet (`git log` reports "does not have any have any commits yet"). The entry is kept honest rather than left claiming work that was not done.

### Actions Performed

- `git init` (branch `master`, no commits yet).
- Staged the scaffolding in the index: `.gitignore`, `.metadata`, `BUILD_LOG.md`, `PROMPT.md`, `SPEC.md`, `analysis_options.yaml`, `android/`, `linux/`, `pubspec.lock`, `pubspec.yaml`.
- `.gitignore` already excludes `build/`, `.dart_tool/`, `.idea/`, `*.iml` and `.flutter-plugins-dependencies`.
- Not staged yet: `lib/`, `test/`, `README.md`.

### Result

Repository initialized and partially staged; no commit created (pending user decision). Suggested incremental split for whoever commits: scaffolding + log entries #1–#2 → models/data → notifications → controller/screens → tests → Android config → README.

### Problems / Errors

- No Git identity configured in this environment (`Author identity unknown`); the agent did not run `git config` because the user chose not to.

### Fixes Attempted

- Not applicable — the block was a user decision, not a defect.

### Current Status

Partially completed (repository ready, commits pending)

---

## Entry #10 — Android SDK setup and the first real APK builds

### Prompt / Request

> "me mande o android sdk install pra eu baixar" → install commands were handed over and run by the user in a second terminal; then: "acabou de baixar o sdk na vdd" (the SDK finished downloading).

Resolves **Entry #7** (`Blocked`).

### Decision Summary

- **CLI SDK instead of Android Studio.** The user asked whether installing Android Studio on Windows would have been easier. It would not have been *for this project*: Flutter, the test suite and the Linux build all live in this WSL environment, the project path is `~/teste/todoapp`, and the agent drives everything from the shell. A Windows Android Studio would be a second, disconnected toolchain (different `PATH`, `JAVA_HOME`, SDK, and a `\\wsl$` project path that makes Gradle I/O very slow). The command-line SDK is ~350 MB, needs no GUI, and `flutter doctor` treats both identically. Android Studio remains a perfectly valid alternative if the user later wants the emulator and a visual device manager.
- Installed toolchain: **OpenJDK 17** (`17.0.20.1`), **cmdline-tools 22.0**, `platform-tools`, `platforms;android-36`, `platforms;android-35`, `build-tools;36.0.0`, `build-tools;35.0.0` (plus `ndk;27.0.12077973` and `cmake`, pulled in by `sdkmanager` but **not required** by this project — no plugin ships native/CMake code).
- `flutter config --android-sdk` already points at `/home/alunoifpe/android-sdk`, so `ANDROID_HOME` is only needed by `sdkmanager` itself.

### Actions Performed

1. Diagnosed the first failed build (see Problems below) before asking for anything to be re-run.
2. User installed JDK + SDK packages in a second terminal.
3. `flutter doctor` → `[✓] Android toolchain - develop for Android devices (Android SDK version 36.0.0)`.
4. `flutter build apk --debug` → exit 0, `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (138 MB), Gradle task `assembleDebug` in 7.3 s.
5. `flutter build apk --release` → exit 0, `✓ Built build/app/outputs/flutter-apk/app-release.apk` (50.7 MB / 49 MB on disk), `assembleRelease` in 135 s, icons tree-shaken (1 645 184 → 3 312 bytes).
6. Validated the **merged** manifest (`build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml`) and the APK itself with `aapt2 dump badging`.

### Result

**`aapt2 dump badging` (app-release/debug APK):**

```
package: name='br.edu.ifpe.todoapp' versionCode='1' versionName='1.0.0'
         compileSdkVersion='36' targetSdkVersion='36'
uses-permission: android.permission.INTERNET
uses-permission: android.permission.RECEIVE_BOOT_COMPLETED
uses-permission: android.permission.SCHEDULE_EXACT_ALARM
uses-permission: android.permission.VIBRATE
uses-permission: android.permission.POST_NOTIFICATIONS
```

**Merged manifest (SPEC §10/§11 acceptance):**

- `<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36" />` — matches the values Flutter 3.35.5 generated.
- `com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver` (`exported="false"`).
- `com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver` with `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `QUICKBOOT_POWERON` and `com.htc.intent.action.QUICKBOOT_POWERON`.
- All four manifest edits from Entry #7 survived manifest merging with the plugin's own declarations — nothing was dropped or duplicated.
- `MainActivity` is `exported="true"` with the `MAIN`/`LAUNCHER` intent filter.

Entry #7 is therefore no longer *Blocked*: the Android configuration is **compiled and verified**.

### Problems / Errors

**The first `flutter build apk --debug` failed with:**

```
[!] No Android SDK found. Try setting the ANDROID_HOME environment variable.
```

That message was misleading — `ANDROID_HOME` *was* set (and `flutter config` had `android-sdk: /home/alunoifpe/android-sdk`). The real chain was:

1. `sudo apt install openjdk-17-jdk` never actually ran, so there was **no JVM at all** (`/usr/lib/jvm` did not exist, `java: command not found`).
2. Without Java the `sdkmanager` wrapper dies immediately (`die "ERROR: JAVA_HOME is set to an invalid directory"`), so `--licenses` and the package install produced **nothing**.
3. `~/android-sdk` therefore contained only `cmdline-tools/` — no `platform-tools/`, no `licenses/`.
4. Flutter does not check that the directory exists; it checks `AndroidSdk.validSdkDirectory()` (`flutter_tools/.../android_sdk.dart:166`):

   ```dart
   static bool validSdkDirectory(String dir) =>
       sdkDirectoryHasLicenses(dir) || sdkDirectoryHasPlatformTools(dir);
   ```

   Both were absent → `locateAndroidSdk()` returned `null` → `exitWithNoSdkMessage()` printed the misleading "set ANDROID_HOME" hint.

Two secondary observations while diagnosing:

- `~/.bashrc` received the Android export block **twice** (the heredoc was run twice). Harmless, but worth knowing when reading history.
- The installed `cmdline-tools 22.0` needs **Java 17**, not 21: the `sdkmanager` classpath's maximum class-file version is `61` (Java 17). The only `major 65` (Java 21) classes found are `META-INF/versions/21/…` entries of a multi-release BouncyCastle jar and `screenshot2` — neither is on `sdkmanager`'s classpath. So JDK 17 satisfies both the tool and AGP 8.9.1.

### Fixes Attempted

- Provided the exact command sequence (`apt install openjdk-17-jdk` → `sdkmanager --licenses` → `sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"` → `flutter doctor`). The agent cannot run `sudo` (password required), so the user executed it in a second terminal.
- No code, Gradle or manifest change was needed — the project configuration from Entry #7 was already correct.

### Current Status

**Completed.** Android toolchain green, debug and release APKs built, notification permissions/receivers verified in the merged manifest. The only remaining `flutter doctor` complaints are `Chrome` (web target, unused) and `Android Studio (not installed)` (not required for CLI builds).

---

## Entry #11 — First run on a real Android device

### Prompt / Request

> "conectei o cabo, como mando o apk pro celular"

### Decision Summary

WSL2 cannot see USB devices directly (`/dev/bus/usb` does not exist), so `adb` inside WSL reports an empty device list and `usbipd` is not installed on Windows. Instead of setting up `usbipd-win`, the **existing Windows `adb.exe`** was used — Windows already has Android Studio and its own SDK at `C:\Users\aluno.lab03\AppData\Local\Android\Sdk`. WSL can execute Windows binaries, so the install ran from here with no extra setup.

### Actions Performed

1. Copied `build/app/outputs/flutter-apk/app-release.apk` (49 MB) to `C:\Users\aluno.lab03\Downloads\todoapp-release.apk`.
2. Detected the device: **Infinix HOT 60 Pro** (`X6885`, serial `148027057Y017887`), `ADB Interface` present → USB debugging already enabled and authorized.
3. `adb.exe install -r C:\Users\aluno.lab03\Downloads\todoapp-release.apk` → **`Success`**.
4. `adb shell am start -n br.edu.ifpe.todoapp/.MainActivity` → launched.
5. Collected `logcat` evidence of the real run.

### Result

```
package:br.edu.ifpe.todoapp                         # installed
NotificationService: local timezone is America/Recife
NotificationService initialized: true
[IMPORTANT ... android_context_vk_impeller.cc] Using the Impeller rendering backend (Vulkan).
```

- The permission dialog (`GrantPermissionsActivity`) came up automatically on launch; `POST_NOTIFICATIONS` was `granted=false` at the time of capture, i.e. the runtime prompt was on screen awaiting the user's tap — exactly the SPEC §11 behaviour.
- Resolving the timezone from the device (`America/Recife`) instead of the desktop's `America/Sao_Paulo` confirms `flutter_timezone` works against the platform channel on hardware.

### Problems / Errors

- `adb.exe: failed to stat /mnt/c/Users/.../Downloads/todoapp-release.apk: No such file or directory` — `adb.exe` is a Windows binary and cannot parse WSL paths. Fixed by passing the Windows path (`C:\Users\...`) instead of the `/mnt/c/...` path.
- `flutter devices` / `adb` under WSL stay empty without `usbipd-win`; documented here so the same dead end is not walked again.

### Fixes Attempted

- Windows-style path for the APK (above). No `usbipd`, no driver install, no re-download required.

### Current Status

**Completed.** The release APK installs, launches and initialises notifications on physical hardware. Remaining: user must accept the notification permission prompt; commits are still deferred.

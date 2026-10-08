import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collections.dart';
import '../models/task.dart';
import '../models/holiday_entry.dart';
import 'attachment_service.dart';
import 'holidays/holiday_service.dart';
import 'notifications/models/notification_preferences.dart';
import 'preferences/app_preferences.dart';
import 'preferences/app_preferences_service.dart';
import 'notifications/platform/local_notification_adapter.dart';
import 'notifications/platform/notification_adapter.dart';
import 'notifications/services/notification_service.dart';
import 'notifications/services/preferences_service.dart';
import 'repository.dart';

final authStateProvider = StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());

final repoProvider = Provider<Repo>((ref) {
  // Rebuilds when the signed-in user changes so queries follow the new uid.
  final user = ref.watch(authStateProvider).value;
  return Repo(uid: user?.uid);
});

final attachmentServiceProvider = Provider<AttachmentService>((ref) {
  final user = ref.watch(authStateProvider).value;
  return AttachmentService(uid: user?.uid);
});

final notificationAdapterProvider =
    Provider<NotificationAdapter>((ref) => LocalNotificationAdapter());

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(adapter: ref.watch(notificationAdapterProvider)),
);

final notificationPreferencesServiceProvider = Provider<NotificationPreferencesService>((ref) {
  final user = ref.watch(authStateProvider).value;
  return NotificationPreferencesService(uid: user?.uid ?? '_anon');
});

/// The user's notification preferences, streamed from their user document.
///
/// The repository schedules against these, so a change here takes effect on the
/// next task write without the UI having to pass them around.
final notificationPreferencesProvider = StreamProvider<NotificationPreferences>((ref) {
  final service = ref.watch(notificationPreferencesServiceProvider);
  final repo = ref.watch(repoProvider);
  return service.watch().map((prefs) {
    repo.notificationPreferences = prefs;
    return prefs;
  });
});

/// Tasks the user has moved but whose Firestore write has not come back yet.
/// Merged over the server list so a drag feels instant (optimistic UI).
class TaskOverrides extends Notifier<Map<String, Task>> {
  @override
  Map<String, Task> build() => const {};

  void put(Task task) => state = {...state, task.id: task};

  void clear(String id) => state = {...state}..remove(id);
}

final taskOverridesProvider =
    NotifierProvider<TaskOverrides, Map<String, Task>>(TaskOverrides.new);

final _serverTasksProvider = StreamProvider<List<Task>>((ref) => ref.watch(repoProvider).watchTasks());

/// True while Firestore is serving from its local cache, which is how the app
/// knows it is offline. Edits still work; they queue and replay on reconnect.
final isOfflineProvider = StreamProvider<bool>((ref) {
  final repo = ref.watch(repoProvider);
  return repo.tasks.snapshots().map((s) => s.metadata.isFromCache);
});

final tasksProvider = Provider<AsyncValue<List<Task>>>((ref) {
  final overrides = ref.watch(taskOverridesProvider);
  return ref.watch(_serverTasksProvider).whenData((tasks) {
    if (overrides.isEmpty) return tasks;
    final merged = <Task>[for (final t in tasks) overrides[t.id] ?? t];
    merged.sort((a, b) => a.position.compareTo(b.position));
    return merged;
  });
});

final boardsProvider = StreamProvider<List<Board>>((ref) => ref.watch(repoProvider).watchBoards());
final listsProvider = StreamProvider<List<TaskList>>((ref) => ref.watch(repoProvider).watchLists());
final categoriesProvider =
    StreamProvider<List<Category>>((ref) => ref.watch(repoProvider).watchCategories());
final notesProvider = StreamProvider<List<Note>>((ref) => ref.watch(repoProvider).watchNotes());
final remindersProvider =
    StreamProvider<List<Reminder>>((ref) => ref.watch(repoProvider).watchReminders());
final holidaysProvider = StreamProvider<List<Holiday>>((ref) => ref.watch(repoProvider).watchHolidays());
final focusSessionsProvider =
    StreamProvider<List<FocusSession>>((ref) => ref.watch(repoProvider).watchFocusSessions());

/// Which bottom-nav tab is showing. Held in a provider so a screen can send
/// the user elsewhere — the week strip on Today opens the Calendar tab.
class HomeTabController extends Notifier<int> {
  @override
  int build() => 0;

  void go(int index) => state = index;
}

final homeTabProvider = NotifierProvider<HomeTabController, int>(HomeTabController.new);

/// The day the Calendar should open on, set when another screen sends the user
/// there for a particular date.
class CalendarFocusController extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void focus(DateTime day) => state = day;
  void clear() => state = null;
}

final calendarFocusProvider =
    NotifierProvider<CalendarFocusController, DateTime?>(CalendarFocusController.new);

final appPreferencesServiceProvider = Provider<AppPreferencesService>((ref) {
  final user = ref.watch(authStateProvider).value;
  return AppPreferencesService(uid: user?.uid ?? '_anon');
});

/// The user's app preferences, streamed from their user document so a change
/// made on one device shows up on the others.
///
/// Readers use [appPreferencesProvider] instead of this, so they get the
/// defaults while the first snapshot is still in flight rather than having to
/// handle a loading state each time.
final appPreferencesStreamProvider = StreamProvider<AppPreferences>(
    (ref) => ref.watch(appPreferencesServiceProvider).watch());

final appPreferencesProvider = Provider<AppPreferences>((ref) =>
    ref.watch(appPreferencesStreamProvider).value ?? const AppPreferences());

/// Saves a changed preference. Everything that reads [appPreferencesProvider]
/// updates from the resulting snapshot, so there is one source of truth.
final savePreferencesProvider = Provider<Future<void> Function(AppPreferences)>(
    (ref) => ref.watch(appPreferencesServiceProvider).save);

final themeModeProvider = Provider<ThemeMode>((ref) => ref.watch(appPreferencesProvider).themeMode);

/// Holiday metadata for the calendar, built from the user's country and
/// category choices plus any holidays they added themselves.
final holidayServiceProvider = Provider<HolidayService>((ref) => HolidayService(
      preferences: ref.watch(appPreferencesProvider),
      userHolidays: ref.watch(holidaysProvider).value ?? const <Holiday>[],
    ));

/// Holidays on a single day, for the small number of callers that need one day
/// rather than a range.
List<HolidayEntry> holidaysOn(HolidayService service, DateTime day) => service.entriesOn(day);

/// Category lookup by id, used by cards to draw the coloured chip.
final categoryByIdProvider = Provider<Map<String, Category>>((ref) {
  final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
  return {for (final c in cats) c.id: c};
});

/// Tasks for one list, in order.
List<Task> tasksForList(List<Task> all, String listId) =>
    all.where((t) => t.listId == listId && t.parentTaskId == null).toList()
      ..sort((a, b) => a.position.compareTo(b.position));

/// Tasks with a start time on a given day.
List<Task> tasksForDay(List<Task> all, DateTime day) => all
    .where((t) =>
        t.startDateTime != null &&
        t.startDateTime!.year == day.year &&
        t.startDateTime!.month == day.month &&
        t.startDateTime!.day == day.day)
    .toList()
  ..sort((a, b) => a.startDateTime!.compareTo(b.startDateTime!));

/// [d] as a local calendar date with the time of day dropped.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The calendar day [days] away from [d]. Calendar arithmetic, not +24 hours,
/// so it stays correct across a daylight-saving change.
DateTime shiftDay(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

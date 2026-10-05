import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collections.dart';
import '../models/task.dart';
import 'attachment_service.dart';
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

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;

  void set(ThemeMode mode) => state = mode;

  void toggle() => state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

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

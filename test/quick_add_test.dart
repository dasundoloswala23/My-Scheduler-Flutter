import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/app/theme.dart';
import 'package:myschedule/core/notifications/models/notification_preferences.dart';
import 'package:myschedule/core/preferences/app_preferences.dart';
import 'package:myschedule/core/providers.dart';
import 'package:myschedule/core/repository.dart';
import 'package:myschedule/features/quick_add/quick_add_logic.dart';
import 'package:myschedule/features/quick_add/quick_add_sheet.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/task.dart';

/// A repository that records what it is asked to save and touches no Firebase.
class FakeRepo extends Fake implements Repo {
  final List<Task> created = [];

  /// When set, `createTask` waits on it, so a test can tap Save again while the
  /// first save is still in flight, which is how a real double tap behaves.
  Completer<void>? hold;

  @override
  Future<String> createTask(Task task) async {
    created.add(task);
    await hold?.future;
    return 'task-${created.length}';
  }

  @override
  Future<String> addNote(Note note) async => 'note-1';
}

Future<FakeRepo> _openQuickAdd(
  WidgetTester tester, {
  Size size = const Size(360, 640),
  double keyboard = 0,
  Brightness brightness = Brightness.light,
  DateTime? date,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);

  final repo = FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repoProvider.overrideWithValue(repo),
        appPreferencesProvider.overrideWithValue(const AppPreferences()),
        notificationPreferencesProvider
            .overrideWith((ref) => Stream.value(const NotificationPreferences())),
        categoriesProvider.overrideWith((ref) => Stream.value(const <Category>[])),
        boardsProvider.overrideWith((ref) => Stream.value(const <Board>[])),
        listsProvider.overrideWith((ref) => Stream.value(const <TaskList>[])),
        tasksProvider.overrideWithValue(const AsyncData(<Task>[])),
      ],
      child: MaterialApp(
        theme: buildAppTheme(brightness: brightness),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showQuickAddSheet(context, date: date),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

Finder get _save => find.widgetWithText(FilledButton, 'Save Task');

void main() {
  group('duration', () {
    test('reads naturally', () {
      expect(describeDuration(30), '30 minutes');
      expect(describeDuration(45), '45 minutes');
      expect(describeDuration(60), '1 hour');
      expect(describeDuration(90), '90 minutes');
      expect(describeDuration(120), '2 hours');
      expect(describeDuration(135), '2 hours 15 min');
    });

    test('moves the end by exactly the duration, so 6:00 PM + 90 min is 7:30 PM', () {
      final start = DateTime(2026, 10, 8, 18, 0);
      expect(endFor(start, 90), DateTime(2026, 10, 8, 19, 30));
      expect(endFor(start, 60), DateTime(2026, 10, 8, 19, 0));
      expect(endFor(null, 60), isNull);
    });
  });

  group('date and time', () {
    test('a date and a time make a start', () {
      expect(
        combineDateAndTime(DateTime(2026, 10, 8), const TimeOfDay(hour: 18, minute: 0)),
        DateTime(2026, 10, 8, 18, 0),
      );
    });

    test('no time means no start', () {
      expect(combineDateAndTime(DateTime(2026, 10, 8), null), isNull);
    });

    test('the picker opens on the next full hour', () {
      expect(defaultTimeAfter(DateTime(2026, 10, 8, 14, 20)), const TimeOfDay(hour: 15, minute: 0));
      expect(defaultTimeAfter(DateTime(2026, 10, 8, 23, 59)), const TimeOfDay(hour: 0, minute: 0));
    });

    test('a time makes a timed task', () {
      final s = scheduleFor(
        date: DateTime(2026, 10, 8),
        dateChosen: true,
        time: const TimeOfDay(hour: 18, minute: 0),
      );
      expect(s.start, DateTime(2026, 10, 8, 18, 0));
      expect(s.isAllDay, isFalse);
    });

    test('a chosen date with no time is an all-day task, not a lost date', () {
      final s = scheduleFor(date: DateTime(2026, 10, 8), dateChosen: true, time: null);
      expect(s.start, DateTime(2026, 10, 8));
      expect(s.isAllDay, isTrue);
    });

    test('a date that only defaulted to today stays unscheduled', () {
      final s = scheduleFor(date: DateTime(2026, 10, 8), dateChosen: false, time: null);
      expect(s.isScheduled, isFalse);
      expect(s.isAllDay, isFalse);
    });
  });

  group('validation', () {
    final now = DateTime(2026, 10, 8, 12, 0);
    QuickAddValidation check({
      String title = 'Write report',
      String url = '',
      DateTime? start,
      int duration = 60,
      int reminders = 0,
    }) =>
        validateQuickAdd(
          title: title,
          url: url,
          start: start,
          durationMinutes: duration,
          reminderCount: reminders,
          now: now,
        );

    test('an empty or blank title cannot be saved', () {
      expect(check(title: '').problem, QuickAddProblem.emptyTitle);
      expect(check(title: '   ').problem, QuickAddProblem.emptyTitle);
      expect(check().canSave, isTrue);
    });

    test('reminders need a time to count from', () {
      expect(check(reminders: 1).problem, QuickAddProblem.remindersNeedTime);
      expect(check(reminders: 1, start: DateTime(2026, 10, 8, 18)).canSave, isTrue);
    });

    test('a zero duration is refused', () {
      expect(check(start: DateTime(2026, 10, 8, 18), duration: 0).problem,
          QuickAddProblem.invalidDuration);
    });

    test('a bad link is refused and a good one is not', () {
      expect(check(url: 'not a link').problem, QuickAddProblem.invalidUrl);
      expect(check(url: 'example.com').canSave, isTrue);
    });

    test('a start in the past is allowed but flagged', () {
      final v = check(start: DateTime(2026, 10, 8, 9));
      expect(v.canSave, isTrue);
      expect(v.startsInPast, isTrue);
      expect(check(start: DateTime(2026, 10, 8, 18)).startsInPast, isFalse);
    });
  });

  group('links', () {
    test('a missing scheme is added', () {
      expect(normalizeUrl('example.com/page'), 'https://example.com/page');
      expect(normalizeUrl('  http://example.com '), 'http://example.com');
    });

    test('non-links are refused', () {
      expect(normalizeUrl(''), isNull);
      expect(normalizeUrl('hello'), isNull);
      expect(normalizeUrl('javascript:alert(1)'), isNull);
      expect(normalizeUrl('ftp://example.com'), isNull);
    });

    test('the link goes on its own line of the description', () {
      expect(
        composeDescription(notes: 'Remember the intro', url: 'https://a.com'),
        'Remember the intro\n\nhttps://a.com',
      );
      expect(composeDescription(notes: '', url: 'https://a.com'), 'https://a.com');
      expect(composeDescription(notes: 'Just notes', url: null), 'Just notes');
    });
  });

  group('submit guard', () {
    test('a second call while the first is running is skipped', () async {
      final guard = SubmitGuard();
      final gate = Completer<void>();
      var runs = 0;

      final first = guard.run(() async {
        runs++;
        await gate.future;
      });
      // Straight away, with no frame in between: this is the double tap.
      final second = guard.run(() async => runs++);

      expect(await second, isFalse);
      gate.complete();
      expect(await first, isTrue);
      expect(runs, 1);
    });

    test('it can run again once the first has finished', () async {
      final guard = SubmitGuard();
      var runs = 0;
      await guard.run(() async => runs++);
      await guard.run(() async => runs++);
      expect(runs, 2);
    });

    test('it is released even when the action throws', () async {
      final guard = SubmitGuard();
      await expectLater(guard.run(() async => throw StateError('boom')), throwsStateError);
      expect(guard.isRunning, isFalse);
    });
  });

  group('the Quick Add sheet', () {
    testWidgets('Save is on screen, above the keyboard, on a small phone', (tester) async {
      // A 360x640 phone with a 300 logical-pixel keyboard: the case where the
      // old sheet pushed Save out of view.
      await _openQuickAdd(tester, size: const Size(360, 640), keyboard: 300);
      await tester.enterText(find.byType(TextField).first, 'Kitty Meow Video');
      await tester.pump();

      final rect = tester.getRect(_save);
      expect(rect.bottom, lessThanOrEqualTo(640 - 300),
          reason: 'Save must sit above the keyboard');
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull, reason: 'no layout overflow');
    });

    testWidgets('Save is not clipped and works on a very small screen', (tester) async {
      final repo = await _openQuickAdd(tester, size: const Size(320, 480), keyboard: 260);
      await tester.enterText(find.byType(TextField).first, 'Small screen task');
      await tester.pump();

      expect(tester.getRect(_save).bottom, lessThanOrEqualTo(480 - 260));
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(repo.created.length, 1);
      expect(repo.created.single.title, 'Small screen task');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Save is disabled with a reason until there is a title', (tester) async {
      await _openQuickAdd(tester);

      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
      expect(find.text('Add a title to save.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Something');
      await tester.pump();

      expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
      expect(find.text('Add a title to save.'), findsNothing);
    });

    testWidgets('tapping Save twice quickly creates exactly one task', (tester) async {
      final repo = await _openQuickAdd(tester);
      repo.hold = Completer<void>();

      await tester.enterText(find.byType(TextField).first, 'Only once');
      await tester.pump();

      // Two taps with no frame between them, while the first save is in flight.
      await tester.tap(_save);
      await tester.tap(_save);
      repo.hold!.complete();
      await tester.pumpAndSettle();

      expect(repo.created.length, 1);
    });

    testWidgets('choosing a time shows a native picker and the chosen time', (tester) async {
      await _openQuickAdd(tester);
      expect(find.text('No time'), findsOneWidget);

      await tester.tap(find.text('Time'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('No time'), findsNothing);
      // The picker opens on the next full hour, so the row now shows a time.
      expect(find.textContaining(RegExp(r'\d{1,2}:00')), findsWidgets);
    });

    testWidgets('a task with a time is saved as one scheduled task with its duration',
        (tester) async {
      final repo = await _openQuickAdd(tester, date: DateTime(2030, 10, 8));

      await tester.enterText(find.byType(TextField).first, 'Upload video');
      await tester.tap(find.text('Time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(repo.created.length, 1);
      final task = repo.created.single;
      expect(task.startDateTime, isNotNull);
      expect(task.startDateTime!.year, 2030);
      expect(task.startDateTime!.month, 10);
      expect(task.startDateTime!.day, 8);
      expect(task.isAllDay, isFalse);
      // The default duration is an hour.
      expect(task.endDateTime!.difference(task.startDateTime!), const Duration(hours: 1));
    });

    testWidgets('a date with no time is saved all-day instead of losing the date',
        (tester) async {
      final repo = await _openQuickAdd(tester, date: DateTime(2030, 10, 8));

      await tester.enterText(find.byType(TextField).first, 'Pay rent');
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      final task = repo.created.single;
      expect(task.isAllDay, isTrue);
      expect(task.startDateTime, DateTime(2030, 10, 8));
    });

    testWidgets('renders in dark mode without a layout error', (tester) async {
      await _openQuickAdd(tester, brightness: Brightness.dark, keyboard: 280);
      await tester.enterText(find.byType(TextField).first, 'Dark');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_save, findsOneWidget);
    });
  });
}

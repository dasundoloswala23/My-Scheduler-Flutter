import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:myschedule/core/providers.dart';
import 'package:myschedule/features/today/today_page.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/task.dart';

Task _task(String id, String title, DateTime start) => Task(
      id: id,
      title: title,
      startDateTime: start,
      endDateTime: start.add(const Duration(hours: 1)),
    );

Future<void> _mount(WidgetTester tester, List<Task> tasks) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 1400);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      tasksProvider.overrideWithValue(AsyncData(tasks)),
      holidaysProvider.overrideWith((ref) => Stream.value(const <Holiday>[])),
      categoriesProvider.overrideWith((ref) => Stream.value(const <Category>[])),
    ],
    child: const MaterialApp(home: Scaffold(body: TodayPage())),
  ));
  await tester.pump();
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  group('day arithmetic', () {
    test('shiftDay is calendar arithmetic and keeps midnight', () {
      expect(shiftDay(DateTime(2026, 3, 28), 1), DateTime(2026, 3, 29));
      expect(shiftDay(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
      expect(shiftDay(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
    });

    test('dateOnly drops the time of day', () {
      expect(dateOnly(DateTime(2026, 10, 8, 23, 59)), DateTime(2026, 10, 8));
    });

    test('a local late-evening task belongs to its own local day, not the next UTC day', () {
      final late = DateTime(2026, 10, 8, 23, 30);
      expect(tasksForDay([_task('a', 'Late', late)], DateTime(2026, 10, 8)), hasLength(1));
      expect(tasksForDay([_task('a', 'Late', late)], DateTime(2026, 10, 9)), isEmpty);
    });
  });

  group('Today page date selection', () {
    testWidgets('opens on today and shows only today\'s tasks', (tester) async {
      await _mount(tester, [
        _task('1', 'Today task', today.add(const Duration(hours: 10))),
        _task('2', 'Tomorrow task', shiftDay(today, 1).add(const Duration(hours: 10))),
        _task('3', 'Yesterday task', shiftDay(today, -1).add(const Duration(hours: 10))),
      ]);

      expect(find.text('Today task'), findsWidgets);
      expect(find.text('Yesterday task'), findsNothing);
    });

    testWidgets('next day shows that day\'s tasks, previous day and Today go back',
        (tester) async {
      await _mount(tester, [
        _task('1', 'Today task', today.add(const Duration(hours: 10))),
        _task('2', 'Tomorrow task', shiftDay(today, 1).add(const Duration(hours: 10))),
        _task('3', 'Yesterday task', shiftDay(today, -1).add(const Duration(hours: 10))),
      ]);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pump();
      expect(find.text('Tomorrow task'), findsWidgets);
      expect(find.text('Today task'), findsNothing);

      await tester.tap(find.byTooltip('Previous day'));
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pump();
      expect(find.text('Yesterday task'), findsWidgets);
      // Tomorrow's task is now "coming up", not on this day's timeline.
      expect(find.text('Coming up'), findsOneWidget);

      await tester.tap(find.text('Today'));
      await tester.pump();
      expect(find.text('Today task'), findsWidgets);
    });

    testWidgets('a day with nothing says so', (tester) async {
      await _mount(tester, const []);
      await tester.tap(find.byTooltip('Next day'));
      await tester.pump();
      expect(find.textContaining('Nothing scheduled on'), findsOneWidget);
    });

    testWidgets('picking a date from the calendar jumps to it', (tester) async {
      final target = shiftDay(today, 1);
      await _mount(tester, [_task('2', 'Tomorrow task', target.add(const Duration(hours: 9)))]);

      await tester.tap(find.text(DateFormat('EEEE, MMMM d').format(today)));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await tester.tap(find.text('${target.day}').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Tomorrow task'), findsWidgets);
    });
  });
}

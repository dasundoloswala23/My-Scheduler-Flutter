import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/preferences/app_preferences.dart';
import 'package:myschedule/core/providers.dart';
import 'package:myschedule/features/calendar/calendar_page.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/task.dart';

/// The real Calendar page, drawing real [Task]s: the views, the 9 AM opening
/// position and where an event sits in the time grid.
Future<void> _mount(WidgetTester tester, List<Task> tasks, {AppPreferences? prefs, double height = 1400}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(900, height);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      tasksProvider.overrideWithValue(AsyncData(tasks)),
      appPreferencesProvider.overrideWithValue(prefs ?? const AppPreferences()),
      savePreferencesProvider.overrideWithValue((_) async {}),
      holidaysProvider.overrideWith((ref) => Stream.value(const <Holiday>[])),
      categoriesProvider.overrideWith((ref) => Stream.value(const <Category>[])),
      boardsProvider.overrideWith((ref) => Stream.value(const <Board>[])),
      listsProvider.overrideWith((ref) => Stream.value(const <TaskList>[])),
    ],
    child: const MaterialApp(home: Scaffold(body: CalendarPage())),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final event = Task(
    id: 'e1',
    title: 'Design review',
    startDateTime: today.add(const Duration(hours: 10, minutes: 30)),
    endDateTime: today.add(const Duration(hours: 11, minutes: 30)),
  );

  testWidgets('opens scrolled to about 9 AM, with earlier hours above', (tester) async {
    await _mount(tester, [event], height: 700);
    // The time grid is the vertical scrollable with the most to scroll.
    final positions = [
      for (final e in find.byType(Scrollable).evaluate())
        if ((e.widget as Scrollable).axisDirection == AxisDirection.down)
          tester.state<ScrollableState>(find.byWidget(e.widget)).position,
    ]..sort((a, b) => b.maxScrollExtent.compareTo(a.maxScrollExtent));
    final hourHeight = const AppPreferences().calendarDensity.hourHeight;

    expect(positions.first.pixels, closeTo(9 * hourHeight, 1));
    expect(positions.first.pixels, greaterThan(0), reason: 'earlier hours stay above');
  });

  testWidgets('every view shows the real task and switches without error', (tester) async {
    await _mount(tester, [event]);
    for (final label in ['Day', '3 days', 'Week', 'Month']) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
      expect(find.textContaining('Design review'), findsWidgets, reason: label);
    }
  });
}


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/app/theme.dart';
import 'package:myschedule/core/flows/flow_providers.dart';
import 'package:myschedule/core/preferences/app_preferences.dart';
import 'package:myschedule/core/providers.dart';
import 'package:myschedule/features/boards/task_card.dart';
import 'package:myschedule/models/collections.dart';
import 'package:myschedule/models/task.dart';

Task _task({List<Subtask> subtasks = const [], String description = ''}) => Task(
      id: 't1',
      title: 'Create Kitty Meow Video',
      description: description,
      categoryId: 'c1',
      subtasks: subtasks,
    );

List<Subtask> _subtasks(int count, {int done = 0}) => [
      for (var i = 0; i < count; i++)
        Subtask(id: 's$i', title: 'Step ${i + 1}', done: i < done, position: i.toDouble()),
    ];

/// Pumps a card with the given preferences, with no Firebase anywhere: every
/// provider the card reads is overridden with plain data.
Future<void> _pumpCard(
  WidgetTester tester,
  Task task, {
  AppPreferences preferences = const AppPreferences(),
  Brightness brightness = Brightness.light,
  Map<String, ({int done, int total})> flowBadges = const {},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(preferences),
        taskFlowBadgeProvider.overrideWithValue(flowBadges),
        categoryByIdProvider.overrideWithValue(const {
          'c1': Category(id: 'c1', name: 'YouTube', colorValue: 0xFF6C5CE7),
        }),
      ],
      child: MaterialApp(
        theme: buildAppTheme(brightness: brightness),
        home: Scaffold(
          body: SizedBox(width: 320, child: TaskCard(task: task, showMenu: false)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a card shows its title and category chip', (tester) async {
    await _pumpCard(tester, _task());
    expect(find.text('Create Kitty Meow Video'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
  });

  group('Project Flow badge', () {
    testWidgets('a task in a flow shows a small Flow 4/9 badge', (tester) async {
      await _pumpCard(tester, _task(), flowBadges: {'t1': (done: 4, total: 9)});
      expect(find.text('Flow 4/9'), findsOneWidget);
    });

    testWidgets('a repeating task with nothing else still shows its repeat chip',
        (tester) async {
      await _pumpCard(tester, _task().copyWith(recurrence: Recurrence.weekly));
      expect(find.text('Weekly'), findsOneWidget);
    });

    testWidgets('a task not in a flow shows no badge', (tester) async {
      await _pumpCard(tester, _task());
      expect(find.textContaining('Flow'), findsNothing);
    });

    testWidgets('a badge belongs to its own task only', (tester) async {
      await _pumpCard(tester, _task(), flowBadges: {'other': (done: 1, total: 2)});
      expect(find.textContaining('Flow'), findsNothing);
    });
  });

  group('subtasks on the card front', () {
    testWidgets('are shown by default', (tester) async {
      await _pumpCard(tester, _task(subtasks: _subtasks(3, done: 1)));

      expect(find.text('Step 1'), findsOneWidget);
      expect(find.text('Step 2'), findsOneWidget);
      expect(find.text('Step 3'), findsOneWidget);
      // The progress counter sits above the checklist.
      expect(find.text('1/3'), findsOneWidget);
    });

    testWidgets('are hidden when the preference is off, leaving the count',
        (tester) async {
      await _pumpCard(
        tester,
        _task(subtasks: _subtasks(3, done: 1)),
        preferences: const AppPreferences(showSubtasksOnCards: false),
      );

      expect(find.text('Step 1'), findsNothing);
      expect(find.text('Step 3'), findsNothing);
      // The meta row still reports progress, so nothing is lost by turning
      // the checklist off.
      expect(find.text('1/3 subtasks'), findsOneWidget);
    });

    testWidgets('collapse behind "+N more" past the preview count',
        (tester) async {
      await _pumpCard(tester, _task(subtasks: _subtasks(8, done: 3)));

      // Default preview count is 4.
      expect(find.text('Step 4'), findsOneWidget);
      expect(find.text('Step 5'), findsNothing);
      expect(find.text('+ 4 more'), findsOneWidget);
      expect(find.text('3/8'), findsOneWidget);
    });

    testWidgets('expand and collapse again when "+N more" is tapped',
        (tester) async {
      await _pumpCard(tester, _task(subtasks: _subtasks(8)));

      await tester.tap(find.text('+ 4 more'));
      await tester.pump();

      expect(find.text('Step 8'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);

      await tester.tap(find.text('Show less'));
      await tester.pump();

      expect(find.text('Step 8'), findsNothing);
      expect(find.text('+ 4 more'), findsOneWidget);
    });

    testWidgets('a short checklist shows no expander at all', (tester) async {
      await _pumpCard(tester, _task(subtasks: _subtasks(2)));
      expect(find.textContaining('more'), findsNothing);
      expect(find.text('Show less'), findsNothing);
    });

    // Not covered: "ticking a subtask does not open the detail sheet".
    //
    // The tick writes through `repoProvider`, and `Repo` cannot be built
    // without a Firebase app, so the tap raises an asynchronous provider
    // error that escapes the test body. Faking that away would test nothing,
    // so this behaviour is listed as NOT TESTED in the QA report and needs a
    // manual check.
  });

  group('link preview', () {
    testWidgets('a URL in the description shows the domain', (tester) async {
      await _pumpCard(
        tester,
        _task(description: 'reference https://www.example.co.uk/page'),
      );
      expect(find.text('example.co.uk'), findsOneWidget);
    });

    testWidgets('a known host is named', (tester) async {
      await _pumpCard(
        tester,
        _task(description: 'https://youtu.be/abc123'),
      );
      expect(find.text('YouTube'), findsNWidgets(2)); // category chip + link
      expect(find.text('youtu.be'), findsOneWidget);
    });

    testWidgets('a description with no link shows no preview tile',
        (tester) async {
      await _pumpCard(tester, _task(description: 'just some notes'));
      expect(find.byIcon(Icons.link), findsNothing);
    });
  });

  group('theming', () {
    testWidgets('renders in dark mode without falling back to a light surface',
        (tester) async {
      await _pumpCard(
        tester,
        _task(subtasks: _subtasks(2)),
        brightness: Brightness.dark,
      );

      final card = tester.widget<Card>(find.byType(Card).first);
      final theme = Theme.of(tester.element(find.byType(TaskCard)));
      // The card takes the dark palette's surface, not Material's default.
      expect(card.color ?? theme.cardTheme.color, AppPalette.dark.surface);
    });
  });
}

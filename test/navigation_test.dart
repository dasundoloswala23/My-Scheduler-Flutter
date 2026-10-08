import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/app/theme.dart';
import 'package:myschedule/features/home/home_shell.dart';
import 'package:myschedule/features/home/lazy_indexed_stack.dart';

const _destinations = [
  (label: 'Today', icon: Icons.home_outlined, selected: Icons.home),
  (label: 'Boards', icon: Icons.view_week_outlined, selected: Icons.view_week),
  (label: 'Calendar', icon: Icons.calendar_today_outlined, selected: Icons.calendar_today),
  (label: 'Inbox', icon: Icons.inbox_outlined, selected: Icons.inbox),
  (label: 'More', icon: Icons.more_horiz, selected: Icons.more_horiz),
];

/// A tab with state of its own, standing in for the Board's scroll position or
/// the Calendar's chosen date. `builds` counts how many times it was created.
class _CounterTab extends StatefulWidget {
  const _CounterTab(this.name, this.onBuilt);
  final String name;
  final void Function(String) onBuilt;

  @override
  State<_CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<_CounterTab> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    widget.onBuilt(widget.name);
  }

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => taps++),
        child: Text('${widget.name}: $taps'),
      );
}

void main() {
  group('LazyIndexedStack', () {
    Future<List<String>> pump(WidgetTester tester, ValueNotifier<int> index) async {
      final built = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: index,
            builder: (context, i, _) => LazyIndexedStack(
              index: i,
              itemCount: 3,
              itemBuilder: (context, n) => _CounterTab('tab$n', built.add),
            ),
          ),
        ),
      );
      return built;
    }

    testWidgets('only the first tab is built at start', (tester) async {
      final built = await pump(tester, ValueNotifier(0));
      expect(built, ['tab0']);
    });

    testWidgets('a tab is built on its first visit, not before', (tester) async {
      final index = ValueNotifier(0);
      final built = await pump(tester, index);

      index.value = 2;
      await tester.pump();

      expect(built, ['tab0', 'tab2']);
      expect(built.contains('tab1'), isFalse, reason: 'tab1 was never opened');
    });

    testWidgets('a tab keeps its state when you leave and come back', (tester) async {
      final index = ValueNotifier(0);
      final built = await pump(tester, index);

      await tester.tap(find.text('tab0: 0'));
      await tester.pump();
      await tester.tap(find.text('tab0: 1'));
      await tester.pump();
      expect(find.text('tab0: 2'), findsOneWidget);

      index.value = 1;
      await tester.pump();
      index.value = 0;
      await tester.pump();

      // The same state object came back, not a fresh one showing zero.
      expect(find.text('tab0: 2'), findsOneWidget);
      expect(built.where((b) => b == 'tab0').length, 1,
          reason: 'it must not have been rebuilt from scratch');
    });

    testWidgets('only the selected tab is visible', (tester) async {
      final index = ValueNotifier(0);
      await pump(tester, index);
      index.value = 1;
      await tester.pump();

      expect(find.text('tab1: 0'), findsOneWidget);
      expect(find.text('tab0: 0', skipOffstage: true), findsNothing);
    });
  });

  group('ModernNavBar', () {
    Future<List<int>> pump(
      WidgetTester tester, {
      int selected = 0,
      Size size = const Size(360, 640),
      EdgeInsets padding = EdgeInsets.zero,
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = FakeViewPadding(bottom: padding.bottom);
      addTearDown(tester.view.reset);

      final taps = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: brightness),
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: ModernNavBar(
              selectedIndex: selected,
              onSelected: taps.add,
              destinations: _destinations,
            ),
          ),
        ),
      );
      return taps;
    }

    testWidgets('shows the five destinations in order', (tester) async {
      await pump(tester);
      for (final d in _destinations) {
        expect(find.text(d.label), findsOneWidget);
      }
      final xs = [for (final d in _destinations) tester.getCenter(find.text(d.label)).dx];
      expect(xs, [...xs]..sort(), reason: 'left to right in the stated order');
    });

    testWidgets('tapping a destination reports its index', (tester) async {
      final taps = await pump(tester);
      await tester.tap(find.text('Calendar'));
      await tester.tap(find.text('More'));
      expect(taps, [2, 4]);
    });

    testWidgets('the selected destination is announced as selected to screen readers',
        (tester) async {
      await pump(tester, selected: 1);
      final handle = tester.ensureSemantics();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Boards')),
        isSemantics(label: 'Boards', isButton: true, isSelected: true, hasTapAction: true),
      );
      // And an unselected one is a button that is not selected.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Today')),
        isSemantics(label: 'Today', isButton: true, isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('each destination is at least 48 logical pixels tall', (tester) async {
      await pump(tester);
      final size = tester.getSize(find.ancestor(
        of: find.text('Today'),
        matching: find.byType(AnimatedContainer),
      ));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('stays above the home indicator and does not touch the screen edge',
        (tester) async {
      await pump(tester, padding: const EdgeInsets.only(bottom: 34));
      final bar = tester.getRect(find.byType(ModernNavBar));
      // The item row has to end above the 34px home indicator.
      final lowest = tester.getRect(find.text('Today')).bottom;
      expect(lowest, lessThanOrEqualTo(640 - 34));
      expect(bar.bottom, lessThanOrEqualTo(640));
    });

    testWidgets('is compact, not an oversized bar', (tester) async {
      await pump(tester);
      expect(tester.getSize(find.byType(ModernNavBar)).height, lessThan(96));
    });

    testWidgets('renders in dark mode without a layout error', (tester) async {
      await pump(tester, brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
    });
  });
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/notifications/platform/local_notification_adapter.dart';
import '../../core/providers.dart';
import '../boards/boards_page.dart';
import '../calendar/calendar_page.dart';
import '../inbox/inbox_page.dart';
import '../more/more_page.dart';
import '../more/reminders_page.dart';
import '../quick_add/quick_add_sheet.dart';
import '../search/search_page.dart';
import '../today/today_page.dart';

/// The app frame: a bottom bar on phones (screenshots 1–20) and a sidebar on
/// desktop and web (screenshots 22–37).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  // The selected tab lives in a provider so other screens can navigate here,
  // such as the week strip on Today opening the Calendar.
  int get _index => ref.watch(homeTabProvider);
  void _setIndex(int i) => ref.read(homeTabProvider.notifier).go(i);

  static const _destinations = [
    (label: 'Today', icon: Icons.home_outlined, selected: Icons.home),
    (label: 'Boards', icon: Icons.view_week_outlined, selected: Icons.view_week),
    (label: 'Calendar', icon: Icons.calendar_today_outlined, selected: Icons.calendar_today),
    (label: 'Inbox', icon: Icons.inbox_outlined, selected: Icons.inbox),
    (label: 'More', icon: Icons.more_horiz, selected: Icons.more_horiz),
  ];

  @override
  void initState() {
    super.initState();
    // Seed the default board, lists and categories on first sign-in.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(repoProvider).ensureBootstrap();
      await LocalNotificationAdapter().initialise();
    });
  }

  Widget get _page => switch (_index) {
        0 => const TodayPage(),
        1 => const BoardsPage(),
        2 => const CalendarPage(),
        3 => const InboxPage(),
        _ => const MorePage(),
      };

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    final fab = FloatingActionButton(
      heroTag: 'quick-add',
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      onPressed: () => showQuickAddSheet(context),
      child: const Icon(Icons.add),
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(
              index: _index,
              onSelect: _setIndex,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: SafeArea(
                child: Column(
                  children: [
                    _TopBar(onQuickAdd: () => showQuickAddSheet(context)),
                    const OfflineBanner(),
                    Expanded(child: _page),
                  ],
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: fab,
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onQuickAdd: () => showQuickAddSheet(context), compact: true),
            const OfflineBanner(),
            Expanded(child: _page),
          ],
        ),
      ),
      floatingActionButton: fab,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _setIndex,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selected),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

/// Tells the user when the app is working from its local cache, so an edit
/// that has not reached the server yet is never a mystery.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider).value ?? false;
    if (!offline) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: AppColors.amber.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: AppColors.amber),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline. Your changes are saved here and will sync when you reconnect.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.amber),
            ),
          ),
        ],
      ),
    );
  }
}

void _openSearch(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage()));

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onQuickAdd, this.compact = false});

  final VoidCallback onQuickAdd;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 8, compact ? 8 : 20, 4),
      child: Row(
        children: [
          Expanded(
            child: compact
                ? const SizedBox.shrink()
                : InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openSearch(context),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(children: [
                        Icon(Icons.search, size: 18, color: AppColors.muted),
                        SizedBox(width: 10),
                        Text('Search tasks, boards, notes…',
                            style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
                      ]),
                    ),
                  ),
          ),
          if (!compact) ...[
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: onQuickAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Quick add'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ink,
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _openSearch(context),
            icon: const Icon(Icons.search),
            tooltip: 'Search',
          ),
          IconButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const RemindersPage())),
            icon: const Icon(Icons.notifications_none),
            tooltip: 'Reminders',
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final boards = ref.watch(boardsProvider).value ?? const [];

    return SizedBox(
      width: 260,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 17),
                  ),
                  const SizedBox(width: 10),
                  const Text('My scheduler',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.ink,
                    child: Text(
                      (user?.displayName ?? user?.email ?? 'U').substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  title: Text(user?.displayName ?? 'My workspace',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  subtitle: Text(user?.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _HomeShellState._destinations.length; i++)
              _SidebarItem(
                label: _HomeShellState._destinations[i].label,
                icon: _HomeShellState._destinations[i].icon,
                selected: i == index,
                onTap: () => onSelect(i),
              ),
            const Divider(height: 24),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('YOUR BOARDS',
                  style: TextStyle(fontSize: 9.5, letterSpacing: 1.1, color: AppColors.muted)),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final b in boards)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.circle, size: 9, color: Color(b.colorValue)),
                      title: Text(b.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      onTap: () => onSelect(1),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: selected ? AppColors.primary : AppColors.muted),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: selected ? AppColors.primary : null,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

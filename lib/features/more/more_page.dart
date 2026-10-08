import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import '../flows/flows_page.dart';
import 'categories_page.dart';
import 'focus_page.dart';
import 'holidays_page.dart';
import 'matrix_page.dart';
import 'notes_page.dart';
import 'reminders_page.dart';
import 'settings_page.dart';
import 'statistics_page.dart';

/// Screenshot 5: the More hub.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final notes = ref.watch(notesProvider).value ?? const <Note>[];
    final reminders = ref.watch(remindersProvider).value ?? const <Reminder>[];
    final holidays = ref.watch(holidaysProvider).value ?? const <Holiday>[];
    final themeMode = ref.watch(themeModeProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
      children: [
        Text('MY SCHEDULER',
            style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: context.palette.textSecondary)),
        Text('More', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary,
              child: Text(
                _initials(user?.displayName ?? user?.email ?? 'U'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(user?.displayName ?? 'My account',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(user?.email ?? '', style: TextStyle(fontSize: 12.5, color: context.palette.textSecondary)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, const SettingsPage()),
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.4,
          children: [
            _Tile(
              icon: Icons.rocket_launch_outlined,
              color: AppColors.primary,
              title: 'Project Flows',
              subtitle: 'Plan in stages',
              onTap: () => _open(context, const ProjectFlowsPage()),
            ),
            _Tile(
              icon: Icons.label_outline,
              color: AppColors.primary,
              title: 'Categories',
              subtitle: '${categories.length} areas',
              onTap: () => _open(context, const CategoriesPage()),
            ),
            _Tile(
              icon: Icons.sticky_note_2_outlined,
              color: AppColors.blue,
              title: 'Notes',
              subtitle: '${notes.length} notes',
              onTap: () => _open(context, const NotesPage()),
            ),
            _Tile(
              icon: Icons.track_changes,
              color: context.palette.warning,
              title: 'Focus',
              subtitle: '25 min timer',
              onTap: () => _open(context, const FocusPage()),
            ),
            _Tile(
              icon: Icons.grid_view,
              color: context.palette.success,
              title: 'Matrix',
              subtitle: 'Prioritise',
              onTap: () => _open(context, const MatrixPage()),
            ),
            _Tile(
              icon: Icons.bar_chart,
              color: AppColors.primary,
              title: 'Productivity',
              subtitle: 'Weekly insights',
              onTap: () => _open(context, const StatisticsPage()),
            ),
            _Tile(
              icon: Icons.notifications_none,
              color: context.palette.danger,
              title: 'Reminders',
              subtitle: '${reminders.where((r) => !r.done).length} upcoming',
              onTap: () => _open(context, const RemindersPage()),
            ),
            _Tile(
              icon: Icons.celebration_outlined,
              color: context.palette.success,
              title: 'Holidays',
              subtitle: holidays.isEmpty ? 'Add yours' : '${holidays.length} this year',
              onTap: () => _open(context, const HolidaysPage()),
            ),
            _Tile(
              icon: Icons.widgets_outlined,
              color: AppColors.blue,
              title: 'Settings',
              subtitle: 'Preferences',
              onTap: () => _open(context, const SettingsPage()),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.wb_sunny_outlined),
                title: const Text('Appearance', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: Text(
                  switch (themeMode) {
                    ThemeMode.dark => 'Dark',
                    ThemeMode.light => 'Light',
                    ThemeMode.system => 'System',
                  },
                  style: TextStyle(color: context.palette.textSecondary),
                ),
                // Cycles System → Light → Dark, matching the three options on
                // the Settings screen rather than offering only two of them.
                onTap: () {
                  final prefs = ref.read(appPreferencesProvider);
                  final next = switch (prefs.themeMode) {
                    ThemeMode.system => ThemeMode.light,
                    ThemeMode.light => ThemeMode.dark,
                    ThemeMode.dark => ThemeMode.system,
                  };
                  ref.read(savePreferencesProvider)(prefs.copyWith(themeMode: next));
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => FirebaseAuth.instance.signOut(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  static String _initials(String value) {
    final parts = value.trim().split(RegExp(r'[\s@.]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: context.palette.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: context.palette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared scaffold for the secondary screens, matching their headers.
class SubPage extends StatelessWidget {
  const SubPage({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.child,
    this.actions = const [],
    this.floatingActionButton,
  });

  final String eyebrow;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(eyebrow.toUpperCase(),
                style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: context.palette.textSecondary)),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
          ],
        ),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: child,
    );
  }
}

/// The empty state used by screenshots 7–9 and 11.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.palette.selected,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'This focused space is ready for your content, preferences, and workflow.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
              style: FilledButton.styleFrom(
                backgroundColor: context.palette.selected,
                foregroundColor: AppColors.primary,
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper used by several sub-pages to ask for a single line of text.
Future<String?> promptText(BuildContext context, String title, {String initial = ''}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
      ],
    ),
  );
  controller.dispose();
  return (result == null || result.isEmpty) ? null : result;
}

/// Count of tasks per category, used on the Categories screen.
Map<String, int> activeTaskCountByCategory(List<Task> tasks) {
  final counts = <String, int>{};
  for (final t in tasks) {
    if (t.completed || t.categoryId == null) continue;
    counts[t.categoryId!] = (counts[t.categoryId!] ?? 0) + 1;
  }
  return counts;
}

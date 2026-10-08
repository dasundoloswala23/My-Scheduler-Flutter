import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../app/app_info.dart';
import '../../app/theme.dart';
import '../../core/notifications/platform/local_notification_adapter.dart';
import '../../core/account_service.dart';
import '../../core/holidays/holiday_data.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/providers.dart';
import '../../models/collections.dart';
import '../../models/task.dart';
import '../legal/legal_pages.dart';
import 'holidays_page.dart';
import 'more_page.dart';
import 'notification_settings_page.dart';

/// Screenshot 36: account, appearance and notification preferences.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// Asks for confirmation, re-authenticates, then deletes. Re-auth is required
  /// by Firebase for any deletion of a session that is not recent.
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your tasks, boards, notes, attachments and '
          'sign-in. It cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.palette.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;

    final service = AccountService(
      cancelLocalReminders: () => ref.read(notificationAdapterProvider).cancelAll(),
    );
    final user = FirebaseAuth.instance.currentUser;
    final providerIds = user?.providerData.map((p) => p.providerId).toSet() ?? {};

    try {
      if (providerIds.contains('password')) {
        final password = await _askPassword(context);
        if (password == null || !context.mounted) return;
        await service.reauthenticateWithPassword(password);
      } else if (providerIds.contains('apple.com')) {
        // Apple requires a fresh nonce-bound credential each time, not a
        // cached one, so this mirrors AuthService.signInWithApple.
        await service.reauthenticateWithAppleCredential();
      } else {
        await service.reauthenticateWithProvider(GoogleAuthProvider());
      }
      await service.deleteAccount();
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? 'That password is not correct.'
            : 'Could not delete the account. Please try again.'),
      ));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not delete the account. Please try again.'),
      ));
    }
  }

  /// Writes a changed preference back to the user document. Everything that
  /// reads it updates from the resulting snapshot, so nothing is held twice.
  void _save(WidgetRef ref, AppPreferences next) => ref.read(savePreferencesProvider)(next);

  Future<String?> _askPassword(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm it is you'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    controller.dispose();
    return (result == null || result.isEmpty) ? null : result;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = ref.watch(appPreferencesProvider);
    final themeMode = prefs.themeMode;
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final palette = context.palette;

    return SubPage(
      eyebrow: 'My Scheduler App',
      title: 'Settings',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Account', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(user?.email ?? 'Signed in',
                      style: TextStyle(fontSize: 12.5, color: context.palette.textSecondary)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Display name', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(user?.displayName ?? 'Not set',
                      style: TextStyle(fontSize: 12.5, color: context.palette.textSecondary)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final name = await promptText(context, 'Display name',
                        initial: user?.displayName ?? '');
                    if (name != null) await user?.updateDisplayName(name);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Reset password', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final email = user?.email;
                    if (email == null) return;
                    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Reset email sent to $email')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _SectionLabel('Appearance'),
          Card(
            child: _ChoiceTile<ThemeMode>(
              icon: Icons.dark_mode_outlined,
              title: 'Theme',
              value: themeMode,
              options: const {
                ThemeMode.system: 'System',
                ThemeMode.light: 'Light',
                ThemeMode.dark: 'Dark',
              },
              onChanged: (v) => _save(ref, prefs.copyWith(themeMode: v)),
            ),
          ),
          const SizedBox(height: 14),
          const _SectionLabel('Calendar'),
          Card(
            child: Column(
              children: [
                _ChoiceTile<CalendarViewPref>(
                  icon: Icons.calendar_month_outlined,
                  title: 'Default view',
                  value: prefs.calendarDefaultView,
                  options: const {
                    CalendarViewPref.day: 'Day',
                    CalendarViewPref.threeDay: '3 days',
                    CalendarViewPref.week: 'Week',
                    CalendarViewPref.month: 'Month',
                    CalendarViewPref.agenda: 'Agenda',
                  },
                  onChanged: (v) => _save(ref, prefs.copyWith(calendarDefaultView: v)),
                ),
                const Divider(height: 1),
                _ChoiceTile<int>(
                  icon: Icons.schedule_outlined,
                  title: 'Opens at',
                  subtitle: 'Where the day and week grids start. Earlier hours '
                      'are still there if you scroll up.',
                  value: prefs.calendarScrollHour,
                  options: {
                    for (final h in const [0, 6, 7, 8, 9, 10, 12])
                      h: DateFormat('h a').format(DateTime(2020, 1, 1, h)),
                  },
                  onChanged: (v) => _save(ref, prefs.copyWith(calendarScrollHour: v)),
                ),
                const Divider(height: 1),
                _ChoiceTile<CalendarDensity>(
                  icon: Icons.view_agenda_outlined,
                  title: 'Layout',
                  value: prefs.calendarDensity,
                  options: {
                    for (final d in CalendarDensity.values) d: d.label,
                  },
                  onChanged: (v) => _save(ref, prefs.copyWith(calendarDensity: v)),
                ),
                const Divider(height: 1),
                _ChoiceTile<bool>(
                  icon: Icons.first_page_outlined,
                  title: 'Week starts on',
                  value: prefs.weekStartsOnMonday,
                  options: const {true: 'Monday', false: 'Sunday'},
                  onChanged: (v) => _save(ref, prefs.copyWith(weekStartsOnMonday: v)),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.weekend_outlined),
                  title: const Text('Show weekends', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: prefs.showWeekends,
                  onChanged: (v) => _save(ref, prefs.copyWith(showWeekends: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _SectionLabel('Tasks'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.checklist_outlined),
                  title: const Text('Show subtasks on cards',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    prefs.showSubtasksOnCards
                        ? 'Cards show the checklist itself'
                        : 'Cards show only the completed count',
                    style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
                  ),
                  value: prefs.showSubtasksOnCards,
                  onChanged: (v) => _save(ref, prefs.copyWith(showSubtasksOnCards: v)),
                ),
                const Divider(height: 1),
                _ChoiceTile<TaskPriority>(
                  icon: Icons.flag_outlined,
                  title: 'Default priority',
                  value: prefs.defaultPriority,
                  options: {for (final p in TaskPriority.values) p: p.label},
                  onChanged: (v) => _save(ref, prefs.copyWith(defaultPriority: v)),
                ),
                const Divider(height: 1),
                _ChoiceTile<String?>(
                  icon: Icons.label_outline,
                  title: 'Default category',
                  value: categories.any((c) => c.id == prefs.defaultCategoryId)
                      ? prefs.defaultCategoryId
                      : null,
                  options: {
                    null: 'None',
                    for (final c in categories) c.id: c.name,
                  },
                  onChanged: (v) => _save(ref, prefs.copyWith(defaultCategoryId: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _SectionLabel('Holidays'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.celebration_outlined),
              title: const Text('Holiday calendars',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                prefs.holidayCountries.isEmpty
                    ? 'No countries selected'
                    : prefs.holidayCountries
                        .map((c) => HolidayData.country(c)?.name ?? c)
                        .join(', '),
                style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const HolidaysPage())),
            ),
          ),
          const SizedBox(height: 14),
          const _SectionLabel('Notifications'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Allow notifications', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    LocalNotificationAdapter().supportsScheduling
                        ? 'Reminders, quiet hours, sound and daily summary'
                        : 'Not available on this platform',
                    style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NotificationSettingsPage()),
                  ),
                ),
              ],
            ),
          ),
          const _SectionLabel('Legal'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of Service',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TermsPage()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: Icon(Icons.person_remove_outlined, color: palette.danger),
              title: Text('Delete account',
                  style: TextStyle(fontWeight: FontWeight.w600, color: palette.danger)),
              subtitle: Text('Permanently removes your tasks, files and sign-in',
                  style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
              onTap: () => _deleteAccount(context, ref),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text('$kAppName · v$kAppVersion',
                style: TextStyle(fontSize: 12, color: palette.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// The small heading above a group of settings.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: context.palette.textSecondary,
        ),
      ),
    );
  }
}

/// A settings row that opens a menu of [options] and reports the chosen key.
///
/// Used instead of a `DropdownButton` because the menu then picks up the app's
/// `popupMenuTheme` and so stays dark in dark mode.
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopupMenuButton<T>(
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final entry in options.entries)
          PopupMenuItem<T>(
            value: entry.key,
            child: Row(
              children: [
                Expanded(child: Text(entry.value)),
                if (entry.key == value)
                  const Icon(Icons.check, size: 17, color: AppColors.primary),
              ],
            ),
          ),
      ],
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(options[value] ?? '—',
                style: TextStyle(fontWeight: FontWeight.w600, color: palette.textSecondary)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 18, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}

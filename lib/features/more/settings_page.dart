import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/notifications/platform/local_notification_adapter.dart';
import '../../core/providers.dart';
import 'more_page.dart';
import 'notification_settings_page.dart';

/// Screenshot 36: account, appearance and notification preferences.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final themeMode = ref.watch(themeModeProvider);

    return SubPage(
      eyebrow: 'My scheduler',
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
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Display name', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(user?.displayName ?? 'Not set',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
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
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Dark mode', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: themeMode == ThemeMode.dark,
                  onChanged: (on) => ref
                      .read(themeModeProvider.notifier)
                      .set(on ? ThemeMode.dark : ThemeMode.light),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Allow notifications', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    LocalNotificationAdapter().supportsScheduling
                        ? 'Reminders, quiet hours, sound and daily summary'
                        : 'Not available on this platform',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NotificationSettingsPage()),
                  ),
                ),
              ],
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
          const Center(
            child: Text('My scheduler · v1.0.0',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}

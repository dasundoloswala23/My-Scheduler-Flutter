import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/notifications/platform/local_notification_adapter.dart';
import '../../core/account_service.dart';
import '../../core/providers.dart';
import 'more_page.dart';
import 'notification_settings_page.dart';

/// Screenshot 36: account, appearance and notification preferences.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// Asks for confirmation, re-authenticates, then deletes. Re-auth is required
  /// by Firebase for any deletion of a session that is not recent.
  Future<void> _deleteAccount(BuildContext context) async {
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;

    final service = AccountService();
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
    final themeMode = ref.watch(themeModeProvider);

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
              leading: const Icon(Icons.person_remove_outlined, color: AppColors.danger),
              title: const Text('Delete account',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.danger)),
              subtitle: const Text('Permanently removes your tasks, files and sign-in',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
              onTap: () => _deleteAccount(context),
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
            child: Text('My Scheduler App · v1.0.0',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../firebase_options.dart';
import '../../../models/task.dart';
import '../../repository.dart';
import '../services/preferences_service.dart';
import 'local_notification_adapter.dart';
import 'notification_adapter.dart';

/// Handles a notification action tapped while the app is not in the foreground.
///
/// This is what makes the lock-screen **Complete** and **Snooze** buttons do
/// their job. Without it the button only dismissed the notification and the
/// task stayed open, because the action buttons deliberately do not open the
/// app, so nothing else was listening.
///
/// The operating system runs this in a fresh background isolate: no UI, no
/// Riverpod and no Firebase yet. So it does the minimum, directly:
///
///   1. start Firebase and wait for the signed-in user to be restored,
///   2. read the same task document the app shows,
///   3. complete or snooze it through the same [Repo] methods the app uses.
///
/// Going through [Repo] matters. Completing a task there also cancels every
/// reminder the task owned, bumps `version` and spawns the next occurrence of a
/// repeating task, so a lock-screen completion behaves exactly like tapping the
/// circle on the board, and the board and calendar update because they read the
/// same document.
class BackgroundActions {
  const BackgroundActions._();

  /// How long to wait for Firebase Auth to restore the saved session. Long
  /// enough for a cold isolate, short enough not to hold the process open.
  static const Duration authTimeout = Duration(seconds: 8);

  static Future<void> handle(NotificationResponse response) async {
    // A background isolate has no plugins registered until this is called.
    DartPluginRegistrant.ensureInitialized();

    final event = LocalNotificationAdapter.eventFromResponse(response);
    if (event == null) return;

    // Open needs a UI, so it is never run here: the OS launches the app and the
    // router handles it. Only the two actions that work without one belong in
    // this isolate.
    if (event.action == NotificationAction.open) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }

      final user = await _signedInUser();
      if (user == null) return; // Signed out: there is nothing of theirs to touch.

      final repo = Repo(uid: user.uid);
      final snap = await repo.tasks.doc(event.taskId).get();
      if (!snap.exists) return; // Deleted since the alert was scheduled.
      final task = Task.fromDoc(snap);

      switch (event.action) {
        case NotificationAction.complete:
          await repo.setTaskCompleted(task, true);
        case NotificationAction.snooze:
          final prefs = await NotificationPreferencesService(uid: user.uid).load();
          repo.notificationPreferences = prefs;
          await repo.snoozeTask(
            task,
            minutes: event.snoozeMinutes ?? prefs.snoozeMinutes,
            reminderId: event.reminderId,
          );
        case NotificationAction.open:
          break;
      }
    } catch (_) {
      // Nothing can be shown from here and there is no one to tell. A failure
      // leaves the task as it was, which is the safe outcome: the reminder was
      // dismissed, but nothing was marked done that was not.
    }
  }

  /// The restored user, or null. `currentUser` is null until persistence has
  /// been read, so wait for the first auth state rather than trusting it.
  static Future<User?> _signedInUser() async {
    final auth = FirebaseAuth.instance;
    final immediate = auth.currentUser;
    if (immediate != null) return immediate;
    try {
      return await auth.authStateChanges().first.timeout(authTimeout);
    } on TimeoutException {
      return null;
    }
  }
}

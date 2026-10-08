import 'package:flutter/foundation.dart';

import 'reminder.dart';

/// One selectable reminder sound.
///
/// The catalogue is deliberately small and honest: every entry here is a real,
/// different audio file, and [availableOn] only lists the ones the notification
/// can actually play on the current platform. A settings screen that offered a
/// sound the OS would then silently replace with the default would be exactly
/// the fake choice the product rules out.
@immutable
class ReminderSound {
  const ReminderSound({
    required this.id,
    required this.label,
    required this.asset,
    required this.androidRawName,
  });

  /// Stored on the reminder and in preferences. Never change an existing id:
  /// it is saved in users' documents.
  final String id;
  final String label;

  /// Flutter asset used for the in-app preview.
  final String asset;

  /// File name (without extension) in `android/app/src/main/res/raw`. Android
  /// plays a notification sound from there, and only from there.
  final String androidRawName;
}

/// Plays whatever sound the operating system has chosen for notifications.
const String kSystemSoundId = 'system';

/// No sound at all.
const String kSilentSoundId = 'silent';

const List<ReminderSound> kBundledSounds = [
  ReminderSound(
    id: 'soft_bell',
    label: 'Soft Bell',
    asset: 'assets/sounds/soft_bell.wav',
    androidRawName: 'soft_bell',
  ),
  ReminderSound(
    id: 'classic_bell',
    label: 'Classic Bell',
    asset: 'assets/sounds/classic_bell.wav',
    androidRawName: 'classic_bell',
  ),
  ReminderSound(
    id: 'alert',
    label: 'Alert',
    asset: 'assets/sounds/alert.wav',
    androidRawName: 'alert',
  ),
  ReminderSound(
    id: 'digital',
    label: 'Digital',
    asset: 'assets/sounds/digital.wav',
    androidRawName: 'digital',
  ),
  ReminderSound(
    id: 'chime',
    label: 'Chime',
    asset: 'assets/sounds/chime.wav',
    androidRawName: 'chime',
  ),
  ReminderSound(
    id: 'urgent',
    label: 'Urgent',
    asset: 'assets/sounds/urgent.wav',
    androidRawName: 'urgent',
  ),
];

/// What the picker offers, and what a notification can actually play.
class ReminderSounds {
  const ReminderSounds._();

  /// Whether bundled sounds can be used as the notification sound here.
  ///
  /// Android reads them from `res/raw`, which this project ships. iOS and macOS
  /// would need each file added to the Xcode target as a bundle resource, and
  /// Windows toasts take only the system sounds; none of that is wired up, so
  /// on those platforms the only honest choices are the system sound and
  /// silence. See docs/REMINDERS.md for the Xcode step.
  static bool supportsBundledSounds([TargetPlatform? platform]) {
    if (kIsWeb) return false;
    return (platform ?? defaultTargetPlatform) == TargetPlatform.android;
  }

  /// Ids offered in the picker on [platform], in display order.
  static List<String> idsFor([TargetPlatform? platform]) => [
        kSystemSoundId,
        if (supportsBundledSounds(platform)) ...kBundledSounds.map((s) => s.id),
        kSilentSoundId,
      ];

  static ReminderSound? byId(String? id) {
    for (final sound in kBundledSounds) {
      if (sound.id == id) return sound;
    }
    return null;
  }

  static String labelFor(String? id) => switch (id) {
        null || kSystemSoundId => 'System default',
        kSilentSoundId => 'Silent',
        _ => byId(id)?.label ?? 'System default',
      };

  /// The sound that will really play for [id], falling back when it cannot.
  ///
  /// A reminder created on an Android phone may be scheduled by an iPhone that
  /// syncs the same task. The iPhone cannot play "Chime", so it plays the
  /// system sound rather than failing or playing nothing.
  static String resolve(String? id, [TargetPlatform? platform]) {
    final wanted = id ?? kSystemSoundId;
    return idsFor(platform).contains(wanted) ? wanted : kSystemSoundId;
  }

  /// The default for a mode when neither the reminder nor the settings say.
  ///
  /// An alarm defaults to the siren where it can be played, because an alarm
  /// that sounds like a polite chime is not doing its job.
  static String defaultFor(AlertMode mode, [TargetPlatform? platform]) {
    if (mode == AlertMode.alarm && supportsBundledSounds(platform)) return 'urgent';
    return kSystemSoundId;
  }
}

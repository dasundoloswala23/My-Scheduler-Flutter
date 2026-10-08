import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/notifications/models/notification_preferences.dart';
import 'package:myschedule/core/notifications/models/reminder.dart';
import 'package:myschedule/core/notifications/models/reminder_sound.dart';
import 'package:myschedule/core/notifications/platform/local_notification_adapter.dart';
import 'package:myschedule/core/notifications/platform/notification_adapter.dart';
import 'package:myschedule/core/notifications/scheduling/reminder_calculator.dart';
import 'package:myschedule/core/notifications/scheduling/upcoming_reminders.dart';
import 'package:myschedule/core/notifications/services/notification_service.dart';
import 'package:myschedule/features/task_detail/reminder_alert_options.dart';
import 'package:myschedule/models/task.dart';

final kNow = DateTime(2026, 10, 5, 9, 0);

Task _task({
  String id = 'task-1',
  DateTime? start,
  bool completed = false,
  List<Reminder> reminders = const [],
}) =>
    Task(
      id: id,
      title: 'Kitty Meow Video',
      startDateTime: start,
      endDateTime: start?.add(const Duration(hours: 1)),
      completed: completed,
      reminders: reminders,
    );

Reminder _reminder(
  int minutes, {
  String? id,
  AlertMode mode = AlertMode.notification,
  String? sound,
  bool? vibrate,
  bool enabled = true,
}) =>
    Reminder(
      id: id ?? 'r-$minutes-${mode.name}',
      taskId: 'task-1',
      type: minutes == 0 ? ReminderType.atTime : ReminderType.beforeTask,
      offsetMinutes: minutes,
      alertMode: mode,
      soundId: sound,
      vibrate: vibrate,
      enabled: enabled,
    );

// ---------------------------------------------------------------- audio helpers

/// Decodes a 16-bit mono PCM WAV file written by tools/generate_sounds.dart.
({List<double> samples, int rate}) _decodeWav(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
  expect(tag(0), 'RIFF');
  expect(tag(8), 'WAVE');
  expect(data.getUint16(22, Endian.little), 1, reason: 'mono');
  expect(data.getUint16(34, Endian.little), 16, reason: '16-bit');
  final rate = data.getUint32(24, Endian.little);
  final count = (bytes.length - 44) ~/ 2;
  return (
    samples: [for (var i = 0; i < count; i++) data.getInt16(44 + i * 2, Endian.little) / 32768.0],
    rate: rate,
  );
}

/// Signal power at one frequency (the Goertzel algorithm).
double _power(List<double> s, double freq, int rate) {
  final k = 2 * math.cos(2 * math.pi * freq / rate);
  var a = 0.0, b = 0.0;
  for (final x in s) {
    final c = x + k * a - b;
    b = a;
    a = c;
  }
  return a * a + b * b - k * a * b;
}

List<double> _unit(List<double> v) {
  final norm = math.sqrt(v.fold<double>(0, (t, x) => t + x * x));
  return norm == 0 ? v : [for (final x in v) x / norm];
}

/// A signature of what the sound sounds like (which pitches) and how it
/// unfolds in time (its rhythm), so two sounds only look alike if both match.
List<double> _signature(({List<double> samples, int rate}) wav) {
  final probes = [for (var i = 0; i < 40; i++) 300 * math.pow(5200 / 300, i / 39).toDouble()];
  final spectrum = _unit([for (final f in probes) _power(wav.samples, f, wav.rate)]);

  // RMS energy per 100 ms over the first 2.5 seconds.
  final window = wav.rate ~/ 10;
  final envelope = _unit([
    for (var w = 0; w < 25; w++)
      () {
        final start = w * window;
        if (start >= wav.samples.length) return 0.0;
        final end = math.min(start + window, wav.samples.length);
        var sum = 0.0;
        for (var i = start; i < end; i++) {
          sum += wav.samples[i] * wav.samples[i];
        }
        return math.sqrt(sum / (end - start));
      }(),
  ]);
  return [...spectrum, ...envelope];
}

double _cosine(List<double> a, List<double> b) {
  var dot = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return dot / 2; // each half is unit length, so the whole has norm sqrt(2)
}

void main() {
  late FakeClock clock;
  late FakeNotificationAdapter adapter;
  late NotificationService service;

  setUp(() {
    clock = FakeClock(kNow);
    adapter = FakeNotificationAdapter();
    service = NotificationService(adapter: adapter, clock: clock);
  });

  group('a reminder carries its own alert settings', () {
    test('round-trips mode, sound and vibration', () {
      final original = _reminder(30, mode: AlertMode.alarm, sound: 'chime', vibrate: false);
      final restored = Reminder.fromJson(original.toJson());

      expect(restored.alertMode, AlertMode.alarm);
      expect(restored.soundId, 'chime');
      expect(restored.vibrate, isFalse);
    });

    test('a document written before alarms existed stays a plain notification', () {
      final restored = Reminder.fromJson({
        'id': 'old',
        'taskId': 't',
        'type': 'beforeTask',
        'offsetMinutes': 15,
      });
      expect(restored.alertMode, AlertMode.notification);
      expect(restored.soundId, isNull);
      expect(restored.vibrate, isNull);
    });

    test('an unknown mode from a newer build falls back instead of throwing', () {
      final restored = Reminder.fromJson({'id': 'x', 'taskId': 't', 'alertMode': 'siren-2'});
      expect(restored.alertMode, AlertMode.notification);
    });

    test('switching the mode counts as a change, so the sync reschedules it', () {
      expect(_reminder(30, id: 'a'), isNot(_reminder(30, id: 'a', mode: AlertMode.alarm)));
      expect(_reminder(30, id: 'a'), isNot(_reminder(30, id: 'a', sound: 'chime')));
      expect(_reminder(30, id: 'a'), equals(_reminder(30, id: 'a')));
    });

    test('withTaskId re-keys the reminder and keeps every setting', () {
      final r = _reminder(5, mode: AlertMode.alarm, sound: 'urgent', vibrate: true);
      final moved = r.withTaskId('real-id');
      expect(moved.taskId, 'real-id');
      expect(moved.alertMode, AlertMode.alarm);
      expect(moved.soundId, 'urgent');
      expect(moved.vibrate, isTrue);
      expect(moved.id, r.id);
    });
  });

  group('the sound catalogue only offers sounds that work', () {
    test('Android offers the bundled sounds as well as system and silent', () {
      final ids = ReminderSounds.idsFor(TargetPlatform.android);
      expect(ids.first, kSystemSoundId);
      expect(ids.last, kSilentSoundId);
      expect(ids, containsAll(['soft_bell', 'classic_bell', 'alert', 'digital', 'chime', 'urgent']));
    });

    test('iOS, macOS and Windows offer only system and silent, not fake choices', () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.windows]) {
        expect(ReminderSounds.idsFor(platform), [kSystemSoundId, kSilentSoundId],
            reason: '$platform cannot play bundled sounds here');
      }
    });

    test('a sound chosen on Android falls back to the system sound on iOS', () {
      expect(ReminderSounds.resolve('chime', TargetPlatform.android), 'chime');
      expect(ReminderSounds.resolve('chime', TargetPlatform.iOS), kSystemSoundId);
      expect(ReminderSounds.resolve(null, TargetPlatform.iOS), kSystemSoundId);
      expect(ReminderSounds.resolve('does-not-exist', TargetPlatform.android), kSystemSoundId);
    });

    test('an alarm defaults to the siren where it can, a notification to the system sound', () {
      expect(ReminderSounds.defaultFor(AlertMode.alarm, TargetPlatform.android), 'urgent');
      expect(ReminderSounds.defaultFor(AlertMode.notification, TargetPlatform.android),
          kSystemSoundId);
      expect(ReminderSounds.defaultFor(AlertMode.alarm, TargetPlatform.iOS), kSystemSoundId);
    });

    test('every bundled sound has a label, an asset and a valid Android resource name', () {
      for (final s in kBundledSounds) {
        expect(s.label, isNotEmpty);
        expect(s.asset, startsWith('assets/sounds/'));
        // Android resource names: lower-case letters, digits and underscores.
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(s.androidRawName), isTrue,
            reason: '${s.androidRawName} is not a legal Android resource name');
      }
      expect(kBundledSounds.map((s) => s.id).toSet().length, kBundledSounds.length,
          reason: 'ids must be unique');
    });
  });

  group('the sound files', () {
    test('every sound exists as an asset and as an Android resource, byte for byte', () {
      for (final s in kBundledSounds) {
        final asset = File(s.asset);
        final raw = File('android/app/src/main/res/raw/${s.androidRawName}.wav');
        expect(asset.existsSync(), isTrue, reason: '${s.asset} is missing');
        expect(raw.existsSync(), isTrue, reason: '${raw.path} is missing');
        expect(raw.readAsBytesSync(), asset.readAsBytesSync(),
            reason: 'the preview and the real notification must play the same audio');
      }
    });

    test('the release keep rule names every sound, so the shrinker cannot delete one', () {
      // Notification sounds are looked up by name at runtime, so the resource
      // shrinker sees them as unused and strips them from release builds. The
      // keep file prevents that, but only for the sounds it lists.
      final keep = File('android/app/src/main/res/raw/reminder_sounds_keep.xml')
          .readAsStringSync();
      final kept = RegExp(r'@raw/([a-z0-9_]+)').allMatches(keep).map((m) => m.group(1)).toSet();

      expect(kept, kBundledSounds.map((s) => s.androidRawName).toSet(),
          reason: 'a sound missing from the keep rule works in debug and is silent in release');
    });

    test('they are valid, reasonably short and do not clip', () {
      for (final s in kBundledSounds) {
        final wav = _decodeWav(File(s.asset).readAsBytesSync());
        final seconds = wav.samples.length / wav.rate;
        expect(seconds, inInclusiveRange(0.5, 4.0), reason: '${s.id} is $seconds s');
        final peak = wav.samples.fold<double>(0, (m, x) => math.max(m, x.abs()));
        expect(peak, lessThan(0.99), reason: '${s.id} clips');
        expect(peak, greaterThan(0.5), reason: '${s.id} is too quiet');
      }
    });

    test('they genuinely sound different, in pitch and in rhythm, not just in name', () {
      final signatures = {
        for (final s in kBundledSounds) s.id: _signature(_decodeWav(File(s.asset).readAsBytesSync())),
      };

      final ids = signatures.keys.toList();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final similarity = _cosine(signatures[ids[i]]!, signatures[ids[j]]!);
          expect(similarity, lessThan(0.95),
              reason: '${ids[i]} and ${ids[j]} are too alike (similarity $similarity)');
        }
      }
    });
  });

  group('alert type in the schedule', () {
    final start = DateTime(2026, 10, 5, 18, 0);

    test('an alarm reminder is planned as an alarm, with its sound and vibration', () async {
      final r = _reminder(30, mode: AlertMode.alarm, sound: 'urgent', vibrate: true);
      final plan = const ReminderCalculator(clock: Clock.system()).plan(
        task: _task(start: DateTime.now().add(const Duration(days: 2)), reminders: [r]),
        reminders: [r],
      );
      final n = plan.scheduled.single;
      expect(n.isAlarm, isTrue);
      expect(n.soundId, 'urgent');
      expect(n.vibrate, isTrue);
    });

    test('a notification reminder is planned as a notification', () async {
      final r = _reminder(30);
      await service.sync(task: _task(start: start, reminders: [r]), reminders: [r]);
      final n = adapter.scheduled.values.single;
      expect(n.isAlarm, isFalse);
      expect(n.alertMode, AlertMode.notification);
    });

    test('one task can mix types: the example from the brief', () async {
      // 6 PM task: 1 hour and 30 minutes as notifications; 5 minutes and at
      // the time as alarms.
      final reminders = [
        _reminder(60, id: 'h1'),
        _reminder(30, id: 'm30'),
        _reminder(5, id: 'm5', mode: AlertMode.alarm),
        _reminder(0, id: 'now', mode: AlertMode.alarm),
      ];
      await service.sync(task: _task(start: start, reminders: reminders), reminders: reminders);

      final byReminder = {for (final n in adapter.scheduled.values) n.reminderId: n};
      expect(byReminder['h1']!.isAlarm, isFalse);
      expect(byReminder['m30']!.isAlarm, isFalse);
      expect(byReminder['m5']!.isAlarm, isTrue);
      expect(byReminder['now']!.isAlarm, isTrue);
      expect(adapter.scheduled, hasLength(4), reason: 'one alert each, no duplicates');
      expect(byReminder['h1']!.fireAt, DateTime(2026, 10, 5, 17, 0));
      expect(byReminder['m5']!.fireAt, DateTime(2026, 10, 5, 17, 55));
      expect(byReminder['now']!.fireAt, start);
    });

    test('with alarms switched off an alarm reminder is downgraded, not dropped', () async {
      final r = _reminder(30, mode: AlertMode.alarm);
      await service.sync(
        task: _task(start: start, reminders: [r]),
        reminders: [r],
        preferences: const NotificationPreferences(alarmsEnabled: false),
      );
      final n = adapter.scheduled.values.single;
      expect(n.isAlarm, isFalse);
      expect(n.fireAt, DateTime(2026, 10, 5, 17, 30));
    });

    test('a reminder with no sound of its own uses the default for its mode', () async {
      final note = _reminder(30, id: 'n');
      final alarm = _reminder(10, id: 'a', mode: AlertMode.alarm);
      await service.sync(
        task: _task(start: start, reminders: [note, alarm]),
        reminders: [note, alarm],
        preferences: const NotificationPreferences(
          notificationSoundId: 'soft_bell',
          alarmSoundId: 'urgent',
        ),
      );
      final byId = {for (final n in adapter.scheduled.values) n.reminderId: n};
      expect(byId['n']!.soundId, 'soft_bell');
      expect(byId['a']!.soundId, 'urgent');
    });

    test("a reminder's own sound beats the default: the per-task override", () async {
      final r = _reminder(30, sound: 'digital');
      await service.sync(
        task: _task(start: start, reminders: [r]),
        reminders: [r],
        preferences: const NotificationPreferences(notificationSoundId: 'soft_bell'),
      );
      expect(adapter.scheduled.values.single.soundId, 'digital');
    });

    test("a reminder's own vibration beats the default", () async {
      final off = _reminder(30, id: 'off', vibrate: false);
      final on = _reminder(10, id: 'on', vibrate: true);
      await service.sync(
        task: _task(start: start, reminders: [off, on]),
        reminders: [off, on],
        preferences: const NotificationPreferences(vibration: VibrationPattern.none),
      );
      final byId = {for (final n in adapter.scheduled.values) n.reminderId: n};
      expect(byId['off']!.vibrate, isFalse);
      expect(byId['on']!.vibrate, isTrue);
    });
  });

  group('quiet hours and alarms', () {
    // 11:30 PM, inside a 10 PM to 7 AM quiet window.
    final late = DateTime(2026, 10, 5, 23, 30);
    const quiet = NotificationPreferences(quietHoursEnabled: true);

    SchedulePlan plan(Reminder r, NotificationPreferences prefs) =>
        ReminderCalculator(clock: clock).plan(
          task: _task(start: late, reminders: [r]),
          reminders: [r],
          preferences: prefs,
        );

    test('a notification is held back during quiet hours', () {
      final p = plan(_reminder(0), quiet);
      expect(p.scheduled, isEmpty);
      expect(p.skipped.single.reason, SkipReason.quietHours);
    });

    test('an alarm is also held back by default: bypassing is opt-in', () {
      final p = plan(_reminder(0, mode: AlertMode.alarm), quiet);
      expect(p.scheduled, isEmpty, reason: 'alarms only bypass quiet hours if asked to');
    });

    test('an alarm gets through once the user explicitly allows it', () {
      final p = plan(
        _reminder(0, mode: AlertMode.alarm),
        quiet.copyWith(alarmsIgnoreQuietHours: true),
      );
      expect(p.scheduled, hasLength(1));
    });

    test('allowing alarms does not let plain notifications through', () {
      final p = plan(_reminder(0), quiet.copyWith(alarmsIgnoreQuietHours: true));
      expect(p.scheduled, isEmpty);
    });

    test('with alarms off, the "allow alarms" setting cannot smuggle a reminder through', () {
      final p = plan(
        _reminder(0, mode: AlertMode.alarm),
        quiet.copyWith(alarmsIgnoreQuietHours: true, alarmsEnabled: false),
      );
      expect(p.scheduled, isEmpty,
          reason: 'it was downgraded to a notification, which quiet hours hold back');
    });
  });

  group('rescheduling keeps the alert type', () {
    test('moving a task 6 PM to 8 PM moves an alarm and it is still an alarm', () async {
      final r = _reminder(30, mode: AlertMode.alarm, sound: 'urgent', id: 'a');
      final original = _task(start: DateTime(2026, 10, 5, 18, 0), reminders: [r]);
      await service.sync(task: original, reminders: [r]);
      expect(adapter.scheduled.values.single.fireAt, DateTime(2026, 10, 5, 17, 30));

      final moved = _task(start: DateTime(2026, 10, 5, 20, 0), reminders: [r]);
      await service.sync(task: moved, reminders: [r], previousReminders: [r]);

      expect(adapter.scheduled, hasLength(1), reason: 'the old 5:30 PM alert is gone');
      final n = adapter.scheduled.values.single;
      expect(n.fireAt, DateTime(2026, 10, 5, 19, 30));
      expect(n.isAlarm, isTrue);
      expect(n.soundId, 'urgent');
    });

    test('changing a reminder from notification to alarm replaces it, not adds to it', () async {
      final before = _reminder(30, id: 'x');
      final start = DateTime(2026, 10, 5, 18, 0);
      await service.sync(task: _task(start: start, reminders: [before]), reminders: [before]);

      final after = before.copyWith(alertMode: AlertMode.alarm);
      await service.sync(
        task: _task(start: start, reminders: [after]),
        reminders: [after],
        previousReminders: [before],
      );

      expect(adapter.scheduled, hasLength(1));
      expect(adapter.scheduled.values.single.isAlarm, isTrue);
    });

    test('snoozing an alarm brings it back as an alarm with the same sound', () async {
      final r = _reminder(30, mode: AlertMode.alarm, sound: 'classic_bell', id: 'a');
      final t = _task(start: DateTime(2026, 10, 5, 18, 0), reminders: [r]);
      await service.sync(task: t, reminders: [r]);

      final fireAt = await service.snooze(task: t, reminder: r, minutes: 10);

      expect(fireAt, kNow.add(const Duration(minutes: 10)));
      expect(adapter.scheduled, hasLength(1), reason: 'snooze replaces, it does not double up');
      final n = adapter.scheduled.values.single;
      expect(n.isAlarm, isTrue);
      expect(n.soundId, 'classic_bell');
    });

    test('snoozing twice still leaves one alert', () async {
      final r = _reminder(30, id: 'a');
      final t = _task(start: DateTime(2026, 10, 5, 18, 0), reminders: [r]);
      await service.sync(task: t, reminders: [r]);

      await service.snooze(task: t, reminder: r, minutes: 5);
      await service.snooze(task: t, reminder: r, minutes: 10);

      expect(adapter.scheduled, hasLength(1));
    });

    test('completing a task cancels its alarms and notifications', () async {
      final reminders = [_reminder(30, id: 'n'), _reminder(5, id: 'a', mode: AlertMode.alarm)];
      final t = _task(start: DateTime(2026, 10, 5, 18, 0), reminders: reminders);
      await service.sync(task: t, reminders: reminders);
      expect(adapter.scheduled, hasLength(2));

      await service.cancelForTask(t, reminders);
      expect(adapter.scheduled, isEmpty);
    });
  });

  group('what each alert type means on each platform', () {
    test('Android alarm is described as repeating and waking the screen', () {
      final text = describeAlertMode(AlertMode.alarm, TargetPlatform.android);
      expect(text, contains('repeats'));
      expect(text, contains('wake'));
    });

    test('iOS does not claim a repeating alarm, and says what it does instead', () {
      final text = describeAlertMode(AlertMode.alarm, TargetPlatform.iOS);
      expect(text, contains('Time Sensitive'));
      expect(text, contains('sounds once'));
      expect(text, isNot(contains('repeats until')));
    });

    test('desktop does not claim a repeating alarm either', () {
      for (final p in [TargetPlatform.macOS, TargetPlatform.windows]) {
        expect(describeAlertMode(AlertMode.alarm, p), contains('cannot repeat'));
      }
    });

    test('the two types are described differently', () {
      expect(describeAlertMode(AlertMode.notification), isNot(describeAlertMode(AlertMode.alarm)));
    });

    test('only Android offers a vibration switch', () {
      expect(supportsVibrationChoice(TargetPlatform.android), isTrue);
      expect(supportsVibrationChoice(TargetPlatform.iOS), isFalse);
      expect(supportsVibrationChoice(TargetPlatform.windows), isFalse);
    });
  });

  group('notification preferences', () {
    test('the new settings round-trip', () {
      const original = NotificationPreferences(
        alarmsEnabled: false,
        defaultAlertMode: AlertMode.alarm,
        notificationSoundId: 'soft_bell',
        alarmSoundId: 'urgent',
        snoozeMinutes: 15,
        alarmsIgnoreQuietHours: true,
        showContentOnLockScreen: false,
        badge: false,
      );
      final restored = NotificationPreferences.fromJson(original.toJson());

      expect(restored.alarmsEnabled, isFalse);
      expect(restored.defaultAlertMode, AlertMode.alarm);
      expect(restored.notificationSoundId, 'soft_bell');
      expect(restored.alarmSoundId, 'urgent');
      expect(restored.snoozeMinutes, 15);
      expect(restored.alarmsIgnoreQuietHours, isTrue);
      expect(restored.showContentOnLockScreen, isFalse);
      expect(restored.badge, isFalse);
    });

    test('the defaults match the brief', () {
      const d = NotificationPreferences();
      expect(d.alarmsEnabled, isTrue);
      expect(d.defaultAlertMode, AlertMode.notification, reason: 'never silently an alarm');
      expect(d.alarmsIgnoreQuietHours, isFalse, reason: 'alarms bypass quiet hours only if asked');
      expect(d.snoozeMinutes, 10);
      expect(d.showContentOnLockScreen, isTrue);
    });

    test('a document from before these settings still loads, with the defaults', () {
      final restored = NotificationPreferences.fromJson({'masterEnabled': true, 'quietHoursEnabled': true});
      expect(restored.alarmsEnabled, isTrue);
      expect(restored.alarmsIgnoreQuietHours, isFalse);
      expect(restored.snoozeMinutes, 10);
    });

    test('an absurd snooze value is clamped to something sane', () {
      expect(NotificationPreferences.fromJson({'snoozeMinutes': 0}).snoozeMinutes, 1);
      expect(NotificationPreferences.fromJson({'snoozeMinutes': 99999}).snoozeMinutes, 240);
    });
  });

  group('the upcoming reminders list', () {
    final now = DateTime(2026, 10, 5, 12, 0);

    Map<ReminderBucket, List<UpcomingReminder>> group(List<Task> tasks) =>
        groupUpcomingReminders(tasks, now);

    test('groups into today, tomorrow and later, in time order', () {
      final today = _task(
          id: 'a', start: DateTime(2026, 10, 5, 18, 0), reminders: [_reminder(30, id: 'r1')]);
      final tomorrow = _task(
          id: 'b', start: DateTime(2026, 10, 6, 9, 0), reminders: [_reminder(30, id: 'r2')]);
      final later = _task(
          id: 'c', start: DateTime(2026, 10, 9, 9, 0), reminders: [_reminder(30, id: 'r3')]);

      final g = group([later, tomorrow, today]);
      expect(g[ReminderBucket.today]!.map((e) => e.task.id), ['a']);
      expect(g[ReminderBucket.tomorrow]!.map((e) => e.task.id), ['b']);
      expect(g[ReminderBucket.later]!.map((e) => e.task.id), ['c']);
    });

    test('lists a reminder by when it fires, not when the task starts', () {
      // The task is tomorrow at 00:30, but its 60 minute reminder fires today.
      final t = _task(start: DateTime(2026, 10, 6, 0, 30), reminders: [_reminder(60, id: 'r')]);
      expect(group([t])[ReminderBucket.today]!, hasLength(1));
    });

    test('leaves out completed tasks, disabled reminders and unscheduled tasks', () {
      final start = DateTime(2026, 10, 5, 18, 0);
      final g = group([
        _task(id: 'done', start: start, completed: true, reminders: [_reminder(30)]),
        _task(id: 'off', start: start, reminders: [_reminder(30, enabled: false)]),
        _task(id: 'none', reminders: [_reminder(30)]),
      ]);
      expect(g.values.every((l) => l.isEmpty), isTrue);
    });

    test('a reminder from the last day is missed; an older one is dropped', () {
      final recent = _task(
          id: 'recent', start: DateTime(2026, 10, 5, 8, 0), reminders: [_reminder(0, id: 'r')]);
      final old = _task(
          id: 'old', start: DateTime(2026, 10, 1, 8, 0), reminders: [_reminder(0, id: 'o')]);
      final g = group([recent, old]);
      expect(g[ReminderBucket.missed]!.map((e) => e.task.id), ['recent']);
    });

    test('carries the alert type so the list can show it', () {
      final t = _task(
        start: DateTime(2026, 10, 5, 18, 0),
        reminders: [_reminder(30, mode: AlertMode.alarm, sound: 'chime')],
      );
      final item = group([t])[ReminderBucket.today]!.single;
      expect(item.reminder.alertMode, AlertMode.alarm);
      expect(item.reminder.soundId, 'chime');
    });
  });

  group('acting on a notification', () {
    NotificationResponse response({String? actionId, Object? payload, int id = 42}) =>
        NotificationResponse(
          notificationResponseType: actionId == null
              ? NotificationResponseType.selectedNotification
              : NotificationResponseType.selectedNotificationAction,
          id: id,
          actionId: actionId,
          payload: payload is String ? payload : (payload == null ? null : jsonEncode(payload)),
        );

    test('Complete, Snooze and a plain tap map to their actions', () {
      final payload = {'taskId': 't1', 'reminderId': 'r1'};

      final complete =
          LocalNotificationAdapter.eventFromResponse(response(actionId: 'complete', payload: payload));
      final snooze =
          LocalNotificationAdapter.eventFromResponse(response(actionId: 'snooze', payload: payload));
      final open = LocalNotificationAdapter.eventFromResponse(response(payload: payload));

      expect(complete!.action, NotificationAction.complete);
      expect(snooze!.action, NotificationAction.snooze);
      expect(open!.action, NotificationAction.open, reason: 'tapping the body opens the task');
    });

    test('the event names the exact task, reminder and notification', () {
      final event = LocalNotificationAdapter.eventFromResponse(
        response(actionId: 'complete', payload: {'taskId': 'task-77', 'reminderId': 'rem-9'}, id: 1234),
      )!;
      expect(event.taskId, 'task-77');
      expect(event.reminderId, 'rem-9');
      expect(event.notificationId, 1234,
          reason: 'needed to silence an alarm that is still sounding');
    });

    test('a payload that is not ours is ignored rather than crashing', () {
      expect(LocalNotificationAdapter.eventFromResponse(response(payload: 'not json')), isNull);
      expect(LocalNotificationAdapter.eventFromResponse(response(payload: <String, Object>{})), isNull);
      expect(LocalNotificationAdapter.eventFromResponse(response()), isNull);
    });
  });
}

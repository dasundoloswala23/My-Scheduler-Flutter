import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/notifications/models/reminder.dart';
import '../../core/notifications/models/reminder_sound.dart';

/// What an alert type really does on [platform], in plain words.
///
/// Notification and alarm are different behaviours and the user has to be able
/// to tell which they are choosing, including where the platform cannot do
/// everything the word "alarm" suggests. iOS in particular has no unrestricted
/// third-party alarm, and saying so is part of the feature.
String describeAlertMode(AlertMode mode, [TargetPlatform? platform]) {
  final target = platform ?? defaultTargetPlatform;
  switch (mode) {
    case AlertMode.notification:
      return 'A normal notification. It appears once, in the notification '
          'shade and on the lock screen.';
    case AlertMode.alarm:
      return switch (target) {
        TargetPlatform.android => 'Plays on the alarm volume and repeats until you '
            'Complete or Snooze it. It can wake the screen, and Android may ask '
            'for permission to show over the lock screen.',
        TargetPlatform.iOS => 'iOS does not allow third-party apps to ring like the '
            'Clock app. This sends a Time Sensitive notification: it can break '
            'through Focus and shows on the lock screen, but sounds once.',
        TargetPlatform.macOS || TargetPlatform.windows => 'Desktop systems cannot '
            'repeat a sound like a phone alarm. This uses the strongest alert '
            'the system allows.',
        _ => 'Uses the strongest alert this device allows.',
      };
  }
}

/// Whether the vibration switch means anything here. iOS and desktop decide
/// vibration themselves, so offering a switch there would be another fake
/// control.
bool supportsVibrationChoice([TargetPlatform? platform]) =>
    !kIsWeb && (platform ?? defaultTargetPlatform) == TargetPlatform.android;

/// Plays a bundled sound for the preview button.
///
/// One shared player, so tapping a second preview stops the first instead of
/// overlapping, and it is released when the owning widget goes away.
class SoundPreviewPlayer {
  SoundPreviewPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  /// Plays [soundId]. Returns false when there is nothing the app can play for
  /// it, which is the case for the system default and for silence.
  Future<bool> play(String soundId) async {
    final sound = ReminderSounds.byId(soundId);
    if (sound == null) return false;
    await _player.stop();
    // AssetSource paths are relative to the assets directory.
    await _player.play(AssetSource(sound.asset.replaceFirst('assets/', '')));
    return true;
  }

  Future<void> stop() => _player.stop();
  Future<void> dispose() => _player.dispose();
}

/// The alert controls shared by the reminder editor and Quick Add: Notification
/// or Alarm, which sound, and whether to vibrate.
///
/// `soundId` and `vibrate` are nullable on purpose. Null means "follow the
/// default for this mode", so a reminder keeps tracking the settings screen
/// until the user picks something specific for it.
class ReminderAlertOptions extends StatefulWidget {
  const ReminderAlertOptions({
    super.key,
    required this.mode,
    required this.soundId,
    required this.vibrate,
    required this.onChanged,
    this.defaultVibrate = true,
  });

  final AlertMode mode;
  final String? soundId;
  final bool? vibrate;

  /// What "follow the default" means for vibration, from the settings.
  final bool defaultVibrate;

  final void Function(AlertMode mode, String? soundId, bool? vibrate) onChanged;

  @override
  State<ReminderAlertOptions> createState() => _ReminderAlertOptionsState();
}

class _ReminderAlertOptionsState extends State<ReminderAlertOptions> {
  final SoundPreviewPlayer _preview = SoundPreviewPlayer();
  String? _playing;

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  String get _effectiveSound =>
      ReminderSounds.resolve(widget.soundId ?? ReminderSounds.defaultFor(widget.mode));

  Future<void> _togglePreview(String id) async {
    if (_playing == id) {
      await _preview.stop();
      if (mounted) setState(() => _playing = null);
      return;
    }
    setState(() => _playing = id);
    try {
      await _preview.play(id);
    } catch (_) {
      // A device with no audio output, or a codec problem, must not break the
      // editor; the preview simply does nothing.
      if (mounted) setState(() => _playing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selected = _effectiveSound;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ALERT TYPE',
            style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: palette.textSecondary)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<AlertMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: AlertMode.notification,
                icon: Icon(Icons.notifications_none, size: 18),
                label: Text('Notification'),
              ),
              ButtonSegment(
                value: AlertMode.alarm,
                icon: Icon(Icons.alarm, size: 18),
                label: Text('Alarm'),
              ),
            ],
            selected: {widget.mode},
            onSelectionChanged: (set) {
              // Switching mode drops an explicit sound the new mode may not
              // suit: a chosen chime should not silently become an alarm's tone.
              widget.onChanged(set.first, null, widget.vibrate);
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(describeAlertMode(widget.mode),
            style: TextStyle(fontSize: 12, height: 1.35, color: palette.textSecondary)),
        const SizedBox(height: 18),
        Text('SOUND',
            style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: palette.textSecondary)),
        const SizedBox(height: 4),
        for (final id in ReminderSounds.idsFor())
          _SoundRow(
            id: id,
            selected: id == selected,
            playing: _playing == id,
            // Only sounds the app itself holds can be previewed. The system
            // sound belongs to the OS and silence has nothing to play.
            canPreview: ReminderSounds.byId(id) != null,
            onSelect: () => widget.onChanged(widget.mode, id, widget.vibrate),
            onPreview: () => _togglePreview(id),
          ),
        if (!ReminderSounds.supportsBundledSounds())
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              'Custom sounds are only available on Android for now. On this '
              'device the system sound or silence are the choices that work.',
              style: TextStyle(fontSize: 11.5, height: 1.35, color: palette.textSecondary),
            ),
          ),
        if (supportsVibrationChoice())
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vibrate'),
            value: widget.vibrate ?? widget.defaultVibrate,
            onChanged: (v) => widget.onChanged(widget.mode, widget.soundId, v),
          ),
      ],
    );
  }
}

class _SoundRow extends StatelessWidget {
  const _SoundRow({
    required this.id,
    required this.selected,
    required this.playing,
    required this.canPreview,
    required this.onSelect,
    required this.onPreview,
  });

  final String id;
  final bool selected;
  final bool playing;
  final bool canPreview;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        // A comfortable touch target for the whole row.
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppColors.primary : palette.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                ReminderSounds.labelFor(id),
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: palette.textPrimary,
                ),
              ),
            ),
            if (canPreview)
              IconButton(
                tooltip: playing ? 'Stop' : 'Preview ${ReminderSounds.labelFor(id)}',
                icon: Icon(playing ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                color: AppColors.primary,
                onPressed: onPreview,
              ),
          ],
        ),
      ),
    );
  }
}

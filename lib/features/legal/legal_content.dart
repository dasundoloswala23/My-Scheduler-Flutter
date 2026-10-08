import '../../app/app_info.dart';

/// One headed block of a legal page.
class LegalSection {
  const LegalSection(this.heading, this.body);
  final String heading;
  final String body;
}

/// When the wording below last changed. Update it with the text.
const String kLegalUpdated = 'October 2026';

/// What the app actually does with data. Each statement here describes
/// behaviour that exists in the code; keep it that way when the app changes.
const List<LegalSection> kPrivacySections = [
  LegalSection(
    'Who this applies to',
    '$kAppName is a personal planner: boards, tasks, calendar, notes, reminders '
        'and project flows. This policy explains what it stores and why.',
  ),
  LegalSection(
    'What we store',
    'Your sign-in details (an email address, or the identity returned by Google '
        'or Apple), your display name, and everything you create in the app: '
        'tasks, subtasks, boards, lists, categories, notes, reminders, project '
        'flows, holidays you add, your settings, and files you attach to tasks.',
  ),
  LegalSection(
    'Where it is stored',
    'Your data is stored in Google Firebase: Authentication for sign-in, Cloud '
        'Firestore for your planner data, and Cloud Storage for attached files. '
        'Access rules restrict each account to its own data. Reminders and alarms '
        'are scheduled on your own device and are not sent through any other service.',
  ),
  LegalSection(
    'What we do not do',
    'We do not sell your data, show advertising, or use your tasks for '
        'advertising or profiling. The app does not include third-party '
        'analytics or advertising SDKs.',
  ),
  LegalSection(
    'Permissions',
    'Notifications (and, on Android, exact alarms and full-screen alerts) are '
        'used only to remind you about your own tasks. You can turn them off in '
        'Settings or in your device settings. The app asks for access to files or '
        'photos only when you choose to attach one.',
  ),
  LegalSection(
    'Keeping and deleting your data',
    'Your data is kept until you delete it. Settings, then Delete account, removes '
        'your tasks, boards, notes, flows, attachments and sign-in from our '
        'servers and clears reminders scheduled on that device. Deletion cannot '
        'be undone. Copies may remain briefly in routine backups operated by '
        'the hosting provider.',
  ),
  LegalSection(
    'Security',
    'Data is sent over encrypted connections and protected by account-based '
        'access rules. No online service can promise perfect security, so keep '
        'your password private and use a strong one.',
  ),
  LegalSection(
    'Children',
    'The app is not directed to children under 13.',
  ),
  LegalSection(
    'Changes',
    'If this policy changes, the new text and its date will appear here.',
  ),
  LegalSection(
    'Contact',
    'Questions or requests about your data can be sent to the developer through '
        "the contact details on this app's store listing.",
  ),
];

const List<LegalSection> kTermsSections = [
  LegalSection(
    'Using the app',
    'By creating an account or using $kAppName you agree to these terms. '
        'Use the app lawfully and only for your own planning.',
  ),
  LegalSection(
    'Your account',
    'You are responsible for keeping your sign-in details private and for '
        'activity under your account. Tell us if you believe it was accessed '
        'without your permission.',
  ),
  LegalSection(
    'Your content',
    'Everything you put in the app remains yours. You give us permission only '
        'to store and display it to you so the app can work. Do not upload '
        'content you do not have the right to use.',
  ),
  LegalSection(
    'Reminders and availability',
    'Reminders depend on your device, its operating system settings (battery '
        'optimisation, Do Not Disturb, notification permission) and your '
        'network. They may be delayed or missed, so do not rely on the app as '
        'the only way to remember anything safety-critical, time-critical or '
        'legal.',
  ),
  LegalSection(
    'Backups',
    'Keep your own copy of anything important. We take care with your data but '
        'cannot guarantee that it will never be lost or unavailable.',
  ),
  LegalSection(
    'Ending your use',
    'You can stop at any time and delete your account in Settings. We may '
        'suspend accounts that abuse the service.',
  ),
  LegalSection(
    'Liability',
    'The app is provided as is. To the extent the law allows, we are not '
        'liable for indirect or consequential loss arising from its use.',
  ),
  LegalSection(
    'Changes',
    'These terms may be updated; continuing to use the app after a change '
        'means you accept it.',
  ),
];

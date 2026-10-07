/// The version shown to the user.
///
/// Android, iOS, macOS, Windows and web all take their version from the
/// `version:` line in `pubspec.yaml`. Dart code cannot read that at runtime
/// without a plugin, so this constant mirrors it and is the single place the
/// UI reads from.
///
/// Keep it in step with `pubspec.yaml` when bumping a release.
const String kAppVersion = '1.1.0';

/// The product name used in the UI. The platform bundles carry their own copy
/// in their manifests.
const String kAppName = 'My Scheduler App';

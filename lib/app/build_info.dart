import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/updates/releases.dart';

/// What this build of the app is. The release workflow gives it the version
/// from the tag and the GitHub repository it is published in
/// (`--dart-define`); a build made any other way, such as `flutter run`, has
/// neither, and does not look for updates.
class BuildInfo {
  const BuildInfo({this.version = '', this.repository = ''});

  /// "1.2.0" or "1.2.0-beta.1"; empty in a development build.
  final String version;

  /// "owner/name" on GitHub; empty in a development build.
  final String repository;

  bool get isRelease => Version.tryParse(version) != null;
}

final buildInfoProvider = Provider<BuildInfo>(
  (ref) => const BuildInfo(
    version: String.fromEnvironment('VIDCTRL_VERSION'),
    repository: String.fromEnvironment('VIDCTRL_REPOSITORY'),
  ),
);

/// Where newer versions are looked for; null in a build that does not know
/// its own version or where it is published. Tests replace it.
final releaseSourceProvider = Provider<ReleaseSource?>((ref) {
  final build = ref.watch(buildInfoProvider);
  if (!build.isRelease || build.repository.isEmpty) return null;
  return GitHubReleases(
    build.repository,
    userAgent: 'VidCtrl/${build.version}',
  );
});

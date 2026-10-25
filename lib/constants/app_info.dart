import 'package:flutter/foundation.dart';
import 'package:mornye/utils/desktop_platform.dart';

class AppInfo {
  static const String version = '5.2.6';
  static const String buildNumber = '165';

  static const String gitCommit = String.fromEnvironment('GIT_COMMIT');
  static String get shortGitCommit =>
      gitCommit.length > 8 ? gitCommit.substring(0, 8) : gitCommit;

  /// The version shown to people; desktop builds are still in beta.
  static String get displayVersion => versionLabel();

  @visibleForTesting
  static String versionLabel({bool debug = kDebugMode, bool? desktop}) {
    if (debug) return 'Internal';
    return desktop ?? isDesktopPlatform ? '$version (beta)' : version;
  }

  static const String appName = 'MornieO';
  static const String license = 'LGPL-3.0-only';
  static const String copyright = '© 2026 MornieO contributors';

  static const String mobileAuthor = 'Aloevera8194';

  static const String githubRepo = 'Aloevera8194/MornieO';
  static const String githubUrl = 'https://github.com/$githubRepo';

  /// Desktop packages are published here; the source stays in [githubRepo].
  static const String desktopGithubRepo = 'Aloevera8194/MornieO';
  static const String remoteConfigApiUrl = '';

}

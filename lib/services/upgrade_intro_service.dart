import 'package:shared_preferences/shared_preferences.dart';

/// Separate from settings migrations: migrating preferences must not consume
/// the upgrade introduction before the user has actually seen it.
class UpgradeIntroService {
  /// The release the tour describes; a new key shows it once again.
  static const tourVersion = '5.2';
  static const _seenKey = 'upgrade_intro_5_2_seen';

  static bool shouldShow(
    SharedPreferences preferences, {
    required String version,
    required bool existingInstallation,
  }) {
    final parts = version.split('.');
    final major = int.tryParse(parts.first);
    final minor = parts.length > 1 ? int.tryParse(parts[1]) : null;
    return major == 5 &&
        minor != null &&
        minor >= 2 &&
        existingInstallation &&
        !(preferences.getBool(_seenKey) ?? false);
  }

  static Future<void> markSeen(SharedPreferences preferences) async {
    await preferences.setBool(_seenKey, true);
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/app_crash_report.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/logger.dart';

final appCrashProvider =
    AsyncNotifierProvider<AppCrashNotifier, AppCrashReport?>(
      AppCrashNotifier.new,
    );

class AppCrashNotifier extends AsyncNotifier<AppCrashReport?> {
  @override
  Future<AppCrashReport?> build() async {
    try {
      final report = await PlatformBridge.getPendingAppCrash();
      return report == null ? null : AppCrashReport.fromMap(report);
    } catch (error) {
      AppLogger('AppCrash').e('Could not recover crash report: $error');
      return null;
    }
  }

  Future<void> dismiss(String id) async {
    await PlatformBridge.dismissAppCrash(id);
    if (ref.mounted && state.value?.id == id) {
      state = const AsyncData(null);
    }
  }
}

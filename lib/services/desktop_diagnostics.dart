import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:mornye/constants/app_info.dart';
import 'package:mornye/utils/desktop_platform.dart';
import 'package:mornye/utils/logger.dart';

/// Desktop crash and log handling (desktop design 6.6), without telemetry:
/// rotating log files in `<app support>/logs`, a "session running" marker
/// that reveals an unclean exit on the next launch, and the crash report the
/// existing crash banner shows (the Android `AppCrashReporter` contract:
/// `getPendingAppCrash`, `getLatestAppCrash`, `markAppCrashShown`,
/// `dismissAppCrash`, `recordAppRuntimeError`). The Rust backend's panic hook
/// writes `rust-panic.log` into the same folder.
class DesktopDiagnostics {
  DesktopDiagnostics({
    required this.directory,
    int? processId,
    DateTime Function()? now,
    this.maxLogBytes = 1024 * 1024,
    this.keptLogFiles = 3,
  }) : _pid = processId ?? pid,
       _now = now ?? DateTime.now;

  static DesktopDiagnostics? _instance;

  /// The running app's diagnostics; null on mobile and before [initialize].
  static DesktopDiagnostics? get instance => _instance;

  @visibleForTesting
  static set debugInstance(DesktopDiagnostics? value) => _instance = value;

  static const logFileName = 'mornye.log';
  static const panicLogFileName = 'rust-panic.log';
  static const _markerFileName = 'session.running';
  static const _reportFileName = 'crash-report.json';
  static const _runtimeErrorFileName = 'last-runtime-error.json';
  static const _recentLogLines = 80;
  static const _panicTailBytes = 16 * 1024;

  final Directory directory;
  final int maxLogBytes;
  final int keptLogFiles;
  final int _pid;
  final DateTime Function() _now;
  RandomAccessFile? _log;
  int _logBytes = 0;
  DateTime? _sessionStart;
  AppLifecycleListener? _lifecycle;
  Timer? _markerRestore;

  File get logFile => File(p.join(directory.path, logFileName));
  File get _marker => File(p.join(directory.path, _markerFileName));
  File get _report => File(p.join(directory.path, _reportFileName));
  File get _runtimeError => File(p.join(directory.path, _runtimeErrorFileName));
  File get _panicLog => File(p.join(directory.path, panicLogFileName));

  /// Desktop startup: detects an unclean previous exit, starts this
  /// session, mirrors buffered log entries into the log file, and clears the
  /// marker when the app is asked to quit.
  static Future<DesktopDiagnostics?> initialize() async {
    if (!isDesktopPlatform) return null;
    if (_instance != null) return _instance;
    try {
      final support = await getApplicationSupportDirectory();
      final diagnostics = DesktopDiagnostics(
        directory: Directory(p.join(support.path, 'logs')),
      );
      diagnostics.beginSession(device: _deviceDescription());
      LogBuffer.fileSink = diagnostics.writeEntry;
      diagnostics._lifecycle = AppLifecycleListener(
        onExitRequested: () async {
          diagnostics.endSession();
          // Another listener may cancel the quit; restore the marker then.
          diagnostics._markerRestore = Timer(
            const Duration(seconds: 3),
            diagnostics._writeMarker,
          );
          return AppExitResponse.exit;
        },
      );
      return _instance = diagnostics;
    } catch (error) {
      debugPrint('Desktop diagnostics unavailable: $error');
      return null;
    }
  }

  static String _deviceDescription() =>
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

  /// Turns a leftover marker from another process into a crash report, then
  /// writes this session's marker. A marker from this process (a debug hot
  /// restart) is not a crash.
  void beginSession({required String device}) {
    directory.createSync(recursive: true);
    final start = _now();
    _sessionStart = start;
    final previous = _readJson(_marker);
    if (previous != null && previous['pid'] != _pid) {
      _writeJson(_report, _buildReport(previous, device));
    }
    if (_runtimeError.existsSync() && previous?['pid'] != _pid) {
      _runtimeError.deleteSync();
    }
    _writeMarker();
    _openLog();
  }

  /// A clean quit: the next launch reports nothing.
  void endSession() {
    _markerRestore?.cancel();
    try {
      if (_marker.existsSync()) _marker.deleteSync();
    } on FileSystemException {
      // The next launch then shows a report; never block quitting.
    }
    try {
      _log?.flushSync();
    } on FileSystemException {
      // Same as above.
    }
  }

  @visibleForTesting
  bool get sessionMarkerExists => _marker.existsSync();

  void _writeMarker() {
    _writeJson(_marker, {
      'pid': _pid,
      'started_at': (_sessionStart ?? _now()).millisecondsSinceEpoch,
      'version': '${AppInfo.version} (${AppInfo.buildNumber})',
    });
  }

  Map<String, Object?> _buildReport(
    Map<String, dynamic> previous,
    String device,
  ) {
    final startedAt = (previous['started_at'] as num?)?.toInt() ?? 0;
    final lastActivity = [
      _modified(logFile),
      _modified(_panicLog),
      DateTime.fromMillisecondsSinceEpoch(startedAt),
    ].whereType<DateTime>().reduce((a, b) => a.isAfter(b) ? a : b);
    final panicModified = _modified(_panicLog);
    final panic =
        panicModified != null &&
            panicModified.millisecondsSinceEpoch >= startedAt
        ? _tail(_panicLog, _panicTailBytes)
        : '';
    final runtime = _readJson(_runtimeError);
    return {
      'id': 'desktop-$startedAt',
      'timestamp': lastActivity.millisecondsSinceEpoch,
      'reason': panic.isEmpty ? 'Unclean exit' : 'Rust panic',
      'description': panic.isEmpty
          ? 'The previous session did not quit normally. It may have '
                'crashed, been force quit, or lost power.'
          : panic
                .split('\n')
                .lastWhere(
                  (line) => line.contains('panicked at'),
                  orElse: () => 'Rust panic',
                )
                .trim(),
      'version': previous['version']?.toString() ?? '',
      'device': device,
      'trace': panic.isEmpty
          ? 'No Rust panic was recorded for this session.'
          : panic,
      'runtime_error': runtime?['error']?.toString() ?? '',
      'runtime_stack': runtime?['stack']?.toString() ?? '',
      'recent_logs': _tailLines(logFile, _recentLogLines),
      'shown': false,
    };
  }

  Map<String, dynamic>? pendingCrash() {
    final report = _readJson(_report);
    if (report == null || report['shown'] == true) return null;
    return report;
  }

  Map<String, dynamic>? latestCrash() => _readJson(_report);

  void markShown(String id) {
    final report = _readJson(_report);
    if (report == null || report['id'] != id) return;
    _writeJson(_report, {...report, 'shown': true});
  }

  void dismiss(String id) {
    final report = _readJson(_report);
    if (report != null && report['id'] == id) _report.deleteSync();
  }

  /// Context for a later unclean exit, like Android's runtime error record.
  void recordRuntimeError({
    required String error,
    required String stack,
    required String logs,
  }) {
    _writeJson(_runtimeError, {
      'error': error,
      'stack': stack,
      'logs': logs,
      'timestamp': _now().millisecondsSinceEpoch,
    });
    _writeLine('${_now().toIso8601String()} [FATAL] [Runtime] $error\n$stack');
  }

  /// [LogBuffer.fileSink]: entries are already redacted and filtered by the
  /// user's logging preference.
  void writeEntry(LogEntry entry) {
    final native = entry.isFromNative ? ' [Native]' : '';
    final error = entry.error == null ? '' : ' | ${entry.error}';
    _writeLine(
      '${entry.timestamp.toIso8601String()} [${entry.level}]$native '
      '[${entry.tag}] ${entry.message}$error',
    );
  }

  void _openLog() {
    try {
      _log = logFile.openSync(mode: FileMode.append);
      _logBytes = _log!.lengthSync();
    } on FileSystemException catch (error) {
      debugPrint('Cannot open desktop log file: $error');
    }
  }

  void _writeLine(String line) {
    final log = _log;
    if (log == null) return;
    try {
      final bytes = utf8.encode('$line\n');
      if (_logBytes > 0 && _logBytes + bytes.length > maxLogBytes) {
        _rotate();
      }
      // Unbuffered: lines reach the OS before a later crash.
      _log!.writeFromSync(bytes);
      _logBytes += bytes.length;
    } on FileSystemException {
      // Logging must never fail the caller.
    }
  }

  /// `mornye.log` becomes `mornye.1.log`; the oldest file is removed.
  void _rotate() {
    _log?.closeSync();
    _log = null;
    String rotated(int index) =>
        p.join(directory.path, index == 0 ? logFileName : 'mornye.$index.log');
    final oldest = File(rotated(keptLogFiles - 1));
    if (oldest.existsSync()) oldest.deleteSync();
    for (var index = keptLogFiles - 2; index >= 0; index--) {
      final file = File(rotated(index));
      if (file.existsSync()) file.renameSync(rotated(index + 1));
    }
    _openLog();
  }

  @visibleForTesting
  Future<void> close() async {
    _markerRestore?.cancel();
    _lifecycle?.dispose();
    await _log?.close();
    _log = null;
  }

  static DateTime? _modified(File file) {
    try {
      return file.existsSync() ? file.lastModifiedSync() : null;
    } on FileSystemException {
      return null;
    }
  }

  static String _tail(File file, int maxBytes) {
    try {
      final handle = file.openSync();
      try {
        final length = handle.lengthSync();
        final start = length > maxBytes ? length - maxBytes : 0;
        handle.setPositionSync(start);
        return utf8.decode(
          handle.readSync(length - start),
          allowMalformed: true,
        );
      } finally {
        handle.closeSync();
      }
    } on FileSystemException {
      return '';
    }
  }

  static String _tailLines(File file, int lines) {
    final text = _tail(file, 64 * 1024).trimRight();
    if (text.isEmpty) return '';
    final all = text.split('\n');
    return all.skip(all.length > lines ? all.length - lines : 0).join('\n');
  }

  static Map<String, dynamic>? _readJson(File file) {
    try {
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }

  static void _writeJson(File file, Map<String, Object?> value) {
    try {
      final staging = File('${file.path}.tmp');
      staging.writeAsStringSync(jsonEncode(value), flush: true);
      staging.renameSync(file.path);
    } on FileSystemException {
      // Diagnostics are best effort.
    }
  }
}

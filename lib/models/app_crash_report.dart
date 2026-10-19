import 'package:spotiflac_android/utils/logger.dart';

class AppCrashReport {
  AppCrashReport.fromMap(Map<String, dynamic> values)
    : id = values['id'] as String,
      timestamp = DateTime.fromMillisecondsSinceEpoch(
        (values['timestamp'] as num).toInt(),
      ),
      reason = redactDiagnosticText(values['reason'] as String? ?? ''),
      description = redactDiagnosticText(
        values['description'] as String? ?? '',
      ),
      report = _formatReport(values);

  final String id;
  final DateTime timestamp;
  final String reason;
  final String description;
  final String report;

  static String _formatReport(Map<String, dynamic> values) {
    final report = StringBuffer('SpotiFLAC Mobile crash report\n');
    report.writeln(
      'Crash time: ${DateTime.fromMillisecondsSinceEpoch((values['timestamp'] as num).toInt()).toUtc().toIso8601String()}',
    );
    for (final (key, label) in const [
      ('version', 'App version'),
      ('device', 'Device'),
      ('android', 'Android'),
      ('sdk', 'Android SDK'),
      ('abis', 'ABIs'),
      ('reason', 'Exit reason'),
      ('reason_code', 'Android exit reason code'),
      ('description', 'Original error'),
      ('status', 'Exit status / signal'),
      ('pss_kb', 'Last sampled PSS (KB)'),
      ('rss_kb', 'Last sampled RSS (KB)'),
    ]) {
      final value = values[key]?.toString() ?? '';
      if (value.isNotEmpty) report.writeln('$label: $value');
    }
    final trace = values['trace'] as String? ?? '';
    report.writeln(
      '\nCrash stack trace:\n${trace.isEmpty ? 'Android did not provide a stack trace for this process exit.' : trace}',
    );
    for (final (key, label) in const [
      ('trace_error', 'Trace availability'),
      (
        'runtime_error',
        'Last unhandled Dart/Flutter error before exit (context)',
      ),
      ('runtime_stack', 'Dart/Flutter stack trace'),
      ('recent_logs', 'Recent app logs before that error'),
    ]) {
      final value = values[key] as String? ?? '';
      if (value.isNotEmpty) report.writeln('\n$label:\n$value');
    }
    return redactDiagnosticText(report.toString());
  }
}

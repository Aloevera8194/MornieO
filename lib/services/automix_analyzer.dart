import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mornye/services/audio_analysis_jobs.dart';
import 'package:mornye/services/automix_analysis.dart';
import 'package:mornye/services/ffmpeg_support.dart';
import 'package:mornye/services/platform_bridge.dart';
import 'package:mornye/utils/logger.dart';

/// Only short head/tail windows are decoded. Summaries are bounded in memory;
/// raw PCM is deleted immediately and is never added to the user's library.
class AutoMixAnalyzer {
  static const windowSeconds = 24.0;
  final _log = AppLogger('AutoMixAnalyzer');
  final _cache = <String, AutoMixBeatGrid>{};
  final _jobs = AudioAnalysisJobs<bool>(
    start: (arguments) async {
      final session = await FFmpegExecution.start(arguments);
      final id = session.id;
      final timeout = Timer(const Duration(seconds: 20), () {
        unawaited(FFmpegExecution.cancel(id));
      });
      return (
        id: id,
        completed: session.completed
            .then((result) => result.success)
            .whenComplete(timeout.cancel),
      );
    },
    cancel: FFmpegExecution.cancel,
  );
  int _generation = 0;
  final _nativeRequests = <String>{};

  void _cancelNativeRequests() {
    for (final request in _nativeRequests) {
      unawaited(_cancelNativeRequest(request));
    }
  }

  Future<void> _cancelNativeRequest(String request) async {
    try {
      await PlatformBridge.cancelNativeDataJob(request);
    } catch (_) {
      // Completion still owns temp cleanup; unsupported hosts have no lease.
    }
  }

  void cancel() {
    _generation++;
    _jobs.invalidate();
    _cancelNativeRequests();
  }

  void dispose() {
    _generation++;
    _jobs.dispose();
    _cancelNativeRequests();
    _cache.clear();
  }

  Future<AutoMixBeatGrid?> analyze(String path, {double offset = 0}) async {
    final generation = _generation;
    Directory? work;
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file) {
        _log.w('AutoMix beat analysis unavailable: input is not a file');
        return null;
      }
      final key =
          '$path:${stat.size}:${stat.modified.microsecondsSinceEpoch}:$offset';
      final cached = _cache.remove(key);
      if (cached != null) {
        _cache[key] = cached;
        return cached;
      }
      if (generation != _generation) return null;
      final temp = await getTemporaryDirectory();
      work = await Directory(temp.path).createTemp('automix-');
      final output = File('${work.path}/window.pcm');
      final success = await _jobs.run([
        '-hide_banner',
        '-loglevel',
        'error',
        '-nostdin',
        '-y',
        '-threads',
        '1',
        '-filter_threads',
        '1',
        '-ss',
        offset.toStringAsFixed(6),
        '-i',
        path,
        '-t',
        '$windowSeconds',
        '-vn',
        '-sn',
        '-dn',
        '-ac',
        '1',
        '-ar',
        '11025',
        '-c:a',
        'pcm_s16le',
        '-f',
        's16le',
        output.path,
      ]);
      if (generation != _generation) return null;
      if (!success) {
        _log.w('AutoMix beat analysis unavailable: native decoding failed');
        return null;
      }
      if (!await output.exists()) {
        _log.w('AutoMix beat analysis unavailable: decoded window is missing');
        return null;
      }
      if (await output.length() > 11025 * 2 * 25) {
        _log.w(
          'AutoMix beat analysis unavailable: decoded window exceeds limit',
        );
        return null;
      }
      final request = 'automix-${work.path}';
      _nativeRequests.add(request);
      late final AutoMixBeatGrid grid;
      try {
        try {
          final result = await PlatformBridge.runNativeDataJob({
            'operation': 'automix',
            'path': output.path,
          }, requestId: request);
          double field(String key) {
            final value = (result[key] as num).toDouble();
            if (!value.isFinite) throw StateError('Invalid AutoMix beat grid');
            return value;
          }

          grid = AutoMixBeatGrid(
            bpm: field('bpm'),
            phase: field('phase'),
            confidence: field('confidence'),
            firstSound: field('first_sound'),
          );
        } on MissingPluginException {
          grid = await compute(analyzeAutoMixPcm, await output.readAsBytes());
        }
      } finally {
        _nativeRequests.remove(request);
      }
      if (generation != _generation) return null;
      _cache[key] = grid;
      while (_cache.length > 16) {
        _cache.remove(_cache.keys.first);
      }
      return grid;
    } on AudioAnalysisCancelled {
      return null;
    } on Object catch (error) {
      if (generation != _generation) return null;
      // Unsupported/corrupt input must not interrupt ordinary playback.
      _log.w('AutoMix beat analysis unavailable (${error.runtimeType})');
      return null;
    } finally {
      if (work != null && await work.exists()) {
        await work.delete(recursive: true);
      }
    }
  }
}

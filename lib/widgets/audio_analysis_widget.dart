import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/services/audio_analysis_jobs.dart';
import 'package:spotiflac_android/services/audio_analysis_cache.dart';
import 'package:spotiflac_android/services/audio_analysis_ffmpeg.dart';
import 'package:spotiflac_android/services/audio_analysis_models.dart';
import 'package:spotiflac_android/services/network_audio_analysis_input.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/app_content_card.dart';
import 'package:spotiflac_android/widgets/app_progress_indicator.dart';
import 'package:spotiflac_android/widgets/app_choice_chip.dart';
import 'package:spotiflac_android/widgets/app_icon_button.dart';
import 'package:spotiflac_android/widgets/app_loading_indicator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/string_utils.dart';

export 'package:spotiflac_android/services/audio_analysis_ffmpeg.dart';
export 'package:spotiflac_android/services/audio_analysis_models.dart';

part 'audio_analysis_models.dart';
part 'audio_analysis_info_card.dart';
part 'audio_analysis_spectrogram.dart';

class AudioAnalysisCard extends StatefulWidget {
  final String filePath;
  final String? codecHint;

  const AudioAnalysisCard({super.key, required this.filePath, this.codecHint});

  @override
  State<AudioAnalysisCard> createState() => _AudioAnalysisCardState();
}

class _AudioAnalysisCardState extends State<AudioAnalysisCard> {
  AudioAnalysisData? _data;
  bool _analyzing = false;
  bool _checkingCache = true;
  String? _error;
  ui.Image? _spectrogramImage;
  int _spectrogramChannel = -1;
  bool _spectrogramChannelLoading = false;
  int _spectrogramRequestId = 0;
  String? _unsupportedCodec;
  final _networkInput = NetworkAudioAnalysisInput();
  final _analysisJobs = AudioAnalysisJobs<FFmpegSession>(
    start: (arguments) async {
      final completed = Completer<FFmpegSession>();
      final session = await FFmpegKit.executeWithArgumentsAsync(
        arguments,
        completed.complete,
      );
      final id = session.getSessionId();
      if (id == null) {
        // Never pass null to cancel: FFmpegKit interprets it as cancel-all.
        await completed.future;
        throw StateError('Analysis session has no ID');
      }
      return (id: id, completed: completed.future);
    },
    cancel: (id) => FFmpegKit.cancel(id),
  );

  void _checkAnalysisRequest(int requestId) {
    if (!mounted || requestId != _spectrogramRequestId) {
      throw const AudioAnalysisCancelled();
    }
  }

  final _nativeAnalysisRequests = <String>{};

  void _cancelNativeAnalysis() {
    for (final request in _nativeAnalysisRequests) {
      unawaited(_cancelNativeAnalysisRequest(request));
    }
  }

  Future<void> _cancelNativeAnalysisRequest(String request) async {
    try {
      await PlatformBridge.cancelNativeDataJob(request);
    } catch (_) {
      // Await the owned worker before temp cleanup even if cancellation fails.
    }
  }

  static const _supportedExtensions = {
    '.flac',
    '.mp3',
    '.m4a',
    '.mp4',
    '.aac',
    '.ac3',
    '.eac3',
    '.opus',
    '.ogg',
    '.wav',
    '.wma',
    '.mka',
    '.wv',
    '.ape',
    '.tta',
    '.aif',
    '.aiff',
  };

  bool get _isSupported {
    final lower = widget.filePath.toLowerCase();
    return _supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  @override
  void initState() {
    super.initState();
    _unsupportedCodec = unsupportedAudioAnalysisCodecLabel(widget.codecHint);
    if (_isSupported) {
      if (_unsupportedCodec == null) {
        _tryLoadFromCache();
      } else {
        _checkingCache = false;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AudioAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath == widget.filePath &&
        oldWidget.codecHint == widget.codecHint) {
      return;
    }

    _spectrogramRequestId++;
    _analysisJobs.invalidate();
    _networkInput.cancel();
    _cancelNativeAnalysis();
    _spectrogramImage?.dispose();
    _spectrogramImage = null;
    _spectrogramChannel = -1;
    _spectrogramChannelLoading = false;
    _data = null;
    _error = null;
    _analyzing = false;
    _unsupportedCodec = unsupportedAudioAnalysisCodecLabel(widget.codecHint);
    _checkingCache = _isSupported && _unsupportedCodec == null;

    if (_checkingCache) {
      unawaited(_tryLoadFromCache());
    }
  }

  @override
  void dispose() {
    _spectrogramRequestId++;
    _analysisJobs.dispose();
    _networkInput.cancel();
    _cancelNativeAnalysis();
    _spectrogramImage?.dispose();
    super.dispose();
  }

  Future<void> _tryLoadFromCache() async {
    final expectedPath = widget.filePath;
    final requestId = _spectrogramRequestId;
    final releaseCache = _cacheBudget.retain(_cacheKey(expectedPath));
    bool isCurrentRequest() =>
        mounted &&
        widget.filePath == expectedPath &&
        requestId == _spectrogramRequestId;

    try {
      final cached = await _loadFromCache(expectedPath);
      if (cached != null && isCurrentRequest()) {
        final unsupported = unsupportedAudioAnalysisCodecLabel(cached.codec);
        if (unsupported != null) {
          await _clearCache(expectedPath);
          if (isCurrentRequest()) {
            setState(() {
              _unsupportedCodec = unsupported;
              _checkingCache = false;
            });
          }
          return;
        }
        setState(() {
          _data = cached;
          _checkingCache = false;
        });
        var image = await _loadSpectrogramFromCache(
          expectedPath,
          channel: _spectrogramChannel,
        );
        if (image == null &&
            NetworkAudioAnalysisInput.isNetwork(expectedPath)) {
          return; // Opening metadata must not fetch the complete remote audio.
        }
        image ??= await _generateAndCacheSpectrogram(
          filePath: expectedPath,
          analysisData: cached,
          requestId: requestId,
        );
        if (isCurrentRequest()) {
          setState(() {
            _spectrogramImage?.dispose();
            _spectrogramImage = image;
          });
        } else {
          image.dispose();
        }
        return;
      }
    } catch (_) {
      // Missing or unreadable cache entries fall back to the Analyze action.
    } finally {
      releaseCache();
      unawaited(_trimCache());
    }
    if (isCurrentRequest()) {
      setState(() => _checkingCache = false);
    }
  }

  Future<ui.Image> _generateAndCacheSpectrogram({
    String? filePath,
    AudioAnalysisData? analysisData,
    required int requestId,
  }) async {
    _checkAnalysisRequest(requestId);
    final sourcePath = filePath ?? widget.filePath;
    final data = analysisData ?? _data;
    final channel = _spectrogramChannel;
    final artifact = await _generateSpectrogramForFile(
      sourcePath,
      requestId: requestId,
      channel: channel,
      durationSeconds: data?.duration,
      sampleRate: data?.sampleRate,
      channels: data?.channels,
    );
    await _saveSpectrogramToCache(sourcePath, artifact.image, channel: channel);
    return artifact.image;
  }

  Future<void> _analyze({bool forceRefresh = false}) async {
    if (_analyzing) return;
    final sourcePath = widget.filePath;
    final releaseCache = _cacheBudget.retain(_cacheKey(sourcePath));
    final requestId = ++_spectrogramRequestId;
    _analysisJobs.invalidate();
    _networkInput.cancel();
    _cancelNativeAnalysis();
    setState(() {
      _analyzing = true;
      _spectrogramChannelLoading = false;
      _error = null;
      if (forceRefresh) {
        _spectrogramImage?.dispose();
        _spectrogramImage = null;
        _data = null;
        _spectrogramChannel = -1;
      }
    });

    try {
      if (forceRefresh) {
        await _clearCache(sourcePath);
      }

      final cached = forceRefresh ? null : await _loadFromCache(sourcePath);
      _checkAnalysisRequest(requestId);
      AudioAnalysisData data;
      ui.Image? image;

      if (cached != null) {
        final unsupported = unsupportedAudioAnalysisCodecLabel(cached.codec);
        if (unsupported != null) {
          throw UnsupportedAudioAnalysisCodecException(unsupported);
        }
        data = cached;
        image = await _loadSpectrogramFromCache(
          sourcePath,
          channel: _spectrogramChannel,
        );
      } else {
        final result = await _runAnalysis(sourcePath, requestId);
        data = result.data;
        image = result.spectrogramImage;
        await _saveToCache(sourcePath, data);
        await _saveSpectrogramToCache(
          sourcePath,
          image,
          channel: _spectrogramChannel,
        );
      }

      image ??= await _generateAndCacheSpectrogram(
        filePath: sourcePath,
        analysisData: data,
        requestId: requestId,
      );

      if (mounted && requestId == _spectrogramRequestId) {
        setState(() {
          _data = data;
          _spectrogramImage?.dispose();
          _spectrogramImage = image;
          _analyzing = false;
        });
      } else {
        image.dispose();
      }
    } on AudioAnalysisCancelled {
      // A new file/request owns the state; cancelled native work is cleaned up.
    } on UnsupportedAudioAnalysisCodecException catch (e) {
      if (mounted && requestId == _spectrogramRequestId) {
        setState(() {
          _unsupportedCodec = e.codecLabel;
          _error = null;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted && requestId == _spectrogramRequestId) {
        setState(() {
          _error = context.friendlyError(e);
          _analyzing = false;
        });
      }
    } finally {
      releaseCache();
      unawaited(_trimCache());
    }
  }

  static Future<void> _clearCache(String filePath) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final jsonFile = File('${dir.path}/$key.json');
      if (await jsonFile.exists()) {
        await jsonFile.delete();
      }
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.replaceAll('\\', '/').split('/').last;
        final isCombined = name == '$key.png';
        final isChannel = name.startsWith('${key}_ch') && name.endsWith('.png');
        if (isCombined || isChannel) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  static String _cacheKey(String filePath) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(filePath)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  static Future<Directory> _cacheDir() async {
    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory('${appSupport.path}/audio_analysis_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static final _cacheBudget = AudioAnalysisCache();

  static Future<void> _trimCache() async {
    try {
      await _cacheBudget.trim(await _cacheDir());
    } catch (_) {
      // Cache maintenance must not interrupt the selected track's analysis.
    }
  }

  Future<AudioAnalysisData?> _loadFromCache(String filePath) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final file = File('${dir.path}/$key.json');
      if (!await file.exists()) return null;

      final json = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      if (json['cacheVersion'] != AudioAnalysisData.cacheVersion) {
        return null;
      }
      final cachedSize = json['fileSize'] as int;

      if (NetworkAudioAnalysisInput.isNetwork(filePath)) {
        final currentSize = await _networkInput.length(filePath);
        if (currentSize <= 0 || currentSize != cachedSize) return null;
      } else if (!filePath.startsWith('content://')) {
        final currentSize = await File(filePath).length();
        if (currentSize != cachedSize) return null;
      } else {
        final stat = await PlatformBridge.safStat(filePath);
        final currentSize = (stat['size'] as num?)?.toInt() ?? 0;
        if (currentSize > 0 && currentSize != cachedSize) return null;
      }

      final data = AudioAnalysisData.fromJson(json);
      await file.setLastModified(DateTime.now());
      return data;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToCache(
    String filePath,
    AudioAnalysisData data,
  ) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final file = File('${dir.path}/$key.json');
      await file.writeAsString(jsonEncode(data.toJson()));
    } catch (_) {}
  }

  static Future<void> _saveSpectrogramToCache(
    String filePath,
    ui.Image image, {
    required int channel,
  }) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final file = File(
          '${dir.path}/${_spectrogramCacheFileName(key, channel)}',
        );
        await file.writeAsBytes(byteData.buffer.asUint8List());
        await _cacheBudget.trim(dir);
      }
    } catch (_) {}
  }

  static String _spectrogramCacheFileName(String key, int channel) =>
      channel < 0 ? '$key.png' : '${key}_ch$channel.png';

  static Future<ui.Image?> _loadSpectrogramFromCache(
    String filePath, {
    required int channel,
  }) async {
    try {
      final dir = await _cacheDir();
      final key = _cacheKey(filePath);
      final file = File(
        '${dir.path}/${_spectrogramCacheFileName(key, channel)}',
      );
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, completer.complete);
      return await completer.future;
    } catch (_) {
      return null;
    }
  }

  Future<_AudioAnalysisRunResult> _runAnalysis(
    String filePath,
    int requestId, {
    String? sourcePath,
  }) async {
    _checkAnalysisRequest(requestId);
    if (NetworkAudioAnalysisInput.isNetwork(filePath)) {
      return _networkInput.withFile(
        filePath,
        (path) => _runAnalysis(path, requestId, sourcePath: filePath),
      );
    }
    String workingPath = filePath;
    String? tempCopy;
    if (filePath.startsWith('content://')) {
      tempCopy = await PlatformBridge.copyContentUriToTemp(filePath);
      if (tempCopy == null) {
        throw Exception('Failed to copy SAF file for analysis');
      }
      workingPath = tempCopy;
    }

    try {
      _checkAnalysisRequest(requestId);
      final info = await _getMediaInfo(workingPath);
      _checkAnalysisRequest(requestId);
      final unsupported = unsupportedAudioAnalysisCodecLabel(info.codecName);
      if (unsupported != null) {
        throw UnsupportedAudioAnalysisCodecException(unsupported);
      }
      _GeneratedSpectrogram? spectrogram;
      try {
        final effectiveDuration = info.totalSamples > 0 && info.sampleRate > 0
            ? info.totalSamples / info.sampleRate
            : info.duration;
        spectrogram = await _generateSpectrogram(
          workingPath,
          requestId: requestId,
          channel: -1,
          includeCutoffPlane: true,
          durationSeconds: effectiveDuration,
          sampleRate: info.sampleRate,
          channels: info.channels,
        );
        _checkAnalysisRequest(requestId);
        final spectralCutoffHz = spectrogram.cutoffFrequencyHz;
        final levelMetrics = await _runFullStreamLevelAnalysis(
          workingPath,
          requestId: requestId,
          durationSeconds: effectiveDuration,
        );
        if (levelMetrics == null) {
          throw Exception('FFmpeg level analysis returned no usable metrics');
        }
        final peakAmplitude = levelMetrics.peakDb;
        final rmsLevel = levelMetrics.rmsDb;
        final dynamicRange = peakAmplitude - rmsLevel;

        return _AudioAnalysisRunResult(
          data: AudioAnalysisData(
            filePath: sourcePath ?? filePath,
            fileSize: info.fileSize,
            codec: info.codec,
            container: info.container,
            decodedSampleFormat: info.decodedSampleFormat,
            sampleRate: info.sampleRate,
            channels: info.channels,
            channelLayout: info.channelLayout,
            bitsPerSample: info.bitsPerSample,
            duration: info.duration,
            bitrate: info.bitrate,
            bitDepth: info.bitsPerSample > 0
                ? '${info.bitsPerSample}-bit'
                : 'N/A',
            dynamicRange: dynamicRange,
            peakAmplitude: peakAmplitude,
            rmsLevel: rmsLevel,
            integratedLufs: levelMetrics.integratedLufs,
            truePeakDb: levelMetrics.truePeakDb,
            clippingSamples: levelMetrics.clippingSamples,
            spectralCutoffHz: spectralCutoffHz,
            channelStats: levelMetrics.channelStats,
            totalSamples: info.totalSamples,
          ),
          spectrogramImage: spectrogram.image,
        );
      } catch (_) {
        spectrogram?.image.dispose();
        rethrow;
      }
    } finally {
      if (tempCopy != null) {
        try {
          await File(tempCopy).delete();
        } catch (_) {}
      }
    }
  }

  Future<_GeneratedSpectrogram> _generateSpectrogramForFile(
    String filePath, {
    required int requestId,
    required int channel,
    double? durationSeconds,
    int? sampleRate,
    int? channels,
  }) async {
    _checkAnalysisRequest(requestId);
    if (NetworkAudioAnalysisInput.isNetwork(filePath)) {
      return _networkInput.withFile(
        filePath,
        (path) => _generateSpectrogramForFile(
          path,
          requestId: requestId,
          channel: channel,
          durationSeconds: durationSeconds,
          sampleRate: sampleRate,
          channels: channels,
        ),
      );
    }
    String workingPath = filePath;
    String? tempCopy;
    if (filePath.startsWith('content://')) {
      tempCopy = await PlatformBridge.copyContentUriToTemp(filePath);
      if (tempCopy == null) {
        throw Exception('Failed to copy SAF file for spectrogram');
      }
      workingPath = tempCopy;
    }

    try {
      return await _generateSpectrogram(
        workingPath,
        requestId: requestId,
        channel: channel,
        durationSeconds: durationSeconds,
        sampleRate: sampleRate,
        channels: channels,
      );
    } finally {
      if (tempCopy != null) {
        try {
          await File(tempCopy).delete();
        } catch (_) {}
      }
    }
  }

  Future<_GeneratedSpectrogram> _generateSpectrogram(
    String inputPath, {
    required int requestId,
    required int channel,
    bool includeCutoffPlane = false,
    double? durationSeconds,
    int? sampleRate,
    int? channels,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final rawPath =
        '${tempDir.path}/analysis_spectrum_'
        '${DateTime.now().microsecondsSinceEpoch}_${channel + 1}.rgba';
    final cutoffPath = includeCutoffPlane ? '$rawPath.cutoff.gray' : null;

    try {
      _checkAnalysisRequest(requestId);
      final session = await _analysisJobs.run(
        buildAudioSpectrogramArguments(
          inputPath: inputPath,
          outputPath: rawPath,
          cutoffOutputPath: cutoffPath,
          channel: channel,
          durationSeconds: durationSeconds,
          sampleRate: sampleRate,
          channels: channels,
        ),
      );

      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getLogsAsString();
        throw Exception('FFmpeg spectrogram failed: $logs');
      }

      final expectedLength = audioSpectrogramWidth * audioSpectrogramHeight * 4;
      final rawBytes = await File(rawPath).readAsBytes();
      if (rawBytes.length < expectedLength) {
        throw Exception(
          'Incomplete spectrogram output '
          '(${rawBytes.length}/$expectedLength bytes)',
        );
      }
      final rgba = rawBytes.length == expectedLength
          ? rawBytes
          : Uint8List.sublistView(rawBytes, 0, expectedLength);
      double? cutoffFrequencyHz;
      if (cutoffPath != null) {
        final expectedCutoffLength =
            audioSpectralAnalysisWidth * audioSpectrogramHeight;
        final cutoffLength = await File(cutoffPath).length();
        if (cutoffLength != expectedCutoffLength) {
          throw Exception(
            'Incomplete spectral cutoff output '
            '($cutoffLength/$expectedCutoffLength bytes)',
          );
        }
        _checkAnalysisRequest(requestId);
        final nativeRequest = 'spectral-$rawPath';
        _nativeAnalysisRequests.add(nativeRequest);
        try {
          try {
            final result = await PlatformBridge.runNativeDataJob({
              'operation': 'spectral_cutoff',
              'path': cutoffPath,
              'width': audioSpectralAnalysisWidth,
              'height': audioSpectrogramHeight,
              'max_frequency': (sampleRate ?? 0) / 2,
            }, requestId: nativeRequest);
            cutoffFrequencyHz = (result['cutoff'] as num?)?.toDouble();
          } on MissingPluginException {
            cutoffFrequencyHz = await compute(
              _estimateEffectiveSpectralCutoffFileInIsolate,
              _SpectralCutoffFileParams(
                path: cutoffPath,
                width: audioSpectralAnalysisWidth,
                height: audioSpectrogramHeight,
                maxFrequencyHz: (sampleRate ?? 0) / 2,
              ),
            );
          }
        } finally {
          _nativeAnalysisRequests.remove(nativeRequest);
        }
        _checkAnalysisRequest(requestId);
      }
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        audioSpectrogramWidth,
        audioSpectrogramHeight,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return _GeneratedSpectrogram(
        image: await completer.future,
        rgba: rgba,
        cutoffFrequencyHz: cutoffFrequencyHz,
      );
    } finally {
      try {
        await File(rawPath).delete();
      } catch (_) {}
      if (cutoffPath != null) {
        try {
          await File(cutoffPath).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _changeSpectrogramChannel(int channel) async {
    final data = _data;
    if (data == null ||
        _spectrogramChannelLoading ||
        _analyzing ||
        channel == _spectrogramChannel ||
        channel < -1 ||
        channel >= data.channels) {
      return;
    }

    final previousChannel = _spectrogramChannel;
    final sourcePath = widget.filePath;
    final releaseCache = _cacheBudget.retain(_cacheKey(sourcePath));
    final requestId = ++_spectrogramRequestId;
    setState(() {
      _spectrogramChannel = channel;
      _spectrogramChannelLoading = true;
    });

    ui.Image? image;
    try {
      image = await _loadSpectrogramFromCache(sourcePath, channel: channel);
      if (image == null) {
        final artifact = await _generateSpectrogramForFile(
          sourcePath,
          requestId: requestId,
          channel: channel,
          durationSeconds: data.duration,
          sampleRate: data.sampleRate,
          channels: data.channels,
        );
        image = artifact.image;
        await _saveSpectrogramToCache(sourcePath, image, channel: channel);
      }

      if (!mounted || requestId != _spectrogramRequestId) {
        image.dispose();
        return;
      }
      setState(() {
        _spectrogramImage?.dispose();
        _spectrogramImage = image;
        _spectrogramChannelLoading = false;
      });
    } catch (_) {
      image?.dispose();
      if (mounted && requestId == _spectrogramRequestId) {
        setState(() {
          _spectrogramChannel = previousChannel;
          _spectrogramChannelLoading = false;
        });
      }
    } finally {
      releaseCache();
      unawaited(_trimCache());
    }
  }

  Future<_MediaInfo> _getMediaInfo(String filePath) async {
    final session = await FFprobeKit.getMediaInformation(filePath);
    final info = session.getMediaInformation();

    if (info == null) {
      throw Exception('Failed to get media information');
    }

    int fileSize = 0;
    try {
      fileSize = await File(filePath).length();
    } catch (_) {}

    final streams = info.getStreams();
    final audioStream = streams.firstWhere(
      (s) => s.getAllProperties()?['codec_type'] == 'audio',
      orElse: () => throw Exception('No audio stream found'),
    );

    final props = audioStream.getAllProperties() ?? {};
    final infoProps = info.getAllProperties() ?? {};
    final codecName = props['codec_name']?.toString().toLowerCase() ?? '';
    final codecLongName = props['codec_long_name']?.toString() ?? '';
    final decodedSampleFormat = props['sample_fmt']?.toString() ?? '';
    final formatName = infoProps['format_name']?.toString() ?? '';
    final formatLongName = infoProps['format_long_name']?.toString() ?? '';
    final sampleRate =
        int.tryParse(props['sample_rate']?.toString() ?? '') ?? 0;
    final channels = int.tryParse(props['channels']?.toString() ?? '') ?? 0;
    final channelLayout =
        props['channel_layout']?.toString() ??
        props['ch_layout']?.toString() ??
        '';
    final streamDuration = double.tryParse(props['duration']?.toString() ?? '');
    final containerDuration = double.tryParse(info.getDuration() ?? '');
    final duration =
        (streamDuration != null && streamDuration > 0
            ? streamDuration
            : containerDuration) ??
        0;
    final streamBitrate = int.tryParse(props['bit_rate']?.toString() ?? '');
    final containerBitrate = int.tryParse(info.getBitrate() ?? '');
    final bitrate =
        streamBitrate ??
        containerBitrate ??
        (duration > 0 && fileSize > 0 ? (fileSize * 8 / duration).round() : 0);

    final canReportStoredBitDepth = _codecHasStoredBitDepth(codecName);

    int bitsPerSample = 0;
    if (canReportStoredBitDepth) {
      bitsPerSample =
          int.tryParse(props['bits_per_raw_sample']?.toString() ?? '') ?? 0;
      if (bitsPerSample == 0) {
        bitsPerSample =
            int.tryParse(props['bits_per_sample']?.toString() ?? '') ?? 0;
      }
    }

    if (bitsPerSample == 0 && canReportStoredBitDepth) {
      final sampleFmt = props['sample_fmt']?.toString() ?? '';
      if (sampleFmt.contains('16') ||
          sampleFmt == 's16' ||
          sampleFmt == 's16p') {
        bitsPerSample = 16;
      } else if (sampleFmt.contains('32') ||
          sampleFmt == 'flt' ||
          sampleFmt == 'fltp') {
        bitsPerSample = 32;
      } else if (sampleFmt.contains('24') || sampleFmt == 's24') {
        bitsPerSample = 24;
      }
    }

    return _MediaInfo(
      fileSize: fileSize,
      codecName: codecName,
      codec: _formatCodecLabel(codecName, codecLongName),
      container: _formatContainerLabel(formatName, formatLongName),
      decodedSampleFormat: decodedSampleFormat,
      sampleRate: sampleRate,
      channels: channels,
      channelLayout: channelLayout,
      bitsPerSample: bitsPerSample,
      duration: duration,
      bitrate: bitrate,
      totalSamples: _estimateTotalSamples(
        props: props,
        duration: duration,
        sampleRate: sampleRate,
        channels: channels,
      ),
    );
  }

  String _formatCodecLabel(String codecName, String codecLongName) {
    final name = codecName.trim();
    final longName = _normalizeAnalysisLabel(codecLongName);
    if (name.isEmpty) return longName;
    if (longName.isEmpty || longName.toLowerCase() == name.toLowerCase()) {
      return name.toUpperCase();
    }
    return '${name.toUpperCase()} ($longName)';
  }

  String _formatContainerLabel(String formatName, String formatLongName) {
    final longName = _normalizeAnalysisLabel(formatLongName);
    if (longName.isNotEmpty) return longName;
    final name = formatName.trim();
    return name.isEmpty ? '' : name.toUpperCase();
  }

  String _normalizeAnalysisLabel(String value) {
    final trimmed = value.trim();
    final lower = trimmed.toLowerCase();
    if (lower.isEmpty || lower == 'unknown' || lower == 'n/a') return '';
    return trimmed;
  }

  int _estimateTotalSamples({
    required Map<dynamic, dynamic> props,
    required double duration,
    required int sampleRate,
    required int channels,
  }) {
    final nbSamples = int.tryParse(props['nb_samples']?.toString() ?? '');
    if (nbSamples != null && nbSamples > 0) {
      return nbSamples;
    }

    final durationTs = int.tryParse(props['duration_ts']?.toString() ?? '');
    final timeBase = props['time_base']?.toString() ?? '';
    if (durationTs != null && durationTs > 0 && timeBase.contains('/')) {
      final parts = timeBase.split('/');
      final numerator = double.tryParse(parts[0]);
      final denominator = double.tryParse(parts[1]);
      if (numerator != null &&
          numerator > 0 &&
          denominator != null &&
          denominator > 0 &&
          sampleRate > 0) {
        final seconds = durationTs * numerator / denominator;
        return (seconds * sampleRate).round();
      }
    }

    if (duration > 0 && sampleRate > 0) {
      return (duration * sampleRate).round();
    }
    return 0;
  }

  bool _codecHasStoredBitDepth(String codecName) {
    if (codecName.isEmpty) return false;
    return codecName == 'flac' ||
        codecName == 'alac' ||
        codecName == 'wavpack' ||
        codecName == 'ape' ||
        codecName == 'tta' ||
        codecName.startsWith('pcm_');
  }

  Future<_LevelMetrics?> _runFullStreamLevelAnalysis(
    String inputPath, {
    required int requestId,
    required double durationSeconds,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final metadataFile = File(
      '${tempDir.path}/analysis_metrics_'
      '${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    try {
      _checkAnalysisRequest(requestId);
      final session = await _analysisJobs.run(
        buildAudioMetricsArguments(
          inputPath: inputPath,
          metadataPath: metadataFile.path,
          durationSeconds: durationSeconds,
        ),
      );

      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        return null;
      }

      final metadata = await metadataFile.exists()
          ? await metadataFile.readAsString()
          : '';
      final metadataSummary = parseAudioAnalysisMetadata(metadata);
      final logs = metadataSummary == null
          ? await session.getAllLogsAsString() ?? ''
          : '';
      final summary = metadataSummary ?? parseAudioAstatsSummary(logs);
      if (summary == null) return null;
      final channelStats = metadataSummary?.channelStats.isNotEmpty == true
          ? metadataSummary!.channelStats
          : parseChannelStats(logs);
      final clippingSamples = channelStats.fold<int>(0, (sum, stats) {
        if (stats.peakDb == null || stats.peakDb! < -0.1) return sum;
        return sum + stats.peakCount;
      });
      return _LevelMetrics(
        peakDb: summary.peakDb,
        rmsDb: summary.rmsDb,
        integratedLufs: metadataSummary?.integratedLufs,
        truePeakDb: metadataSummary?.truePeakDb,
        clippingSamples: clippingSamples,
        channelStats: channelStats,
      );
    } finally {
      try {
        if (await metadataFile.exists()) await metadataFile.delete();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    if (_checkingCache) return const SizedBox.shrink();

    if (_unsupportedCodec != null) {
      return AppContentCard(
        elevation: 0,
        color: settingsGroupColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.audioAnalysisTitle,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.snackbarUnsupportedAudioFormat}: '
                      '$_unsupportedCodec',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_analyzing) {
      final isRescan = _data != null || _spectrogramImage != null;
      return AppContentCard(
        elevation: 0,
        color: settingsGroupColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLoadingIndicator(size: 24, strokeWidth: 2.5),
                const SizedBox(height: 12),
                Text(
                  isRescan
                      ? l10n.audioAnalysisRescanning
                      : l10n.audioAnalysisAnalyzing,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return AppContentCard(
        preserveColor: true,
        color: cs.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: cs.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              ),
              AppIconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: l10n.audioAnalysisRescan,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                color: cs.onErrorContainer,
                onPressed: () => _analyze(forceRefresh: true),
              ),
            ],
          ),
        ),
      );
    }

    if (_data == null) {
      return AppContentCard(
        elevation: 0,
        color: settingsGroupColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          onTap: _analyze,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.audioAnalysisTitle,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.audioAnalysisDescription,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    }

    final data = _data!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AudioInfoCard(
          data: data,
          onRescan: () => _analyze(forceRefresh: true),
        ),
        if (_spectrogramImage != null) ...[
          const SizedBox(height: 12),
          _SpectrogramView(
            image: _spectrogramImage!,
            sampleRate: data.sampleRate,
            maxFreq: data.sampleRate / 2,
            duration: data.duration,
            channels: data.channels,
            selectedChannel: _spectrogramChannel,
            channelLoading: _spectrogramChannelLoading,
            onChannelChanged: _changeSpectrogramChannel,
          ),
        ],
      ],
    );
  }
}

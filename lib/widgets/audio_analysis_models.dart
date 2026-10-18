part of 'audio_analysis_widget.dart';

// Per-run parameter records. The public result models live in
// services/audio_analysis_models.dart.

class _GeneratedSpectrogram {
  final ui.Image image;
  final Uint8List rgba;
  final double? cutoffFrequencyHz;

  const _GeneratedSpectrogram({
    required this.image,
    required this.rgba,
    this.cutoffFrequencyHz,
  });
}

class _AudioAnalysisRunResult {
  final AudioAnalysisData data;
  final ui.Image spectrogramImage;

  const _AudioAnalysisRunResult({
    required this.data,
    required this.spectrogramImage,
  });
}

class _SpectralCutoffFileParams {
  final String path;
  final int width;
  final int height;
  final double maxFrequencyHz;

  const _SpectralCutoffFileParams({
    required this.path,
    required this.width,
    required this.height,
    required this.maxFrequencyHz,
  });
}

double? _estimateEffectiveSpectralCutoffFileInIsolate(
  _SpectralCutoffFileParams params,
) {
  final expected = params.width * params.height;
  final file = File(params.path);
  if (file.lengthSync() != expected) {
    throw const FormatException('Incomplete spectral cutoff output');
  }
  return estimateEffectiveSpectralCutoffHz(
    intensity: file.readAsBytesSync(),
    width: params.width,
    height: params.height,
    maxFrequencyHz: params.maxFrequencyHz,
  );
}

class _MediaInfo {
  final int fileSize;
  final String codecName;
  final String codec;
  final String container;
  final String decodedSampleFormat;
  final int sampleRate;
  final int channels;
  final String channelLayout;
  final int bitsPerSample;
  final double duration;
  final int bitrate;
  final int totalSamples;

  const _MediaInfo({
    required this.fileSize,
    required this.codecName,
    required this.codec,
    required this.container,
    required this.decodedSampleFormat,
    required this.sampleRate,
    required this.channels,
    required this.channelLayout,
    required this.bitsPerSample,
    required this.duration,
    required this.bitrate,
    required this.totalSamples,
  });
}

class _LevelMetrics {
  final double peakDb;
  final double rmsDb;
  final double? integratedLufs;
  final double? truePeakDb;
  final int clippingSamples;
  final List<ChannelAnalysisStats> channelStats;

  const _LevelMetrics({
    required this.peakDb,
    required this.rmsDb,
    this.integratedLufs,
    this.truePeakDb,
    this.clippingSamples = 0,
    this.channelStats = const [],
  });
}

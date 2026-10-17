import 'dart:math';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/services/music_haptics.dart';

Uint8List _pcm(double seconds, double Function(double time) sample) {
  final count = (seconds * musicHapticsSampleRate).round();
  final data = ByteData(count * 2);
  for (var i = 0; i < count; i++) {
    final value = sample(i / musicHapticsSampleRate).clamp(-1.0, 1.0);
    data.setInt16(i * 2, (value * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Decaying bursts every [period] seconds, starting at [offset].
double Function(double) _hits(double frequency, double period, double offset) =>
    (time) {
      if (time < offset) return 0;
      final local = (time - offset) % period;
      return 0.8 * exp(-local * 30) * sin(2 * pi * frequency * local);
    };

class _Analyzer extends MusicHapticsAnalyzer {
  _Analyzer(this.result);
  final HapticTrack result;
  final paths = <String>[];

  @override
  Future<HapticTrack?> analyze(String path) async {
    paths.add(path);
    return result;
  }
}

void main() {
  test('a kick on every beat becomes one deep pulse per beat', () {
    final track = analyzeHapticPcm(_pcm(6, _hits(60, 0.5, 0.25)));
    expect(track.length, inInclusiveRange(11, 12));
    for (var n = 0; n < track.length; n++) {
      final beat = ((track.times[n] - 250) / 500).round();
      expect(
        (track.times[n] - (250 + beat * 500)).abs(),
        lessThanOrEqualTo(30),
      );
      expect(track.sharpness[n], lessThan(128));
    }
  });

  test('bright hits are sharper than bass hits', () {
    final track = analyzeHapticPcm(_pcm(4, _hits(1200, 0.4, 0.2)));
    expect(track.length, greaterThan(6));
    expect(track.sharpness.reduce(min), greaterThan(128));
  });

  test('silence and steady tones produce no pulses', () {
    expect(analyzeHapticPcm(_pcm(3, (_) => 0)).length, 0);
    final tone = analyzeHapticPcm(
      _pcm(3, (time) => 0.5 * sin(2 * pi * 220 * time)),
    );
    expect(tone.length, lessThanOrEqualTo(1));
  });

  test('pulses follow the playing position and stop on pause', () async {
    var state = PlaybackState(
      playing: true,
      processingState: AudioProcessingState.ready,
      updatePosition: Duration.zero,
    );
    final pulses = <(double, double)>[];
    final analyzer = _Analyzer(
      HapticTrack(
        Int32List.fromList([80, 280, 900]),
        Uint8List.fromList([255, 51, 255]),
        Uint8List.fromList([0, 255, 0]),
      ),
    );
    final haptics = MusicHaptics(
      state: () => state,
      analyzer: analyzer,
      pulse: (intensity, sharpness) async => pulses.add((intensity, sharpness)),
    );
    haptics.update('/music/song.flac');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(pulses, [(1.0, 0.0), (0.2, 1.0)]);

    state = state.copyWith(
      playing: false,
      updatePosition: const Duration(milliseconds: 400),
    );
    haptics.update('/music/song.flac');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(pulses, hasLength(2));

    haptics.update(null);
    expect(analyzer.paths, ['/music/song.flac']);
    haptics.dispose();
  });
}

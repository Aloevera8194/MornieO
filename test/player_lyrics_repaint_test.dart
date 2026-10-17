import 'dart:async';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/utils/lyrics_parser.dart';
import 'package:spotiflac_android/widgets/player_lyrics.dart';

const _text = 'AAAA BBBB';
const _lyrics = ParsedLyrics(
  synced: true,
  wordSynced: true,
  plainText: '',
  lines: [
    LyricLine(
      time: Duration.zero,
      end: Duration(seconds: 20),
      text: _text,
      words: [
        LyricWord(
          time: Duration.zero,
          end: Duration(seconds: 10),
          text: 'AAAA ',
        ),
        LyricWord(
          time: Duration(seconds: 10),
          end: Duration(seconds: 20),
          text: 'BBBB',
        ),
      ],
    ),
  ],
);

Finder get _paint => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == _text,
  ),
  matching: find.byType(CustomPaint),
);

List<List<Rect>> _segmentBoxes(WidgetTester tester) {
  // Inspect the existing painter payload without adding production test hooks.
  // ignore: avoid_dynamic_calls
  return (tester.widget<CustomPaint>(_paint).painter as dynamic).segmentBoxes
      as List<List<Rect>>;
}

Future<List<int>> _pixels(WidgetTester tester) async {
  final painter = tester.widget<CustomPaint>(_paint).painter!;
  final size = tester.getSize(_paint);
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final result = bytes.buffer.asUint8List().toList();
    image.dispose();
    picture.dispose();
    return result;
  }))!;
}

void main() {
  for (final mornye in [false, true]) {
    testWidgets(
      'playing lyrics retain their painter and refresh stopped highlights ($mornye)',
      (tester) async {
        final playback = StreamController<PlaybackState>.broadcast();
        final preview = ValueNotifier<Duration?>(null);
        addTearDown(playback.close);
        addTearDown(preview.dispose);
        final theme = mornye
            ? MornyeTheme.build(Brightness.dark)
            : ThemeData.dark();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playbackStateProvider.overrideWith((ref) => playback.stream),
            ],
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SyncedLyricsView(
                  lyrics: _lyrics,
                  seekPreview: preview,
                  colorScheme: theme.colorScheme,
                  isActive: true,
                  showPronunciation: false,
                  showTranslation: false,
                ),
              ),
            ),
          ),
        );
        Future<void> report(
          int seconds, {
          bool playing = false,
          AudioProcessingState state = AudioProcessingState.ready,
        }) async {
          playback.add(
            PlaybackState(
              playing: playing,
              processingState: state,
              updatePosition: Duration(seconds: seconds),
            ),
          );
          await tester.pump();
          await tester.pump();
        }

        await report(2);
        await tester.pumpAndSettle();
        await report(2, playing: true);
        await tester.pump(const Duration(milliseconds: 500));
        final retained = tester.widget<CustomPaint>(_paint).painter!;
        final retainedBoxes = _segmentBoxes(tester);
        final early = await _pixels(tester);
        var repaintNotifications = 0;
        void repaint() => repaintNotifications++;
        retained.addListener(repaint);
        await report(6, playing: true);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.widget<CustomPaint>(_paint).painter, same(retained));
        expect(repaintNotifications, greaterThan(0));
        expect(await _pixels(tester), isNot(orderedEquals(early)));
        retained.removeListener(repaint);

        await report(8);
        await tester.pumpAndSettle();
        expect(_segmentBoxes(tester), same(retainedBoxes));
        final paused = await _pixels(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(await _pixels(tester), orderedEquals(paused));
        await report(3);
        await tester.pumpAndSettle();
        expect(await _pixels(tester), isNot(orderedEquals(paused)));

        await report(4, playing: true, state: AudioProcessingState.buffering);
        await tester.pumpAndSettle();
        if (mornye) {
          expect(_paint, findsNothing);
        } else {
          final buffered = await _pixels(tester);
          await tester.pump(const Duration(seconds: 1));
          expect(await _pixels(tester), orderedEquals(buffered));
          await report(7, playing: true, state: AudioProcessingState.buffering);
          await tester.pumpAndSettle();
          expect(await _pixels(tester), isNot(orderedEquals(buffered)));
        }

        preview.value = const Duration(seconds: 2);
        await tester.pumpAndSettle();
        final sought = await _pixels(tester);
        final soughtBoxes = _segmentBoxes(tester);
        preview.value = const Duration(seconds: 8);
        await tester.pumpAndSettle();
        expect(_segmentBoxes(tester), same(soughtBoxes));
        expect(await _pixels(tester), isNot(orderedEquals(sought)));
        preview.value = const Duration(seconds: 2);
        await tester.pumpAndSettle();
        expect(await _pixels(tester), orderedEquals(sought));
        await report(12, playing: true, state: AudioProcessingState.buffering);
        await tester.pumpAndSettle();
        expect(await _pixels(tester), orderedEquals(sought));
        preview.value = null;
        await report(2);
        await tester.pumpAndSettle();
        expect(await _pixels(tester), orderedEquals(sought));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'timed geometry survives rebuilds and tracks layout and boundaries',
    (tester) async {
      final preview = ValueNotifier<Duration?>(const Duration(seconds: 5));
      addTearDown(preview.dispose);
      final words = _lyrics.lines.single.words.toList();
      final lyrics = ParsedLyrics(
        synced: true,
        wordSynced: true,
        plainText: '',
        lines: [
          LyricLine(
            time: Duration.zero,
            end: const Duration(seconds: 20),
            text: _text,
            words: words,
            translation: 'Translation',
          ),
        ],
      );
      var width = 620.0;
      var fontSize = 28.0;
      var scale = 1.0;
      var direction = TextDirection.ltr;
      var locale = const Locale('en');
      var supplements = false;
      var viewKey = 0;
      Future<void> pump() async {
        final theme = ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.copyWith(
            headlineSmall: TextStyle(fontSize: fontSize),
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: theme,
              locale: locale,
              supportedLocales: const [Locale('en'), Locale('en', 'US')],
              home: Scaffold(
                body: Directionality(
                  textDirection: direction,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: SizedBox(
                      width: width,
                      child: SyncedLyricsView(
                        key: ValueKey(viewKey),
                        lyrics: lyrics,
                        seekPreview: preview,
                        colorScheme: theme.colorScheme,
                        isActive: true,
                        showPronunciation: false,
                        showTranslation: supplements,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> matchesFreshLayout() async {
        final cached = await _pixels(tester);
        viewKey++;
        await pump();
        expect(await _pixels(tester), orderedEquals(cached));
      }

      await pump();
      var boxes = _segmentBoxes(tester);
      final initial = await _pixels(tester);
      await pump();
      expect(_segmentBoxes(tester), same(boxes));
      supplements = true;
      await pump();
      expect(_segmentBoxes(tester), same(boxes));
      expect(await _pixels(tester), orderedEquals(initial));

      // Timing-only edits must repaint even though the geometry is retained.
      final oldPainter = tester.widget<CustomPaint>(_paint).painter!;
      words[0] = const LyricWord(
        time: Duration.zero,
        end: Duration(seconds: 6),
        text: 'AAAA ',
      );
      await pump();
      expect(_segmentBoxes(tester), same(boxes));
      expect(
        tester.widget<CustomPaint>(_paint).painter!.shouldRepaint(oldPainter),
        isTrue,
      );
      expect(await _pixels(tester), isNot(orderedEquals(initial)));

      // The paragraph is unchanged, but the timed selections have new bounds.
      words[0] = const LyricWord(
        time: Duration.zero,
        end: Duration(seconds: 10),
        text: 'AA',
      );
      words[1] = const LyricWord(
        time: Duration(seconds: 10),
        end: Duration(seconds: 20),
        text: 'AA BBBB',
      );
      await pump();
      expect(_segmentBoxes(tester), isNot(same(boxes)));
      expect(_segmentBoxes(tester), isNot(equals(boxes)));
      await matchesFreshLayout();

      for (final change in <VoidCallback>[
        () => width = 180,
        () => direction = TextDirection.rtl,
        () => scale = 1.4,
        () => fontSize = 32,
        () => locale = const Locale('en', 'US'),
        () => width = 620,
      ]) {
        boxes = _segmentBoxes(tester);
        change();
        await pump();
        expect(_segmentBoxes(tester), isNot(same(boxes)));
        if (width == 180) {
          expect(
            _segmentBoxes(
              tester,
            ).expand((boxes) => boxes).map((box) => box.top).toSet().length,
            greaterThan(1),
          );
        }
        await matchesFreshLayout();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

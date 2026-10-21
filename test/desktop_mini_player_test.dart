import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mornye/controllers/player_metadata_controller.dart';
import 'package:mornye/l10n/app_localizations.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/theme/app_theme.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/utils/desktop_platform.dart';
import 'package:mornye/utils/lyrics_parser.dart';
import 'package:mornye/widgets/desktop/desktop_commands.dart';
import 'package:mornye/widgets/desktop/desktop_player_bar.dart';
import 'package:mornye/widgets/desktop/desktop_window.dart';

const _track = MediaItem(
  id: 'track',
  title: 'A song',
  artist: 'An artist',
  duration: Duration(minutes: 4),
  extras: {'source': '/music/song.flac'},
);

const _lrc =
    '[00:00.00]First line\n[00:05.00]Second line\n[00:10.00]Third line';

const _ttml =
    '<tt xmlns="http://www.w3.org/ns/ttml"><body><div>'
    '<p begin="0s" end="4s"><span begin="0s" end="2s">First</span> '
    '<span begin="2s" end="4s">words</span></p>'
    '<p begin="5s" end="9s"><span begin="5s" end="7s">Second</span> '
    '<span begin="7s" end="9s">words</span></p>'
    '<p begin="10s" end="14s"><span begin="10s" end="12s">Third</span> '
    '<span begin="12s" end="14s">words</span></p>'
    '</div></body></tt>';

const _channel = MethodChannel('com.zarz.mornye/window');

void main() {
  late List<MethodCall> calls;
  late bool windowOpens;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDesktopPlatformOverride = true;
    debugDesktopTitleBarInContentOverride = true;
    calls = [];
    windowOpens = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return call.method == 'openMiniPlayer' ? windowOpens : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    debugDesktopPlatformOverride = null;
    debugDesktopTitleBarInContentOverride = null;
    desktopMiniPlayerOpen.value = false;
    desktopMiniPlayerLyrics.value = false;
  });

  test('shrinks the window and returns it', () async {
    await toggleDesktopMiniPlayer();
    expect(desktopMiniPlayerOpen.value, isTrue);
    expect(calls.single.method, 'openMiniPlayer');
    expect(calls.single.arguments, {'width': 360.0, 'height': 140.0});

    await toggleDesktopMiniPlayer();
    expect(desktopMiniPlayerOpen.value, isFalse);
    expect(calls.last.method, 'closeMiniPlayer');
  });

  test('stays in the full window when the window cannot shrink', () async {
    windowOpens = false;
    await setDesktopMiniPlayer(open: true);
    expect(desktopMiniPlayerOpen.value, isFalse);
  });

  test('does nothing where the window cannot shrink', () async {
    debugDesktopTitleBarInContentOverride = false;
    await setDesktopMiniPlayer(open: true);
    expect(desktopMiniPlayerOpen.value, isFalse);
    expect(calls, isEmpty);
  });

  test('has the Music shortcut on macOS only', () {
    final shortcut = desktopCommandShortcut(
      DesktopCommand.miniPlayer,
      TargetPlatform.macOS,
    )!;
    expect(shortcut.trigger, LogicalKeyboardKey.keyM);
    expect((shortcut.meta, shortcut.alt), (true, true));
    expect((shortcut.control, shortcut.shift), (false, false));
    expect(
      desktopCommandShortcut(DesktopCommand.miniPlayer, TargetPlatform.windows),
      isNull,
    );
  });

  testWidgets('word-timed TTML lines advance while playing', (tester) async {
    tester.view.physicalSize = const Size(360, 248);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = StreamController<PlaybackState>();
    addTearDown(playback.close);
    // Playing from the start; no further report arrives while it plays.
    playback.add(
      PlaybackState(processingState: AudioProcessingState.ready, playing: true),
    );
    desktopMiniPlayerOpen.value = true;
    desktopMiniPlayerLyrics.value = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMediaItemProvider.overrideWithBuild(
            (ref, notifier) => Stream.value(_track),
          ),
          playbackStateProvider.overrideWith((ref) => playback.stream),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DesktopMiniPlayer(
            metadataControllerFactory: () => PlayerMetadataController(
              readMetadata: (_) async => {'lyrics': _ttml},
              parseLyrics: (raw) async => LyricsParser.parse(raw!),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Second'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('First'), findsNothing);
    expect(find.textContaining('Third'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Second'), findsNothing);
    expect(find.textContaining('Third'), findsOneWidget);
  });

  for (final mornye in [false, true]) {
    final style = mornye ? 'Mornye' : 'Material';

    testWidgets('$style panel follows the lyrics and grows for them', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 248);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final playback = StreamController<PlaybackState>();
      addTearDown(playback.close);
      PlaybackState pausedAt(int seconds) => PlaybackState(
        processingState: AudioProcessingState.ready,
        updatePosition: Duration(seconds: seconds),
      );
      playback.add(pausedAt(6));
      desktopMiniPlayerOpen.value = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentMediaItemProvider.overrideWithBuild(
              (ref, notifier) => Stream.value(_track),
            ),
            playbackStateProvider.overrideWith((ref) => playback.stream),
          ],
          child: MaterialApp(
            theme: mornye
                ? MornyeTheme.build(Brightness.light)
                : AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DesktopMiniPlayer(
              metadataControllerFactory: () => PlayerMetadataController(
                readMetadata: (_) async => {'lyrics': _lrc},
                parseLyrics: (raw) async => LyricsParser.parse(raw!),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A song'), findsOneWidget);
      expect(find.text('Second line'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('desktop-mini-player-lyrics')),
      );
      await tester.pumpAndSettle();
      expect(desktopMiniPlayerLyrics.value, isTrue);
      expect(calls.last.arguments, {'width': 360.0, 'height': 248.0});
      expect(find.text('Second line'), findsOneWidget);
      expect(find.text('Third line'), findsOneWidget);

      playback.add(pausedAt(11));
      await tester.pumpAndSettle();
      expect(find.text('Second line'), findsNothing);
      expect(find.text('Third line'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('desktop-mini-player-expand')),
      );
      await tester.pumpAndSettle();
      expect(calls.last.method, 'closeMiniPlayer');
      expect(desktopMiniPlayerOpen.value, isFalse);
    });
  }
}

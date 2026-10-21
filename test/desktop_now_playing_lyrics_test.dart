import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mornye/controllers/player_metadata_controller.dart';
import 'package:mornye/l10n/app_localizations.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/providers/system_volume_provider.dart';
import 'package:mornye/theme/app_theme.dart';
import 'package:mornye/utils/desktop_platform.dart';
import 'package:mornye/utils/lyrics_parser.dart';
import 'package:mornye/widgets/app_loading_indicator.dart';
import 'package:mornye/widgets/desktop/desktop_inspector.dart';
import 'package:mornye/widgets/desktop/desktop_now_playing.dart';
import 'package:mornye/widgets/player_artwork.dart';
import 'package:mornye/widgets/player_lyrics.dart';

const _track = MediaItem(
  id: 'track',
  title: 'A song',
  artist: 'An artist',
  duration: Duration(minutes: 4),
  extras: {'source': '/music/song.flac'},
);

String _timestamp(int seconds) =>
    '[${(seconds ~/ 60).toString().padLeft(2, '0')}:'
    '${(seconds % 60).toString().padLeft(2, '0')}.00]';

final _lrc = [
  for (var i = 0; i < 80; i++) '${_timestamp(i * 3)}Lyric line $i',
].join('\n');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDesktopPlatformOverride = true;
    desktopInspectorPanel.value = null;
  });

  tearDown(() {
    debugDesktopPlatformOverride = null;
    desktopInspectorPanel.value = null;
  });

  testWidgets('Material lyrics toggle paints only the playing line', (
    tester,
  ) async {
    // A Retina window, where a half logical pixel is a device pixel.
    tester.view.physicalSize = const Size(3024, 1964);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMediaItemProvider.overrideWithBuild(
            (ref, notifier) => Stream.value(_track),
          ),
          // Paused mid-song, on line 40.
          playbackStateProvider.overrideWith(
            (ref) => Stream.value(
              PlaybackState(
                processingState: AudioProcessingState.ready,
                updatePosition: const Duration(seconds: 121),
              ),
            ),
          ),
          playQueueProvider.overrideWith((ref) => Stream.value(const [_track])),
          systemVolumeProvider.overrideWith((ref) => Stream.value(0.5)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DesktopNowPlaying(
              metadataControllerFactory: () => PlayerMetadataController(
                readMetadata: (_) async => {'lyrics': _lrc},
                parseLyrics: (raw) async => LyricsParser.parse(raw!),
              ),
            ),
          ),
        ),
      ),
    );
    // Looping animations elsewhere in the player keep pumpAndSettle busy.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final view = find.byType(SyncedLyricsView);
    final cover = find.byWidgetPredicate(
      (widget) => widget is PlayerArtwork && widget.iconSize == 96,
    );
    final coverWidths = <int?>{};
    State? lyricsState;

    // Whether the lyrics view paints its list at all.
    bool listShown() {
      final list = find
          .descendant(of: view, matching: find.byType(Scrollable))
          .first;
      final hiding = find.descendant(
        of: view,
        matching: find.ancestor(of: list, matching: find.byType(Opacity)),
      );
      return tester
          .renderObjectList<RenderOpacity>(hiding)
          .every((opacity) => opacity.opacity > 0);
    }

    // Checks what the last frame painted: render objects keep the layout
    // and opacity of that frame even after a post-frame scroll jump.
    void checkFrame(String label) {
      coverWidths.add(tester.widget<PlayerArtwork>(cover).cacheWidth);
      expect(find.byType(AppLoadingIndicator), findsNothing, reason: label);
      if (view.evaluate().isEmpty) return;
      final state = tester.state(view);
      lyricsState ??= state;
      expect(state, same(lyricsState), reason: '$label rebuilt the lyrics');

      final panel = tester.renderObject<RenderOpacity>(
        find.ancestor(of: view, matching: find.byType(Opacity)).first,
      );
      final slide = tester.widget<Transform>(
        find.ancestor(of: view, matching: find.byType(Transform)).first,
      );
      final dx = slide.transform.getTranslation().x * 2;
      expect(dx, dx.roundToDouble(), reason: '$label slid between pixels');

      if (panel.opacity == 0 || !listShown()) return;
      final viewport = tester.getRect(
        find.descendant(of: view, matching: find.byType(Scrollable)).first,
      );
      final playing = find.descendant(
        of: view,
        matching: find.text('Lyric line 40'),
      );
      expect(playing, findsOneWidget, reason: label);
      expect(
        tester.getCenter(playing).dy,
        moreOrLessEquals(viewport.center.dy, epsilon: 1),
        reason: '$label painted another line in the middle',
      );
    }

    for (var cycle = 0; cycle < 2; cycle++) {
      desktopInspectorPanel.value = DesktopInspectorPanel.lyrics;
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        checkFrame('open $cycle frame $frame');
      }
      // The list shows once it has found the line.
      expect(listShown(), isTrue);
      desktopInspectorPanel.value = null;
      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        checkFrame('close $cycle frame $frame');
      }
      expect(view, findsNothing);
      lyricsState = null;
    }
    // The cover column resizes with the panel but decodes its cover once.
    expect(coverWidths, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

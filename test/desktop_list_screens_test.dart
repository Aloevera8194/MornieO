import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/providers/playback_provider.dart';
import 'package:mornye/screens/local_album_screen.dart';
import 'package:mornye/services/library_database.dart';
import 'package:mornye/theme/app_theme.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/utils/desktop_platform.dart';
import 'package:mornye/widgets/album_track_tile.dart';
import 'package:mornye/widgets/desktop/desktop_selection.dart';
import 'package:mornye/widgets/desktop/track_table.dart';
import 'package:mornye/widgets/mornye_context_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends MusicPlayerController {
  @override
  Future<void> setShuffle(bool enabled) async {}
}

class _Playback extends PlaybackController {
  final started = <String>[];

  @override
  Future<void> playLocalLibraryQueue(
    List<LocalLibraryItem> items, {
    required LocalLibraryItem startItem,
  }) async {
    started.add(startItem.id);
  }
}

final _tracks = [
  for (final (number, name) in [(1, 'Bravo'), (2, 'Alpha'), (3, 'Charlie')])
    LocalLibraryItem(
      id: '$number',
      trackName: name,
      artistName: 'Artist',
      albumName: 'Album',
      filePath: '/music/$name.flac',
      trackNumber: number,
      duration: 60 * (4 - number),
      scannedAt: DateTime(2026),
    ),
];

Future<_Playback> _pumpAlbum(WidgetTester tester, {bool mornye = false}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final playback = _Playback();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentMediaItemProvider.overrideWithBuild(
          (ref, notifier) => const Stream.empty(),
        ),
        playbackPlayingProvider.overrideWith((ref) => false),
        musicPlayerControllerProvider.overrideWithValue(_Player()),
        playbackProvider.overrideWith(() => playback),
      ],
      child: MaterialApp(
        theme: mornye ? MornyeTheme.build(Brightness.light) : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LocalAlbumScreen(
          albumName: 'Album',
          artistName: 'Artist',
          tracks: _tracks,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return playback;
}

Future<void> _click(WidgetTester tester, Finder finder, {int buttons = 1}) =>
    tester
        .startGesture(
          tester.getCenter(finder),
          kind: PointerDeviceKind.mouse,
          buttons: buttons,
        )
        .then((gesture) => gesture.up());

void main() {
  setUp(DesktopDoubleClick.reset);
  tearDown(() => debugDesktopPlatformOverride = null);

  testWidgets('phones keep the album track tiles', (tester) async {
    debugDesktopPlatformOverride = false;
    await _pumpAlbum(tester);
    expect(find.byType(AlbumTrackTile), findsNWidgets(3));
    expect(find.byType(SliverTrackTable), findsNothing);
  });

  for (final mornye in [false, true]) {
    testWidgets('desktop album lists songs in a table (mornye: $mornye)', (
      tester,
    ) async {
      debugDesktopPlatformOverride = true;
      final playback = await _pumpAlbum(tester, mornye: mornye);
      expect(find.byType(AlbumTrackTile), findsNothing);
      expect(find.byType(SliverTrackTable), findsOneWidget);

      // A right-click selects the row and opens the long-press actions, the
      // selection bar's, as a menu.
      await _click(tester, find.text('Charlie'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      final menu = mornye
          ? find.byType(MornyeContextMenu)
          : find.ancestor(
              of: find.byType(MenuItemButton).first,
              matching: find.byType(MenuAnchor),
            );
      expect(menu, findsOneWidget);
      expect(
        find.descendant(of: menu, matching: find.text('Play next')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: menu, matching: find.textContaining('Delete')),
        findsOneWidget,
      );

      // Escape closes the menu, then clears the selection.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byType(mornye ? MornyeContextMenu : MenuItemButton),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Play next'), findsNothing);

      // A double click plays the row.
      await _click(tester, find.text('Alpha'));
      await tester.pump();
      await _click(tester, find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(playback.started, ['2']);
    });
  }
}

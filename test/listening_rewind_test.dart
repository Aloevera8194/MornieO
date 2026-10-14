import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/screens/listening_rewind_screen.dart';
import 'package:spotiflac_android/services/listening_rewind.dart';
import 'package:spotiflac_android/services/listening_statistics.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';

Map<String, Object?> _row(
  String day,
  String key, {
  String artist = 'Artist',
  String album = 'Album',
  int minutes = 10,
  int plays = 1,
}) => {
  'day': day,
  'track_key': key,
  'title': 'Song $key',
  'artist': artist,
  'album': album,
  'artwork': null,
  'milliseconds': minutes * 60000,
  'plays': plays,
};

final _range = ListeningRewindRange.of(
  ListeningRewindPeriod.weeks,
  DateTime(2026, 10, 14, 21),
);

ListeningRewind _sample({Set<String>? newArtists, ListeningReplay? replay}) =>
    ListeningRewind.compute(
      range: _range,
      summary: ListeningSummary.fromRows([
        _row('2026-10-01', 'a', minutes: 30, plays: 3),
        _row('2026-10-02', 'a', minutes: 20, plays: 2),
        _row('2026-10-03', 'b', album: 'ALBUM', minutes: 15),
        _row('2026-10-05', 'c', artist: 'Other', album: 'Else', minutes: 40),
        _row('2026-10-06', 'd', artist: 'Fresh', album: '', minutes: 5),
      ]),
      previousMilliseconds: 100 * 60000,
      newArtistNames: newArtists,
      replay: replay,
    );

void main() {
  test('rolling and yearly windows compare with the span before them', () {
    expect(_range.start, DateTime(2026, 9, 17));
    expect(_range.end, DateTime(2026, 10, 15));
    expect(_range.lastDay, DateTime(2026, 10, 14));
    expect(_range.previousStart, DateTime(2026, 8, 20));
    expect(_range.previousEnd, DateTime(2026, 9, 17));

    final year = ListeningRewindRange.of(
      ListeningRewindPeriod.year,
      DateTime(2026, 10, 14),
    );
    expect(year.start, DateTime(2026));
    expect(year.previousStart, DateTime(2025));
    expect(year.previousEnd, DateTime(2025, 10, 15));
  });

  test('highlights rank artists, merge albums and read listening rhythm', () {
    final rewind = _sample();
    expect(rewind.minutes, 110);
    expect(rewind.changePercent, 10);
    expect(rewind.topArtists.map((e) => e.key), ['Artist', 'Other', 'Fresh']);
    expect(rewind.topArtistShare, 59);
    // Album names match case-insensitively and empty albums are skipped.
    expect(rewind.topAlbums.first.album, 'Album');
    expect(rewind.topAlbums.first.milliseconds, 65 * 60000);
    expect(rewind.topAlbums.length, 2);
    expect(rewind.peakDay, DateTime(2026, 10, 5));
    expect(rewind.peakDayMilliseconds, 40 * 60000);
    // 1–3 October run three days in a row; 5–6 October two.
    expect(rewind.longestStreak, 3);
    expect(rewind.favoriteWeekday, DateTime(2026, 10, 5).weekday);
    // Without earlier history every artist would be new, so none are shown.
    expect(rewind.newArtists, isEmpty);
    expect(rewind.replay, isNull);
  });

  test('discoveries follow listening order and replays need repeats', () {
    const track = ListeningTrack(
      key: 'a',
      title: 'Song a',
      artist: 'Artist',
      album: 'Album',
    );
    final rewind = _sample(
      newArtists: {'Fresh', 'Other', 'Elsewhere'},
      replay: ListeningReplay(track, DateTime(2026, 10, 1), 4),
    );
    expect(rewind.newArtists, ['Other', 'Fresh']);
    expect(rewind.replay?.plays, 4);
    expect(
      _sample(replay: ListeningReplay(track, DateTime(2026, 10, 1), 2)).replay,
      isNull,
    );
    expect(
      ListeningRewind.compute(
        range: _range,
        summary: const ListeningSummary(),
        previousMilliseconds: 0,
      ).changePercent,
      isNull,
    );
  });

  for (final mornye in [false, true]) {
    testWidgets('Rewind story steps through highlights ($mornye)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listeningRewindProvider.overrideWith(
              (ref, period) async => _sample(newArtists: {'Fresh'}),
            ),
          ],
          child: MaterialApp(
            theme: mornye ? MornyeTheme.build(Brightness.dark) : ThemeData(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // Reduced motion: no auto-advance, so the story waits for taps.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const ListeningRewindScreen(
              period: ListeningRewindPeriod.weeks,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your Rewind'), findsOneWidget);
      expect(find.text('Last 4 weeks'), findsOneWidget);

      final story = tester.getRect(find.byType(PageView));
      Future<void> next() async {
        await tester.tapAt(Offset(story.right - 40, story.center.dy));
        await tester.pumpAndSettle();
      }

      await next();
      expect(find.text('110'), findsOneWidget);
      expect(find.text('10% more than the period before'), findsOneWidget);
      await next();
      expect(find.text('Your top artist'), findsOneWidget);
      expect(find.text('65 min · 59% of your listening time'), findsOneWidget);
      await tester.tapAt(Offset(story.left + 20, story.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('110'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty windows explain how to fill a Rewind', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listeningRewindProvider.overrideWith(
            (ref, period) async => ListeningRewind.compute(
              range: _range,
              summary: const ListeningSummary(),
              previousMilliseconds: 0,
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ListeningRewindScreen(period: ListeningRewindPeriod.year),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Not enough listening'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });
}

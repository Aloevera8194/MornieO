import 'package:spotiflac_android/services/listening_statistics.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:sqflite/sqflite.dart';

/// Windows a Rewind can look back over. Rolling windows end today; [year]
/// covers the calendar year so far.
enum ListeningRewindPeriod {
  weeks(28),
  quarter(91),
  halfYear(182),
  year(0);

  const ListeningRewindPeriod(this.days);

  final int days;
}

/// Local calendar days. Both ends are exclusive of [end] and [previousEnd].
///
/// The previous window is the same span immediately before a rolling window,
/// or the same dates last year for [ListeningRewindPeriod.year].
class ListeningRewindRange {
  const ListeningRewindRange({
    required this.start,
    required this.end,
    required this.previousStart,
    required this.previousEnd,
  });

  factory ListeningRewindRange.of(ListeningRewindPeriod period, DateTime now) {
    final end = DateTime(now.year, now.month, now.day + 1);
    if (period == ListeningRewindPeriod.year) {
      return ListeningRewindRange(
        start: DateTime(now.year),
        end: end,
        previousStart: DateTime(now.year - 1),
        previousEnd: DateTime(now.year - 1, now.month, now.day + 1),
      );
    }
    final start = DateTime(end.year, end.month, end.day - period.days);
    return ListeningRewindRange(
      start: start,
      end: end,
      previousStart: DateTime(start.year, start.month, start.day - period.days),
      previousEnd: start,
    );
  }

  final DateTime start;
  final DateTime end;
  final DateTime previousStart;
  final DateTime previousEnd;

  /// The last day inside the window.
  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);
}

class ListeningAlbumTotal {
  const ListeningAlbumTotal({
    required this.album,
    required this.artist,
    required this.milliseconds,
    required this.plays,
    this.artwork,
  });

  final String album;
  final String artist;
  final String? artwork;
  final int milliseconds;
  final int plays;
}

/// The most plays one song received on a single day.
class ListeningReplay {
  const ListeningReplay(this.track, this.day, this.plays);

  final ListeningTrack track;
  final DateTime day;
  final int plays;
}

/// Highlights of one Rewind window, derived from the daily listening table.
class ListeningRewind {
  const ListeningRewind({
    required this.range,
    required this.summary,
    required this.previousMilliseconds,
    required this.topArtists,
    required this.topAlbums,
    required this.newArtists,
    required this.longestStreak,
    this.peakDay,
    this.peakDayMilliseconds = 0,
    this.favoriteWeekday,
    this.replay,
  });

  /// Songs replayed fewer times than this in one day are not highlighted.
  static const minimumReplays = 3;

  /// Builds the highlights from the window's [summary].
  ///
  /// [newArtistNames] holds artists first heard inside the window; pass null
  /// when nothing was recorded before it, since every artist would be "new".
  factory ListeningRewind.compute({
    required ListeningRewindRange range,
    required ListeningSummary summary,
    required int previousMilliseconds,
    Set<String>? newArtistNames,
    ListeningReplay? replay,
  }) {
    final artists = summary.artists.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final albums = <(String, String), ListeningAlbumTotal>{};
    for (final total in summary.tracks) {
      final album = total.track.album.trim();
      if (album.isEmpty) continue;
      final key = (album.toLowerCase(), total.track.artist.toLowerCase());
      final existing = albums[key];
      albums[key] = ListeningAlbumTotal(
        album: existing?.album ?? album,
        artist: existing?.artist ?? total.track.artist,
        // Tracks arrive most listened first, so the first cover wins.
        artwork:
            existing?.artwork ?? normalizeCoverReference(total.track.artwork),
        milliseconds: (existing?.milliseconds ?? 0) + total.milliseconds,
        plays: (existing?.plays ?? 0) + total.plays,
      );
    }
    final topAlbums = albums.values.toList()
      ..sort((a, b) => b.milliseconds.compareTo(a.milliseconds));

    final days = <DateTime, int>{
      for (final entry in summary.days.entries)
        if (entry.value > 0) DateTime.parse(entry.key): entry.value,
    };
    final ordered = days.keys.toList()..sort();
    DateTime? peakDay;
    var peakMilliseconds = 0;
    final weekdays = <int, int>{};
    var longestStreak = 0;
    var streak = 0;
    DateTime? previous;
    for (final day in ordered) {
      final time = days[day]!;
      if (time > peakMilliseconds) {
        peakDay = day;
        peakMilliseconds = time;
      }
      weekdays[day.weekday] = (weekdays[day.weekday] ?? 0) + time;
      final expected = previous == null
          ? null
          : DateTime(previous.year, previous.month, previous.day + 1);
      streak = expected == day ? streak + 1 : 1;
      if (streak > longestStreak) longestStreak = streak;
      previous = day;
    }
    int? favoriteWeekday;
    for (final entry in weekdays.entries) {
      if (favoriteWeekday == null || entry.value > weekdays[favoriteWeekday]!) {
        favoriteWeekday = entry.key;
      }
    }

    return ListeningRewind(
      range: range,
      summary: summary,
      previousMilliseconds: previousMilliseconds,
      topArtists: artists,
      topAlbums: topAlbums,
      newArtists: newArtistNames == null
          ? const []
          : [
              for (final artist in artists)
                if (newArtistNames.contains(artist.key)) artist.key,
            ],
      longestStreak: longestStreak,
      peakDay: peakDay,
      peakDayMilliseconds: peakMilliseconds,
      favoriteWeekday: favoriteWeekday,
      replay: replay != null && replay.plays >= minimumReplays ? replay : null,
    );
  }

  final ListeningRewindRange range;
  final ListeningSummary summary;
  final int previousMilliseconds;

  /// Artists by listening time, most first.
  final List<MapEntry<String, int>> topArtists;
  final List<ListeningAlbumTotal> topAlbums;

  /// Artists first heard in this window, most listened first.
  final List<String> newArtists;
  final DateTime? peakDay;
  final int peakDayMilliseconds;

  /// [DateTime.monday] to [DateTime.sunday].
  final int? favoriteWeekday;
  final int longestStreak;
  final ListeningReplay? replay;

  bool get isEmpty => summary.milliseconds <= 0;

  int get minutes => (summary.milliseconds / 60000).round();

  /// Signed change from the previous window, or null without earlier
  /// listening to compare against.
  int? get changePercent => previousMilliseconds <= 0
      ? null
      : ((summary.milliseconds - previousMilliseconds) *
                100 /
                previousMilliseconds)
            .round();

  /// The top artist's share of all listening, in percent.
  int get topArtistShare => topArtists.isEmpty || summary.milliseconds <= 0
      ? 0
      : (topArtists.first.value * 100 / summary.milliseconds).round();
}

/// Reads one Rewind window, aggregating in SQLite like the statistics screen.
Future<ListeningRewind> readListeningRewind(
  DatabaseExecutor db,
  ListeningRewindRange range,
) async {
  final summary = await readListeningSummary(db, range.start, range.end);
  final start = listeningDay(range.start);
  final end = listeningDay(range.end);
  final previous = await db.rawQuery(
    '''
    SELECT COALESCE(SUM(milliseconds), 0) AS milliseconds
    FROM listening WHERE day >= ? AND day < ?
  ''',
    [listeningDay(range.previousStart), listeningDay(range.previousEnd)],
  );
  final earlier = await db.rawQuery(
    'SELECT COUNT(*) AS count FROM listening WHERE day < ?',
    [start],
  );
  final hasHistory = (earlier.first['count'] as int? ?? 0) > 0;
  final newArtists = hasHistory
      ? await db.rawQuery(
          '''
          SELECT artist FROM listening GROUP BY artist
          HAVING MIN(day) >= ? AND MIN(day) < ?
        ''',
          [start, end],
        )
      : null;
  final replays = await db.rawQuery(
    '''
    SELECT day, track_key, title, artist, album, artwork, plays
    FROM listening WHERE day >= ? AND day < ?
    ORDER BY plays DESC, milliseconds DESC LIMIT 1
  ''',
    [start, end],
  );
  final replay = replays.isEmpty ? null : replays.first;
  return ListeningRewind.compute(
    range: range,
    summary: summary,
    previousMilliseconds: previous.first['milliseconds'] as int? ?? 0,
    newArtistNames: newArtists == null
        ? null
        : {for (final row in newArtists) row['artist'] as String},
    replay: replay == null
        ? null
        : ListeningReplay(
            ListeningTrack(
              key: replay['track_key'] as String,
              title: replay['title'] as String,
              artist: replay['artist'] as String,
              album: replay['album'] as String,
              artwork: replay['artwork'] as String?,
            ),
            DateTime.parse(replay['day'] as String),
            replay['plays'] as int,
          ),
  );
}

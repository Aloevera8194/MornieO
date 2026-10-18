import 'dart:io';

import 'package:audio_service/audio_service.dart' show AudioServiceRepeatMode;
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/services/music_player_runtime.dart';
import 'package:spotiflac_android/services/playable_media.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/playback_artwork.dart';

final _log = AppLogger('MusicPlayer');

Future<void> restorePlaybackSession(MusicPlayerRuntime runtime) async {
  try {
    final database = runtime.dependencies.sessionDatabase;
    final session = await database.getPlaybackSession();
    if (session == null) return;

    final rawMedia = session['media'];
    if (rawMedia is! List) {
      await database.clearPlaybackSession();
      return;
    }

    final items = <PlayableMedia>[];
    final keptOriginalIndices = <int>[];
    final iosDocumentsPath = runtime.dependencies.isIOS
        ? (await getApplicationDocumentsDirectory()).path
        : null;
    var artworkRelocated = false;
    for (var i = 0; i < rawMedia.length; i++) {
      final entry = rawMedia[i];
      if (entry is! Map) continue;
      final media = PlayableMedia.fromJson(
        Map<String, dynamic>.from(entry),
        iosDocumentsPath: iosDocumentsPath,
      );
      if (media == null) continue;
      if (!media.isContentUri &&
          !media.isNetwork &&
          !await File(media.source).exists()) {
        continue;
      }
      final artwork = await resolveRestoredArtworkUri(
        media.artUri,
        loadLibraryCoverPath: () async {
          final database = runtime.dependencies.libraryDatabase;
          final row = await database.getById(media.id);
          if (row != null) return row['coverPath'] as String?;
          final matches = await database.findByTrackAndArtist(
            media.title,
            media.artist,
          );
          for (final row in matches) {
            if (row['filePath'] == media.source) {
              return row['coverPath'] as String?;
            }
          }
          return null;
        },
      );
      items.add(
        artwork == media.artUri
            ? media
            : PlayableMedia.fromJson({...media.toJson(), 'artUri': artwork})!,
      );
      artworkRelocated |= artwork != entry['artUri'];
      keptOriginalIndices.add(i);
    }
    if (items.isEmpty) {
      await database.clearPlaybackSession();
      return;
    }

    // Remap the saved index onto the surviving list; if the current track
    // itself was dropped, land on the nearest earlier survivor at 0:00.
    final savedIndex = (session['index'] as num?)?.toInt() ?? 0;
    var index = 0;
    for (var i = 0; i < keptOriginalIndices.length; i++) {
      if (keptOriginalIndices[i] <= savedIndex) index = i;
    }
    var position = Duration(
      milliseconds: (session['positionMs'] as num?)?.toInt() ?? 0,
    );
    if (keptOriginalIndices[index] != savedIndex) {
      position = Duration.zero;
    }

    final handler = await runtime.initialize();
    await handler.restoreSession(
      items: items,
      index: index,
      position: position,
      shuffle: session['shuffle'] == true,
      originalOrder: [
        for (final i in keptOriginalIndices)
          ((rawMedia[i] as Map)['queueOriginalIndex'] as num?)?.toInt() ?? i,
      ],
      queueNeedsRewrite: items.length != rawMedia.length || artworkRelocated,
      repeatMode: AudioServiceRepeatMode.values.firstWhere(
        (mode) => mode.name == session['repeat'],
        orElse: () => AudioServiceRepeatMode.none,
      ),
    );
    _log.i(
      'Restored playback session: ${items.length} track(s), paused at '
      '${position.inSeconds}s',
    );
  } catch (e) {
    _log.w('Failed to restore playback session: $e');
  }
}

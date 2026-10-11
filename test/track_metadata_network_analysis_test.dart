import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/audio_analysis_widget.dart';
import 'package:spotiflac_android/widgets/hires_check_card.dart';

void main() {
  for (final mornye in [false, true]) {
    for (final format in ['flac', 'wav', 'mp3']) {
      testWidgets(
        'network $format exposes supported analysers (Mornye=$mornye)',
        (tester) async {
          final item = LocalLibraryItem(
            id: 'network://fixture/track.$format',
            filePath: 'network://fixture/track.$format',
            trackName: 'Network track',
            artistName: 'Artist',
            albumName: 'Album',
            scannedAt: DateTime(2026),
          );
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: mornye
                    ? MornyeTheme.build(Brightness.dark)
                    : ThemeData.dark(useMaterial3: true),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: TrackMetadataScreen(localItem: item),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.scrollUntilVisible(
            find.byType(AudioAnalysisCard),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.byType(AudioAnalysisCard), findsOneWidget);
          expect(
            tester
                .widget<AudioAnalysisCard>(find.byType(AudioAnalysisCard))
                .filePath,
            item.filePath,
          );
          expect(
            find.byType(HiResCheckCard),
            format == 'mp3' ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}

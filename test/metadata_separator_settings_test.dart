import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/app_localizations.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/screens/settings/metadata_separator_settings_page.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final mornye in [false, true]) {
    for (final size in [const Size(390, 844), const Size(844, 390)]) {
      testWidgets(
        'separator preview, save, cancel and reset ($mornye, $size)',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final container = ProviderContainer(
            overrides: [settingsProvider.overrideWith(_Settings.new)],
          );
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: ThemeData(extensions: [if (mornye) const MornyeTheme()]),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const MetadataSeparatorSettingsPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> tap(String text) async {
            final target = find.text(text).last;
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          await tap('Artist');
          await tap('Semicolon (;)');
          expect(find.text('Artist A; Artist B'), findsOneWidget);
          await tap('Save');
          expect(
            container.read(settingsProvider).metadataSeparators.artist,
            '; ',
          );
          expect(container.read(settingsProvider).metadataSeparators.genre, '');
          await tap('Artist');
          await tap('Custom separator');
          await tester.enterText(find.byType(TextField), ' | ');
          await tester.pumpAndSettle();
          expect(find.text('Artist A | Artist B'), findsOneWidget);
          await tap('Save');
          expect(
            container.read(settingsProvider).metadataSeparators.artist,
            ' | ',
          );
          await tap('Artist');
          await tap('Slash (/)');
          // Dismissing a draft must not overwrite the saved preference.
          await Navigator.of(
            tester.element(find.byType(BottomSheet).first),
          ).maybePop();
          await tester.pumpAndSettle();
          expect(
            container.read(settingsProvider).metadataSeparators.artist,
            ' | ',
          );
          await tap('Artist');
          await tap('Keep source formatting');
          await tap('Save');
          expect(
            container.read(settingsProvider).metadataSeparators.isDefault,
            isTrue,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

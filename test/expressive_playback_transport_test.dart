import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/widgets/expressive_playback_transport.dart';

void main() {
  Future<void> pumpTransport(
    WidgetTester tester, {
    required double width,
    required bool fill,
  }) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ExpressivePlaybackTransport(
                colorScheme: scheme,
                playing: false,
                loading: false,
                playTooltip: 'Play',
                previousTooltip: 'Previous',
                nextTooltip: 'Next',
                onPlayPause: () {},
                onPrevious: () {},
                onNext: () {},
                fill: fill,
                leading: const SizedBox(
                  key: ValueKey('leading'),
                  width: 48,
                  height: 48,
                ),
                trailing: const SizedBox(
                  key: ValueKey('trailing'),
                  width: 48,
                  height: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect rectOf(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));

  testWidgets('a filled row puts the side actions at its ends', (tester) async {
    await pumpTransport(tester, width: 800, fill: true);
    expect(rectOf(tester, 'leading').left, moreOrLessEquals(0));
    expect(rectOf(tester, 'trailing').right, moreOrLessEquals(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('without fill the row keeps its resting width, centered', (
    tester,
  ) async {
    await pumpTransport(tester, width: 800, fill: false);
    final leading = rectOf(tester, 'leading');
    final trailing = rectOf(tester, 'trailing');
    expect(leading.left, greaterThan(0));
    expect(800 - trailing.right, moreOrLessEquals(leading.left));
  });
}

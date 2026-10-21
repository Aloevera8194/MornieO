import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/widgets/expressive_playback_transport.dart';

void main() {
  Future<void> pumpTransport(
    WidgetTester tester, {
    required double width,
    required bool fill,
    bool settle = true,
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
    if (settle) await tester.pumpAndSettle();
  }

  Rect rectOf(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));

  testWidgets('a filled row puts the side actions at its ends', (tester) async {
    await pumpTransport(tester, width: 800, fill: true);
    expect(rectOf(tester, 'leading').left, moreOrLessEquals(0));
    expect(rectOf(tester, 'trailing').right, moreOrLessEquals(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resize never pushes a filled row past its width', (
    tester,
  ) async {
    await pumpTransport(tester, width: 432, fill: true);
    for (final width in [300.0, 600.0, 432.0]) {
      await pumpTransport(tester, width: width, fill: true);
      expect(tester.takeException(), isNull);
      expect(rectOf(tester, 'trailing').right, moreOrLessEquals(width));
    }
  });

  testWidgets('a wider row springs the buttons to their new widths', (
    tester,
  ) async {
    await pumpTransport(tester, width: 300, fill: true);
    final play = find.byTooltip('Play');
    final narrow = tester.getSize(play).width;
    await pumpTransport(tester, width: 600, fill: true, settle: false);
    await tester.pump(const Duration(milliseconds: 16));
    final growing = tester.getSize(play).width;
    await tester.pumpAndSettle();
    final wide = tester.getSize(play).width;
    expect(growing, greaterThan(narrow));
    expect(growing, lessThan(wide));
    expect(rectOf(tester, 'trailing').right, moreOrLessEquals(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a press widens the button inside the row', (tester) async {
    await pumpTransport(tester, width: 432, fill: true);
    final play = find.byTooltip('Play');
    final resting = tester.getSize(play).width;
    final gesture = await tester.startGesture(tester.getCenter(play));
    // The spring overshoots; the neighbours give way every frame of it.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(rectOf(tester, 'leading').left, moreOrLessEquals(0));
      expect(rectOf(tester, 'trailing').right, moreOrLessEquals(432));
    }
    expect(tester.getSize(play).width, greaterThan(resting * 1.1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(play).width, moreOrLessEquals(resting));
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

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/l10n/app_localizations.dart';
import 'package:mornye/screens/selection_mode_mixin.dart';
import 'package:mornye/theme/app_theme.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/utils/desktop_platform.dart';
import 'package:mornye/widgets/desktop/context_menu.dart';
import 'package:mornye/widgets/desktop/desktop_selection.dart';
import 'package:mornye/widgets/desktop/track_table.dart';
import 'package:mornye/widgets/mornye_context_menu.dart';
import 'package:mornye/widgets/track_card.dart';

Widget _app(Widget child, {bool mornye = false}) => ProviderScope(
  child: MaterialApp(
    theme: mornye ? MornyeTheme.build(Brightness.light) : AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _click(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.up();
  await tester.pump();
}

/// A song table over [SelectionModeMixin], the way the detail screens use it.
class _TableHost extends StatefulWidget {
  const _TableHost({required this.rows, this.onActivate, this.onDelete});

  final List<TrackTableRow> rows;
  final ValueChanged<String>? onActivate;
  final ValueChanged<Set<String>>? onDelete;

  @override
  State<_TableHost> createState() => _TableHostState();
}

class _TableHostState extends State<_TableHost>
    with SelectionModeMixin<_TableHost> {
  @override
  Widget build(BuildContext context) => DesktopListScope(
    onSelectAll: () => selectAll(widget.rows.map((row) => row.id)),
    onClearSelection: isSelectionMode ? exitSelectionMode : null,
    onDelete: widget.onDelete == null
        ? null
        : () => widget.onDelete!({...selectedIds}),
    onActivate: () => widget.onActivate?.call(selectionAnchorId ?? ''),
    child: CustomScrollView(
      slivers: [
        SliverTrackTable(
          rows: widget.rows,
          columns: const [
            TrackTableColumn.number,
            TrackTableColumn.title,
            TrackTableColumn.artist,
            TrackTableColumn.duration,
          ],
          selectedIds: selectedIds,
          onSelect: applyDesktopClick,
          onActivate: (id) => widget.onActivate?.call(id),
        ),
      ],
    ),
  );
}

const _rows = [
  TrackTableRow(
    id: 'b',
    number: 1,
    title: 'Bravo',
    artist: 'Zed',
    duration: Duration(minutes: 3),
  ),
  TrackTableRow(
    id: 'a',
    number: 2,
    title: 'Alpha',
    artist: 'Mike',
    duration: Duration(minutes: 5),
  ),
  TrackTableRow(
    id: 'c',
    number: 3,
    title: 'Charlie',
    artist: 'Ann',
    duration: Duration(minutes: 1),
  ),
];

List<String> _shownTitles(WidgetTester tester) {
  final titles = ['Alpha', 'Bravo', 'Charlie'];
  final positions = {
    for (final title in titles) title: tester.getTopLeft(find.text(title)).dy,
  };
  return titles..sort((a, b) => positions[a]!.compareTo(positions[b]!));
}

void main() {
  setUp(() {
    debugDesktopPlatformOverride = true;
    DesktopDoubleClick.reset();
  });

  tearDown(() {
    debugDesktopPlatformOverride = null;
    DesktopDoubleClick.reset();
  });

  List<List<ContextMenuAction>> menu(List<String> log) => [
    [
      ContextMenuAction(
        icon: Icons.play_arrow,
        label: 'Play',
        onSelected: () => log.add('play'),
      ),
    ],
    [
      ContextMenuAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () => log.add('delete'),
      ),
    ],
  ];

  Widget card(List<String> log) => Builder(
    builder: (context) => TrackCard(
      leading: const SizedBox(width: 40),
      title: 'Song',
      onTap: () {},
      onLongPress: () => log.add('long-press'),
      onContextMenu: (position) =>
          showContextMenu(context, position: position, groups: menu(log)),
    ),
  );

  group('context menus', () {
    testWidgets('Material right-click opens the long-press actions', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(_app(card(log)));

      await _rightClick(tester, find.text('Song'));
      expect(find.byType(MenuItemButton), findsNWidgets(2));
      expect(find.text('Play'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(log, ['delete']);
      expect(find.byType(MenuItemButton), findsNothing);
    });

    testWidgets('Escape closes the Material menu without an action', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(_app(card(log)));

      await _rightClick(tester, find.text('Song'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(log, isEmpty);
    });

    testWidgets('Mornye right-click opens the Mornye context menu', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(_app(card(log), mornye: true));

      await _rightClick(tester, find.text('Song'));
      expect(find.byType(MornyeContextMenu), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(log, ['play']);
      expect(find.byType(MornyeContextMenu), findsNothing);
    });

    testWidgets('Shift+F10 opens the menu of the item clicked last', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(_app(DesktopListScope(child: card(log))));

      await _click(tester, find.text('Song'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('phones keep the long press and ignore right-clicks', (
      tester,
    ) async {
      debugDesktopPlatformOverride = false;
      final log = <String>[];
      await tester.pumpWidget(_app(card(log)));

      await _rightClick(tester, find.text('Song'));
      expect(find.text('Play'), findsNothing);

      await tester.longPress(find.text('Song'));
      expect(log, ['long-press']);
    });
  });

  group('song table', () {
    testWidgets('header clicks sort ascending, descending, then restore', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const _TableHost(rows: _rows)));
      expect(_shownTitles(tester), ['Bravo', 'Alpha', 'Charlie']);

      await tester.tap(find.text('Title'));
      await tester.pump();
      expect(_shownTitles(tester), ['Alpha', 'Bravo', 'Charlie']);

      await tester.tap(find.text('Title'));
      await tester.pump();
      expect(_shownTitles(tester), ['Charlie', 'Bravo', 'Alpha']);

      await tester.tap(find.text('Title'));
      await tester.pump();
      expect(_shownTitles(tester), ['Bravo', 'Alpha', 'Charlie']);

      await tester.tap(find.text('Duration'));
      await tester.pump();
      expect(_shownTitles(tester), ['Charlie', 'Bravo', 'Alpha']);
    });

    testWidgets('quality sorts by its numbers', (tester) async {
      expect(
        compareTrackTableRows(
          const TrackTableRow(id: 'x', title: 'x', quality: '24-bit/96kHz'),
          const TrackTableRow(id: 'y', title: 'y', quality: '16-bit/44.1kHz'),
          TrackTableColumn.quality,
        ),
        greaterThan(0),
      );
      expect(
        compareTrackTableRows(
          const TrackTableRow(id: 'x', title: 'x'),
          const TrackTableRow(id: 'y', title: 'y', quality: 'MP3'),
          TrackTableColumn.quality,
        ),
        greaterThan(0),
      );
    });

    testWidgets('click selects, modifier clicks toggle and extend', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const _TableHost(rows: _rows)));
      final state = tester.state<_TableHostState>(find.byType(_TableHost));

      await _click(tester, find.text('Bravo'));
      expect(state.selectedIds, {'b'});
      expect(state.isSelectionMode, isTrue);

      await _click(tester, find.text('Alpha'));
      expect(state.selectedIds, {'a'});

      final toggle = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(toggle);
      await _click(tester, find.text('Charlie'));
      expect(state.selectedIds, {'a', 'c'});
      await _click(tester, find.text('Alpha'));
      await tester.sendKeyUpEvent(toggle);
      expect(state.selectedIds, {'c'});

      // Shift extends from the anchor (Charlie) to Bravo in shown order.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await _click(tester, find.text('Bravo'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(state.selectedIds, {'c', 'a', 'b'});
    });

    testWidgets('double click and Enter activate, Escape clears', (
      tester,
    ) async {
      final activated = <String>[];
      await tester.pumpWidget(
        _app(_TableHost(rows: _rows, onActivate: activated.add)),
      );
      final state = tester.state<_TableHostState>(find.byType(_TableHost));

      await _click(tester, find.text('Alpha'));
      await _click(tester, find.text('Alpha'));
      expect(activated, ['a']);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(activated, ['a', 'a']);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(state.selectedIds, isEmpty);
      expect(state.isSelectionMode, isFalse);
    });

    testWidgets('select all and Delete act on the whole selection', (
      tester,
    ) async {
      final deleted = <Set<String>>[];
      await tester.pumpWidget(
        _app(_TableHost(rows: _rows, onDelete: deleted.add)),
      );
      final state = tester.state<_TableHostState>(find.byType(_TableHost));

      await _click(tester, find.text('Alpha'));
      final primary = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(primary);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(primary);
      await tester.pump();
      expect(state.selectedIds, {'a', 'b', 'c'});

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(deleted, [
        {'a', 'b', 'c'},
      ]);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/theme/app_tokens.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/app_icon.dart';
import 'package:mornye/widgets/desktop/context_menu.dart';
import 'package:mornye/widgets/desktop/desktop_selection.dart';

/// A column of a [SliverTrackTable], in display order.
enum TrackTableColumn { number, title, artist, album, quality, duration }

/// One song in a [SliverTrackTable]. Plain values drive sorting; the widgets
/// only decorate the row.
class TrackTableRow {
  const TrackTableRow({
    required this.id,
    required this.title,
    this.number,
    this.artist,
    this.album,
    this.quality,
    this.duration,
    this.leading,
    this.titleTrailing,
    this.trailing,
  });

  /// Selection id, unique within the table.
  final String id;
  final String title;
  final int? number;
  final String? artist;
  final String? album;

  /// Format or quality label, such as "FLAC 24-bit/96kHz".
  final String? quality;
  final Duration? duration;

  /// Artwork at the start of the title cell.
  final Widget? leading;

  /// Badges after the title, such as Explicit or In Library.
  final Widget? titleTrailing;

  /// Row actions at the end of the row, such as the options button.
  final Widget? trailing;
}

/// Desktop song list: a header of sortable columns over one row per song.
///
/// Clicking a header sorts by that column, again reverses the order, and a
/// third click restores the original order. Rows follow the desktop list
/// gestures: a click selects, Cmd/Ctrl-click toggles, Shift-click selects a
/// range in the shown order, a double click runs [onActivate], and a
/// right-click runs [onContextMenu]. Wrap the screen in a [DesktopListScope]
/// for the keyboard.
class SliverTrackTable extends StatefulWidget {
  const SliverTrackTable({
    super.key,
    required this.rows,
    required this.columns,
    required this.selectedIds,
    required this.onSelect,
    required this.onActivate,
    this.onContextMenu,
  });

  final List<TrackTableRow> rows;
  final List<TrackTableColumn> columns;
  final Set<String> selectedIds;

  /// A click of `kind` on the row `id`; `orderedIds` lists the rows in the
  /// order shown.
  final void Function(String id, DesktopClick kind, List<String> orderedIds)
  onSelect;

  /// Plays or opens the row with this id.
  final ValueChanged<String> onActivate;

  /// Opens the row's menu at a global position.
  final void Function(String id, Offset position)? onContextMenu;

  @override
  State<SliverTrackTable> createState() => _SliverTrackTableState();
}

class _SliverTrackTableState extends State<SliverTrackTable> {
  TrackTableColumn? _sortColumn;
  bool _ascending = true;

  void _sortBy(TrackTableColumn column) {
    setState(() {
      if (_sortColumn != column) {
        _sortColumn = column;
        _ascending = true;
      } else if (_ascending) {
        _ascending = false;
      } else {
        _sortColumn = null;
      }
    });
  }

  List<TrackTableRow> get _sortedRows {
    final column = _sortColumn;
    if (column == null) return widget.rows;
    final indexed = widget.rows.indexed.toList();
    indexed.sort((a, b) {
      final order = compareTrackTableRows(a.$2, b.$2, column);
      // Equal keys keep their original order in both directions.
      if (order == 0) return a.$1.compareTo(b.$1);
      return _ascending ? order : -order;
    });
    return [for (final entry in indexed) entry.$2];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sortedRows;
    final orderedIds = [for (final row in rows) row.id];
    final hasTrailing = rows.any((row) => row.trailing != null);
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _HeaderDelegate(
            height: _TrackTableHeader.heightFor(context),
            child: _TrackTableHeader(
              columns: widget.columns,
              sortColumn: _sortColumn,
              ascending: _ascending,
              hasTrailing: hasTrailing,
              onSort: _sortBy,
            ),
          ),
        ),
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return _TrackTableRowView(
              key: ValueKey(row.id),
              row: row,
              columns: widget.columns,
              hasTrailing: hasTrailing,
              selected: widget.selectedIds.contains(row.id),
              onTap: () => handleDesktopRowClick(
                row.id,
                select: (kind) => widget.onSelect(row.id, kind, orderedIds),
                activate: () => widget.onActivate(row.id),
              ),
              onContextMenu: widget.onContextMenu == null
                  ? null
                  : (position) => widget.onContextMenu!(row.id, position),
            );
          },
        ),
      ],
    );
  }
}

/// Orders two rows by [column], ascending, with missing values last.
int compareTrackTableRows(
  TrackTableRow a,
  TrackTableRow b,
  TrackTableColumn column,
) {
  int text(String? x, String? y) {
    if (x == null || x.isEmpty) return y == null || y.isEmpty ? 0 : 1;
    if (y == null || y.isEmpty) return -1;
    return x.toLowerCase().compareTo(y.toLowerCase());
  }

  int number(num? x, num? y) {
    if (x == null) return y == null ? 0 : 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }

  return switch (column) {
    TrackTableColumn.number => number(a.number, b.number),
    TrackTableColumn.title => text(a.title, b.title),
    TrackTableColumn.artist => text(a.artist, b.artist),
    TrackTableColumn.album => text(a.album, b.album),
    TrackTableColumn.duration => number(
      a.duration?.inMilliseconds,
      b.duration?.inMilliseconds,
    ),
    TrackTableColumn.quality => _compareQuality(a.quality, b.quality),
  };
}

/// Compares quality labels by their numbers (bit depth, then sample rate or
/// bitrate), so "24-bit/96kHz" sorts above "16-bit/44.1kHz".
int _compareQuality(String? a, String? b) {
  if (a == null || a.isEmpty) return b == null || b.isEmpty ? 0 : 1;
  if (b == null || b.isEmpty) return -1;
  final pattern = RegExp(r'\d+(?:\.\d+)?');
  final x = [for (final m in pattern.allMatches(a)) double.parse(m[0]!)];
  final y = [for (final m in pattern.allMatches(b)) double.parse(m[0]!)];
  for (var i = 0; i < x.length && i < y.length; i++) {
    final order = x[i].compareTo(y[i]);
    if (order != 0) return order;
  }
  final order = x.length.compareTo(y.length);
  return order != 0 ? order : a.toLowerCase().compareTo(b.toLowerCase());
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}

/// Shared column geometry, so header and rows line up.
class _Columns {
  static const double number = 44;
  static const double quality = 132;
  static const double duration = 64;
  static const double trailing = 52;
  static const double gap = 12;

  static int flex(TrackTableColumn column) => switch (column) {
    TrackTableColumn.title => 5,
    TrackTableColumn.artist || TrackTableColumn.album => 3,
    _ => 0,
  };

  static double? width(TrackTableColumn column) => switch (column) {
    TrackTableColumn.number => number,
    TrackTableColumn.quality => quality,
    TrackTableColumn.duration => duration,
    _ => null,
  };

  static bool alignEnd(TrackTableColumn column) =>
      column == TrackTableColumn.number || column == TrackTableColumn.duration;

  static List<Widget> layout({
    required List<TrackTableColumn> columns,
    required Widget Function(TrackTableColumn column) cell,
    required bool hasTrailing,
    Widget? trailing,
  }) => [
    for (final column in columns) ...[
      if (_Columns.width(column) case final width?)
        SizedBox(width: width, child: cell(column))
      else
        Expanded(flex: _Columns.flex(column), child: cell(column)),
      const SizedBox(width: gap),
    ],
    if (hasTrailing)
      SizedBox(width: _Columns.trailing, child: trailing)
    else
      const SizedBox(width: gap),
  ];
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  const _HeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(_HeaderDelegate oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
}

class _TrackTableHeader extends StatelessWidget {
  const _TrackTableHeader({
    required this.columns,
    required this.sortColumn,
    required this.ascending,
    required this.hasTrailing,
    required this.onSort,
  });

  final List<TrackTableColumn> columns;
  final TrackTableColumn? sortColumn;
  final bool ascending;
  final bool hasTrailing;
  final ValueChanged<TrackTableColumn> onSort;

  /// Tall enough for a 32dp pointer target, growing with the text size.
  static double heightFor(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(20) + 16;

  String _label(BuildContext context, TrackTableColumn column) {
    final l10n = context.l10n;
    return switch (column) {
      TrackTableColumn.number => l10n.trackTrackNumber,
      TrackTableColumn.title => l10n.editMetadataFieldTitle,
      TrackTableColumn.artist => l10n.trackArtist,
      TrackTableColumn.album => l10n.trackAlbum,
      TrackTableColumn.quality => l10n.audioInfoQuality,
      TrackTableColumn.duration => l10n.trackDuration,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = theme.textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    Widget cell(TrackTableColumn column) {
      final label = _label(context, column);
      final sorted = sortColumn == column;
      final end = _Columns.alignEnd(column);
      final text = Text(
        column == TrackTableColumn.number ? '#' : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: sorted ? style?.copyWith(color: colorScheme.onSurface) : style,
      );
      final arrow = AppIcon.adaptive(
        ascending ? Icons.arrow_upward : Icons.arrow_downward,
        size: 14,
        color: colorScheme.onSurface,
      );
      return Semantics(
        button: true,
        label: sorted
            ? (ascending
                  ? context.l10n.desktopTableSortedAscending(label)
                  : context.l10n.desktopTableSortedDescending(label))
            : label,
        onTap: () => onSort(column),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onSort(column),
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: heightFor(context),
            child: Row(
              mainAxisAlignment: end
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                if (sorted && end) ...[arrow, const SizedBox(width: 2)],
                Flexible(child: text),
                if (sorted && !end) ...[const SizedBox(width: 2), arrow],
              ],
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.tokens.gapSm),
          child: Row(
            children: _Columns.layout(
              columns: columns,
              cell: cell,
              hasTrailing: hasTrailing,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackTableRowView extends StatelessWidget {
  const _TrackTableRowView({
    super.key,
    required this.row,
    required this.columns,
    required this.hasTrailing,
    required this.selected,
    required this.onTap,
    required this.onContextMenu,
  });

  final TrackTableRow row;
  final List<TrackTableColumn> columns;
  final bool hasTrailing;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.tokens;
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    Widget plain(String? value, {bool end = false}) => Text(
      value ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: secondary?.copyWith(
        fontFeatures: end ? const [FontFeature.tabularFigures()] : null,
      ),
    );

    Widget cell(TrackTableColumn column) => switch (column) {
      TrackTableColumn.number => plain(row.number?.toString(), end: true),
      TrackTableColumn.title => Row(
        children: [
          if (row.leading != null) ...[row.leading!, const SizedBox(width: 10)],
          Flexible(
            child: Text(
              row.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (row.titleTrailing != null) ...[
            const SizedBox(width: 6),
            row.titleTrailing!,
          ],
        ],
      ),
      TrackTableColumn.artist => plain(row.artist),
      TrackTableColumn.album => plain(row.album),
      TrackTableColumn.quality => plain(row.quality),
      TrackTableColumn.duration => plain(
        row.duration == null ? null : _formatDuration(row.duration!),
        end: true,
      ),
    };

    final selectedFill = context.isMornye
        ? colorScheme.primary.withValues(alpha: 0.16)
        : colorScheme.secondaryContainer;
    return Semantics(
      selected: selected,
      label: [row.title, ?row.artist].join(', '),
      child: DesktopContextMenuRegion(
        onContextMenu: onContextMenu,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.gapXs, vertical: 1),
          child: Material(
            color: selected ? selectedFill : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: tokens.gapXs),
                  child: Row(
                    children: _Columns.layout(
                      columns: columns,
                      cell: cell,
                      hasTrailing: hasTrailing,
                      trailing: row.trailing,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/theme/app_tokens.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/app_icon.dart';
import 'package:mornye/widgets/desktop/context_menu.dart';
import 'package:mornye/widgets/desktop/desktop_selection.dart';

/// A column of a [SliverTrackTable], in display order.
enum TrackTableColumn { number, title, artist, album, quality, duration }

/// The column a [SliverTrackTable] is sorted by, and its direction.
typedef TrackTableSort = ({TrackTableColumn column, bool ascending});

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

  /// Row actions at the end of the row, such as the options button. They show
  /// on hover, selection or keyboard focus.
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
///
/// Lists sorted by their source, such as the paged Library, pass [onSort]:
/// the table then shows [sort] and leaves [rows] in the given order, and only
/// [sortableColumns] take header clicks.
class SliverTrackTable extends StatefulWidget {
  const SliverTrackTable({
    super.key,
    required this.rows,
    required this.columns,
    required this.selectedIds,
    required this.onSelect,
    required this.onActivate,
    this.onContextMenu,
    this.sort,
    this.onSort,
    this.sortableColumns,
    this.albumLayout = false,
    this.albumArtist,
  });

  /// The album page layout of Apple Music: no column headers, the number,
  /// title and duration with a "More" button, the artist under the title only
  /// when it differs from [albumArtist], separators from the title column,
  /// and a play glyph in place of the number under the pointer. [columns],
  /// sorting and the rows' trailing widgets do not apply.
  final bool albumLayout;

  /// The album's artist, which album rows leave out.
  final String? albumArtist;

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

  /// The sort shown when [onSort] is set; null is the source's own order.
  final TrackTableSort? sort;

  /// Asks the source to sort by the next state of a clicked header, null
  /// when a third click restores the source's own order.
  final ValueChanged<TrackTableSort?>? onSort;

  /// Columns whose headers sort; all of them when null.
  final Set<TrackTableColumn>? sortableColumns;

  @override
  State<SliverTrackTable> createState() => _SliverTrackTableState();
}

class _SliverTrackTableState extends State<SliverTrackTable> {
  TrackTableSort? _localSort;

  TrackTableSort? get _sort => widget.onSort == null ? _localSort : widget.sort;

  void _sortBy(TrackTableColumn column) {
    final current = _sort;
    final TrackTableSort? next;
    if (current?.column != column) {
      next = (column: column, ascending: true);
    } else if (current!.ascending) {
      next = (column: column, ascending: false);
    } else {
      next = null;
    }
    final onSort = widget.onSort;
    if (onSort != null) {
      onSort(next);
    } else {
      setState(() => _localSort = next);
    }
  }

  List<TrackTableRow> get _sortedRows {
    final sort = _localSort;
    if (widget.onSort != null || sort == null) return widget.rows;
    final (:column, :ascending) = sort;
    final indexed = widget.rows.indexed.toList();
    indexed.sort((a, b) {
      final order = compareTrackTableRows(a.$2, b.$2, column);
      // Equal keys keep their original order in both directions.
      if (order == 0) return a.$1.compareTo(b.$1);
      return ascending ? order : -order;
    });
    return [for (final entry in indexed) entry.$2];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sortedRows;
    final sort = _sort;
    final orderedIds = [for (final row in rows) row.id];
    final hasTrailing = rows.any((row) => row.trailing != null);
    if (widget.albumLayout) {
      final albumArtist = widget.albumArtist?.trim().toLowerCase();
      return SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final artist = row.artist?.trim();
          return _AlbumRowView(
            key: ValueKey(row.id),
            row: row,
            artist:
                artist == null ||
                    artist.isEmpty ||
                    artist.toLowerCase() == albumArtist
                ? null
                : artist,
            last: index == rows.length - 1,
            selected: widget.selectedIds.contains(row.id),
            onTap: () => handleDesktopRowClick(
              row.id,
              select: (kind) => widget.onSelect(row.id, kind, orderedIds),
              activate: () => widget.onActivate(row.id),
            ),
            onPlay: () => widget.onActivate(row.id),
            onContextMenu: widget.onContextMenu == null
                ? null
                : (position) => widget.onContextMenu!(row.id, position),
          );
        },
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _HeaderDelegate(
            height: _TrackTableHeader.heightFor(context),
            child: _TrackTableHeader(
              columns: widget.columns,
              sortColumn: sort?.column,
              ascending: sort?.ascending ?? true,
              sortableColumns: widget.sortableColumns,
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
    required this.sortableColumns,
    required this.hasTrailing,
    required this.onSort,
  });

  final List<TrackTableColumn> columns;
  final TrackTableColumn? sortColumn;
  final bool ascending;
  final Set<TrackTableColumn>? sortableColumns;
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
      final sortable = sortableColumns?.contains(column) ?? true;
      return Semantics(
        button: sortable,
        label: sorted
            ? (ascending
                  ? context.l10n.desktopTableSortedAscending(label)
                  : context.l10n.desktopTableSortedDescending(label))
            : label,
        onTap: sortable ? () => onSort(column) : null,
        excludeSemantics: true,
        child: InkWell(
          onTap: sortable ? () => onSort(column) : null,
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

class _TrackTableRowView extends StatefulWidget {
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

  /// Desktop density: compact rows for Mornye, the Material list height.
  static double minHeightFor(BuildContext context) =>
      context.isMornye ? 40 : 48;

  @override
  State<_TrackTableRowView> createState() => _TrackTableRowViewState();
}

class _TrackTableRowViewState extends State<_TrackTableRowView> {
  bool _hovered = false;
  bool _trailingFocused = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final columns = widget.columns;
    final hasTrailing = widget.hasTrailing;
    final selected = widget.selected;
    final onTap = widget.onTap;
    final onContextMenu = widget.onContextMenu;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.tokens;
    // Row actions appear for the row under the pointer, the selection, or
    // keyboard focus, so a long list does not repeat them on every row.
    final trailing = row.trailing == null
        ? null
        : Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (focused) =>
                setState(() => _trailingFocused = focused),
            child: AnimatedOpacity(
              opacity: _hovered || selected || _trailingFocused ? 1 : 0,
              duration: tokens.motionFast,
              child: row.trailing,
            ),
          );
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
              onHover: (hovered) => setState(() => _hovered = hovered),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: _TrackTableRowView.minHeightFor(context),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: tokens.gapXs),
                  child: Row(
                    children: _Columns.layout(
                      columns: columns,
                      cell: cell,
                      hasTrailing: hasTrailing,
                      trailing: trailing,
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

/// One song of a [SliverTrackTable.albumLayout] list.
class _AlbumRowView extends StatefulWidget {
  const _AlbumRowView({
    super.key,
    required this.row,
    required this.artist,
    required this.last,
    required this.selected,
    required this.onTap,
    required this.onPlay,
    required this.onContextMenu,
  });

  final TrackTableRow row;

  /// Shown under the title; null when it is the album's artist.
  final String? artist;
  final bool last;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final ValueChanged<Offset>? onContextMenu;

  @override
  State<_AlbumRowView> createState() => _AlbumRowViewState();
}

class _AlbumRowViewState extends State<_AlbumRowView> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.tokens;
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final active = _hovered || widget.selected || _focused;
    final l10n = MaterialLocalizations.of(context);
    final onContextMenu = widget.onContextMenu;
    final number = SizedBox(
      width: 32,
      child: _hovered
          ? IconButton(
              tooltip: context.l10n.tooltipPlay,
              onPressed: widget.onPlay,
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: AppIcon.adaptive(
                Icons.play_arrow_rounded,
                size: 16,
                color: scheme.primary,
              ),
            )
          : Text(
              row.number?.toString() ?? '',
              textAlign: TextAlign.end,
              style: secondary,
            ),
    );
    final more = onContextMenu == null
        ? const SizedBox(width: 32)
        : Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: tokens.motionFast,
              child: Builder(
                builder: (buttonContext) => IconButton(
                  tooltip: l10n.showMenuTooltip,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: AppIcon.adaptive(
                    Icons.more_horiz,
                    size: 20,
                    color: scheme.primary,
                  ),
                  onPressed: () => onContextMenu(
                    contextMenuPositionBelow(buttonContext) ?? Offset.zero,
                  ),
                ),
              ),
            ),
          );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
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
        if (widget.artist != null)
          Text(
            widget.artist!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
    final selectedFill = context.isMornye
        ? scheme.primary.withValues(alpha: 0.16)
        : scheme.secondaryContainer;
    return Semantics(
      selected: widget.selected,
      label: [row.title, ?widget.artist].join(', '),
      child: DesktopContextMenuRegion(
        onContextMenu: onContextMenu,
        child: Material(
          color: widget.selected || _hovered
              ? (widget.selected
                    ? selectedFill
                    : scheme.onSurface.withValues(alpha: 0.05))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHover: (hovered) => setState(() => _hovered = hovered),
            hoverColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 46),
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: tokens.gapXs),
                child: Row(
                  children: [
                    number,
                    const SizedBox(width: 14),
                    // The separator starts at the title, as in Apple Music.
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: widget.last
                              ? null
                              : Border(
                                  bottom: BorderSide(
                                    color: scheme.outlineVariant.withValues(
                                      alpha: 0.6,
                                    ),
                                    width: 0.5,
                                  ),
                                ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 46),
                          child: Row(
                            children: [
                              Expanded(child: title),
                              const SizedBox(width: 12),
                              Text(
                                row.duration == null
                                    ? ''
                                    : _formatDuration(row.duration!),
                                style: secondary,
                              ),
                              const SizedBox(width: 8),
                              more,
                              SizedBox(width: tokens.gapXs),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

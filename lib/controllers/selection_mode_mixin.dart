import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mornye/utils/ordered_range_selection.dart';
import 'package:mornye/widgets/desktop/desktop_selection.dart';

/// Shared multi-select state for list screens: enter/exit selection mode,
/// toggle individual items, select all, and prune ids that fell out of the
/// current item list. Mix into a `State<T>` alongside the screen's own
/// per-item lookups. Used by the album, artist, playlist, downloaded album,
/// local album and library tracks folder screens; queue_tab keeps its own
/// selection state.
///
/// Desktop clicks go through [applyDesktopClick] and
/// [selectForContextMenu], which drive the same selection mode.
mixin SelectionModeMixin<T extends StatefulWidget> on State<T> {
  bool isSelectionMode = false;
  final Set<String> selectedIds = {};

  /// Where a desktop Shift-click range starts: the item clicked last without
  /// Shift.
  String? selectionAnchorId;

  void enterSelectionMode(String itemId) {
    HapticFeedback.mediumImpact();
    setState(() {
      isSelectionMode = true;
      selectedIds.add(itemId);
      selectionAnchorId = itemId;
    });
  }

  void exitSelectionMode() {
    setState(() {
      isSelectionMode = false;
      selectedIds.clear();
      selectionAnchorId = null;
    });
  }

  /// Applies a desktop click of [kind] on [itemId]. [orderedIds] lists the
  /// visible items in display order, for Shift ranges.
  void applyDesktopClick(
    String itemId,
    DesktopClick kind,
    List<String> orderedIds,
  ) {
    setState(() {
      switch (kind) {
        case DesktopClick.replace:
          selectedIds
            ..clear()
            ..add(itemId);
          selectionAnchorId = itemId;
        case DesktopClick.toggle:
          selectionAnchorId = toggleOrderedSelection(
            selected: selectedIds,
            target: itemId,
          );
        case DesktopClick.extend:
          // The range replaces the selection and keeps its anchor, as in
          // Finder and Explorer.
          final anchor = selectionAnchorId;
          selectedIds.clear();
          addOrderedSelectionRange(
            selected: selectedIds,
            visibleItems: orderedIds,
            target: itemId,
            anchor: anchor,
          );
          selectionAnchorId = anchor ?? itemId;
      }
      isSelectionMode = selectedIds.isNotEmpty;
    });
  }

  /// A desktop right-click outside the selection selects only that item, so
  /// the menu acts on the item it was opened on.
  void selectForContextMenu(String itemId) {
    if (selectedIds.contains(itemId)) return;
    applyDesktopClick(itemId, DesktopClick.replace, const []);
  }

  void toggleSelection(String itemId) {
    setState(() {
      if (selectedIds.contains(itemId)) {
        selectedIds.remove(itemId);
        if (selectedIds.isEmpty) {
          isSelectionMode = false;
        }
      } else {
        selectedIds.add(itemId);
      }
    });
  }

  /// Adds [ids] to the selection, entering selection mode for desktop
  /// Cmd/Ctrl+A.
  void selectAll(Iterable<String> ids) {
    setState(() {
      selectedIds.addAll(ids);
      if (selectedIds.isNotEmpty) isSelectionMode = true;
    });
  }

  /// Drops ids no longer present in [validIds]; call from build() with the
  /// current item ids. Exits selection mode next frame if that empties it.
  void pruneSelection(Set<String> validIds) {
    selectedIds.removeWhere((id) => !validIds.contains(id));
    if (selectedIds.isEmpty && isSelectionMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => isSelectionMode = false);
      });
    }
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/app_alert_dialog.dart';
import 'package:spotiflac_android/widgets/app_choice_chip.dart';
import 'package:spotiflac_android/widgets/app_content_card.dart';
import 'package:spotiflac_android/widgets/app_text_field.dart';
import 'package:spotiflac_android/services/local_track_batch_actions.dart';
import 'package:spotiflac_android/services/shell_navigation_service.dart';
import 'package:spotiflac_android/widgets/error_card.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/swipe_delete_dismissible.dart';
import 'package:spotiflac_android/widgets/track_card.dart';
import 'package:spotiflac_android/theme/app_motion.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/material_expressive.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/app_icon.dart';
import 'package:spotiflac_android/widgets/app_icon_button.dart';
import 'package:spotiflac_android/widgets/app_loading_indicator.dart';
import 'package:spotiflac_android/widgets/app_progress_indicator.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/expressive_button.dart';
import 'package:spotiflac_android/widgets/app_search_field.dart';
import 'package:spotiflac_android/widgets/app_snack_bar.dart';
import 'package:spotiflac_android/widgets/library_search_results.dart';
import 'package:spotiflac_android/widgets/library_track_selection_bar.dart';
import 'package:spotiflac_android/widgets/library_selection_playback_actions.dart';
import 'package:spotiflac_android/widgets/local_library_artwork_builder.dart';
import 'package:spotiflac_android/widgets/library_playlist_drag_source.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_3_expressive/material_3_expressive.dart'
    show
        M3EButtonGroup,
        M3EButtonGroupAction,
        M3EButtonGroupType,
        M3EButtonSize,
        M3EButtonStyle;
import 'package:spotiflac_android/providers/library_browse_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/widgets/app_shape.dart';
import 'package:spotiflac_android/widgets/library_fast_scroller.dart';
import 'package:spotiflac_android/widgets/player_artwork.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/audio_quality_badge_policy.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/library_format_filters.dart';
import 'package:spotiflac_android/utils/ordered_range_selection.dart';
import 'package:spotiflac_android/utils/saf_download_tree.dart';
import 'package:spotiflac_android/models/download_item.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/unified_library_item.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/services/music_player_service.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/album_completeness.dart';
import 'package:spotiflac_android/services/local_track_redownload_service.dart';
import 'package:spotiflac_android/services/batch_track_actions.dart';
import 'package:spotiflac_android/services/downloaded_embedded_cover_resolver.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/screens/listening_rewind_screen.dart';
import 'package:spotiflac_android/screens/favorite_artists_screen.dart';
import 'package:spotiflac_android/screens/downloaded_album_screen.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotiflac_android/services/cover_cache_manager.dart';
import 'package:spotiflac_android/screens/library_tracks_folder_screen.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/screens/mornye_library_screen.dart';
import 'package:spotiflac_android/controllers/queue_library_refresh_policy.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/widgets/download_service_picker.dart';
import 'package:spotiflac_android/widgets/animated_library_sliver_grid.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';
import 'package:spotiflac_android/widgets/smoothed_progress.dart';
import 'package:spotiflac_android/widgets/scroll_edge_fade.dart';
import 'package:spotiflac_android/widgets/two_finger_pinch_listener.dart';

part 'queue_tab_helpers.dart';
part 'queue_tab_widgets.dart';
part 'queue_tab_selection.dart';
part 'queue_tab_navigation.dart';
part 'queue_tab_collection_items.dart';
part 'queue_tab_filter_widgets.dart';
part 'queue_tab_sections.dart';
part 'queue_tab_batch_actions.dart';
part 'queue_tab_item_widgets.dart';
part 'queue_tab_download_labels.dart';
part 'queue_tab_download_dialogs.dart';
part 'queue_tab_filter_sheet.dart';

DownloadHistoryItem? _historyItemForCompletionBridge(
  DownloadItem item,
  List<DownloadHistoryItem> historyItems,
) {
  final filePath = item.filePath?.trim();
  if (filePath != null && filePath.isNotEmpty) {
    for (final historyItem in historyItems) {
      if (historyItem.filePath == filePath) return historyItem;
    }
  }

  for (final historyItem in historyItems) {
    if (historyItem.id == item.id) return historyItem;
  }

  final trackId = item.track.id.trim();
  if (trackId.isNotEmpty) {
    for (final historyItem in historyItems) {
      if (historyItem.spotifyId == trackId) return historyItem;
    }
  }

  final isrc = item.track.isrc?.trim();
  if (isrc != null && isrc.isNotEmpty) {
    for (final historyItem in historyItems) {
      if (historyItem.isrc == isrc) return historyItem;
    }
  }

  return null;
}

class QueueTab extends ConsumerStatefulWidget {
  final String? librarySection;
  final bool isTabActive;

  const QueueTab({super.key, this.librarySection, this.isTabActive = true});

  @override
  ConsumerState<QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends ConsumerState<QueueTab> {
  static const int _libraryPageSize = 300;
  final LibraryFileAvailabilityCache _fileExistsCache =
      LibraryFileAvailabilityCache();
  late final CompletionBridgePlayableProbeCache _completionBridgePlayableProbe;
  static const double _libraryGridMinExtent = 92;
  static const double _libraryGridDefaultExtent = 126;
  static const double _libraryGridMaxExtent = 190;
  bool _embeddedCoverRefreshScheduled = false;
  // Version counter to trigger targeted cover image rebuilds
  // without rebuilding the entire widget tree via setState.
  final ValueNotifier<int> _embeddedCoverVersion = ValueNotifier<int>(0);

  bool _isSelectionMode = false;
  bool _isDraggingLibraryTrack = false;
  final Set<String> _selectedIds = {};
  String? _selectionAnchorId;
  final SelectionOverlayController _selectionOverlay =
      SelectionOverlayController();
  List<UnifiedLibraryItem> _selectionOverlayItems = const [];
  double _selectionOverlayBottomPadding = 0;

  /// Keeps the selection overlays hidden while a modal launched from the
  /// selection toolbar is open, so they don't reappear over its animation.
  bool _suppressSelectionOverlay = false;

  bool _isPlaylistSelectionMode = false;
  final Set<String> _selectedPlaylistIds = {};
  final SelectionOverlayController _playlistSelectionOverlay =
      SelectionOverlayController();
  List<UserPlaylistCollection> _playlistSelectionOverlayItems = const [];
  double _playlistSelectionOverlayBottomPadding = 0;

  PageController? _filterPageController;

  /// Pages of the Library pager: Songs, Albums, Artists and Playlists.
  /// Singles share the Albums page behind [_albumsShowSingles].
  final List<String> _filterModes = ['all', 'albums', 'artists', 'playlists'];
  bool _albumsShowSingles = false;

  int _pageIndexFor(String mode) =>
      _filterModes.indexOf(mode == 'singles' ? 'albums' : mode);

  /// Data mode of the page at [index], resolving Albums to Singles when the
  /// Albums page shows singles.
  String _modeForPage(int index) {
    final mode = _filterModes[index];
    return mode == 'albums' && _albumsShowSingles ? 'singles' : mode;
  }

  bool _isPageControllerInitialized = false;
  bool _wasTabVisible = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  Timer? _searchDebounce;
  final Map<String, DownloadItem> _completionBridge = {};
  final Map<String, DateTime> _completionBridgeAt = {};
  final Set<String> _bridgePrecacheStarted = {};
  String? _filterSource;
  String? _filterQuality;
  String? _filterFormat;
  String? _filterMetadata;
  String _sortMode = 'latest';
  String _libraryQualityLabelMode = AppSettings.libraryQualityLabelBitDepthOnly;
  double _libraryGridExtent = _libraryGridDefaultExtent;
  double? _libraryGridPinchStartExtent;
  final Map<String, int> _libraryPageOffsetByFilter = {};
  bool _libraryPageLoadScheduled = false;

  final Map<_QueueLibraryCountsRequest, QueueLibraryCounts>
  _queueLibraryCountsCache = {};
  final Map<_QueueLibraryPageRequest, _QueueLibraryPageData>
  _queueLibraryPageDataCache = {};
  DateTime? _lastBlankLibraryRepairAt;

  double _queueCoverSize() {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final scale = (shortestSide / 390).clamp(0.82, 1.0);
    final textScale = effectiveTextScale(context);
    return (56 * scale * (1 + ((textScale - 1) * 0.12))).clamp(46.0, 56.0);
  }

  double get _libraryAlbumGridExtent =>
      (_libraryGridExtent * 1.45).clamp(150.0, 300.0);

  /// setState is @protected, so the extension part files route rebuilds
  /// through this forwarder.
  void _setState(VoidCallback fn) => setState(fn);

  void _handleLibraryGridPinchStart() {
    _libraryGridPinchStartExtent = _libraryGridExtent;
  }

  void _handleLibraryGridPinchUpdate(double scale) {
    final startExtent = _libraryGridPinchStartExtent;
    if (startExtent == null) return;

    final nextExtent = (startExtent * scale).clamp(
      _libraryGridMinExtent,
      _libraryGridMaxExtent,
    );
    if ((nextExtent - _libraryGridExtent).abs() < 0.5) return;
    setState(() => _libraryGridExtent = nextExtent);
  }

  void _handleLibraryGridPinchEnd() {
    _libraryGridPinchStartExtent = null;
  }

  @override
  void initState() {
    super.initState();
    _completionBridgePlayableProbe = CompletionBridgePlayableProbeCache(
      onPlayable: _fileExistsCache.markExists,
    );
  }

  void _initializePageController() {
    if (_isPageControllerInitialized) return;
    _isPageControllerInitialized = true;
    final settings = ref.read(settingsProvider);
    final initialFilter =
        widget.librarySection ??
        (settings.defaultLibraryView == 'last'
            ? settings.historyFilterMode
            : settings.defaultLibraryView);
    final initialPage = _pageIndexFor(
      initialFilter,
    ).clamp(0, _filterModes.length - 1);
    _albumsShowSingles = initialFilter == 'singles';
    final initialMode = _modeForPage(initialPage);
    if (widget.librarySection == null &&
        settings.historyFilterMode != initialMode) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(settingsProvider.notifier).setHistoryFilterMode(initialMode);
      });
    }
    _filterPageController = PageController(initialPage: initialPage);
  }

  /// When the shell switches back to this tab and a fixed default view is
  /// configured, jump the filter pager to it.
  void _applyDefaultLibraryViewOnTabVisible() {
    if (widget.librarySection != null) return;
    // Route transitions also disable TickerMode. Only a shell tab change
    // should reset the user's current album/single view.
    final isVisible = widget.isTabActive;
    final becameVisible = isVisible && !_wasTabVisible;
    _wasTabVisible = isVisible;
    if (!becameVisible) return;
    final defaultView = ref.read(settingsProvider).defaultLibraryView;
    if (defaultView == 'last') return;
    final index = _pageIndexFor(defaultView);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_filterModes[index] == 'albums') {
        _setState(() => _albumsShowSingles = defaultView == 'singles');
      }
      if (ref.read(settingsProvider).historyFilterMode != defaultView) {
        ref.read(settingsProvider.notifier).setHistoryFilterMode(defaultView);
      }
      final controller = _filterPageController;
      if (controller != null &&
          controller.hasClients &&
          controller.page?.round() != index) {
        controller.jumpToPage(index);
      }
    });
  }

  @override
  void dispose() {
    _hideSelectionOverlay();
    _hidePlaylistSelectionOverlay();
    _fileExistsCache.dispose();
    _completionBridgePlayableProbe.dispose();
    _embeddedCoverVersion.dispose();
    _filterPageController?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final normalized = value.trim().toLowerCase();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || _searchQuery == normalized) return;
      setState(() {
        _searchQuery = normalized;
        _resetLibraryPaging();
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    if (_searchQuery.isEmpty) return;
    setState(() {
      _searchQuery = '';
      _resetLibraryPaging();
    });
  }

  int _libraryPageOffsetFor(String filterMode) =>
      _libraryPageOffsetByFilter[filterMode] ?? 0;

  void _resetLibraryOffsets() {
    _libraryPageOffsetByFilter.clear();
  }

  void _resetLibraryPaging() {
    _resetLibraryOffsets();
    _queueLibraryPageDataCache.clear();
  }

  void _loadMoreLibraryItems({
    required String filterMode,
    required bool hasMoreLibrary,
  }) {
    if (_libraryPageLoadScheduled) return;
    _libraryPageLoadScheduled = true;
    setState(() {
      if (hasMoreLibrary) {
        _libraryPageOffsetByFilter[filterMode] =
            _libraryPageOffsetFor(filterMode) + _libraryPageSize;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _libraryPageLoadScheduled = false;
    });
  }

  QueueLibraryCounts _resolveQueueLibraryCounts(
    AsyncValue<QueueLibraryCounts> value,
    _QueueLibraryCountsRequest request, {
    QueueLibraryCounts? nonEmptyFallback,
  }) {
    return value.maybeWhen(
      data: (counts) {
        final cached = _queueLibraryCountsCache[request];
        final resolved = resolveQueueLibraryCountsSnapshot(
          current: counts,
          cached: cached,
          activeDownloadFallback: nonEmptyFallback,
        );
        _queueLibraryCountsCache[request] = resolved;
        _trimQueueLibraryCountsCache();
        return resolved;
      },
      orElse: () =>
          _queueLibraryCountsCache[request] ??
          nonEmptyFallback ??
          const QueueLibraryCounts(
            allTrackCount: 0,
            albumCount: 0,
            singleTrackCount: 0,
          ),
    );
  }

  /// [nonEmptyFallback] is non-null when an in-memory snapshot is available;
  /// it is only invoked when no cached or live page has content.
  _QueueLibraryPageData _resolveQueueLibraryPageData(
    AsyncValue<_QueueLibraryPageData>? value,
    _QueueLibraryPageRequest request, {
    _QueueLibraryPageData Function()? nonEmptyFallback,
  }) {
    void storePage(_QueueLibraryPageData data) {
      final cached = _cachedQueueLibraryPageAt(request, request.offset);
      if (shouldRetainQueueLibraryPageSnapshot(
        currentIsEmpty: data.isEmpty,
        cachedHasContent: cached != null && !cached.isEmpty,
        activeDownloadFallbackAvailable: nonEmptyFallback != null,
      )) {
        return;
      }
      final staleRequests = _queueLibraryPageDataCache.keys
          .where(
            (cachedRequest) =>
                cachedRequest.offset == request.offset &&
                cachedRequest != request &&
                _sameQueueLibraryPageScope(cachedRequest, request),
          )
          .toList(growable: false);
      for (final staleRequest in staleRequests) {
        _queueLibraryPageDataCache.remove(staleRequest);
      }
      _queueLibraryPageDataCache[request] = data;
      _trimQueueLibraryPageDataCache(protectedRequest: request);
    }

    if (value != null) {
      final liveData = value.asData?.value;
      if (liveData != null) {
        storePage(liveData);
      }
      value.whenOrNull(data: storePage);
    }

    final pages = <_QueueLibraryPageData>[];
    for (var offset = 0; offset <= request.offset; offset += _libraryPageSize) {
      final page = _cachedQueueLibraryPageAt(request, offset);
      if (page != null) pages.add(page);
    }

    final combined = _QueueLibraryPageData.combine(pages);
    if (combined.isEmpty && nonEmptyFallback != null) {
      return nonEmptyFallback();
    }
    return combined;
  }

  void _invalidateLibraryDataCaches() {
    _queueLibraryCountsCache.clear();
    _queueLibraryPageDataCache.clear();
  }

  void _scheduleBlankLibraryRepair({
    required bool hasQueueItems,
    required bool hasLibraryContent,
    required bool hasAnyLibraryItems,
    required bool isLibraryPageLoading,
  }) {
    if (!hasQueueItems ||
        hasLibraryContent ||
        hasAnyLibraryItems ||
        isLibraryPageLoading) {
      return;
    }
    final now = DateTime.now();
    final last = _lastBlankLibraryRepairAt;
    if (last != null && now.difference(last) < const Duration(seconds: 8)) {
      return;
    }
    _lastBlankLibraryRepairAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _invalidateLibraryDataCaches();
      ref.read(downloadHistoryProvider.notifier).reloadFromStorage();
      if (ref.read(settingsProvider).localLibraryEnabled) {
        ref.read(localLibraryProvider.notifier).reloadFromStorage();
      }
      setState(() {});
    });
  }

  void _trimQueueLibraryCountsCache() {
    const maxCountEntries = 24;
    while (_queueLibraryCountsCache.length > maxCountEntries) {
      _queueLibraryCountsCache.remove(_queueLibraryCountsCache.keys.first);
    }
  }

  bool _isProtectedQueueLibraryPage(
    _QueueLibraryPageRequest request,
    _QueueLibraryPageRequest protectedRequest,
  ) {
    return _sameQueueLibraryPageScope(request, protectedRequest) &&
        request.limit == protectedRequest.limit &&
        request.offset <= protectedRequest.offset;
  }

  bool _sameQueueLibraryPageScope(
    _QueueLibraryPageRequest a,
    _QueueLibraryPageRequest b,
  ) {
    return a.filterMode == b.filterMode &&
        a.limit == b.limit &&
        a.searchQuery == b.searchQuery &&
        a.filterSource == b.filterSource &&
        a.filterQuality == b.filterQuality &&
        a.filterFormat == b.filterFormat &&
        a.filterMetadata == b.filterMetadata &&
        a.sortMode == b.sortMode &&
        a.localLibraryEnabled == b.localLibraryEnabled;
  }

  _QueueLibraryPageData? _cachedQueueLibraryPageAt(
    _QueueLibraryPageRequest request,
    int offset,
  ) {
    for (final entry in _queueLibraryPageDataCache.entries) {
      if (entry.key.offset == offset &&
          _sameQueueLibraryPageScope(entry.key, request)) {
        return entry.value;
      }
    }
    return null;
  }

  void _trimQueueLibraryPageDataCache({
    required _QueueLibraryPageRequest protectedRequest,
  }) {
    const maxPageEntries = 96;
    while (_queueLibraryPageDataCache.length > maxPageEntries) {
      final removableKey = _queueLibraryPageDataCache.keys
          .where(
            (request) =>
                !_isProtectedQueueLibraryPage(request, protectedRequest),
          )
          .firstOrNull;
      if (removableKey == null) break;
      _queueLibraryPageDataCache.remove(removableKey);
    }
  }

  bool _handleLibraryScrollNotification({
    required ScrollNotification notification,
    required String filterMode,
    required bool hasMoreLibrary,
    required bool isPageLoading,
  }) {
    if (isPageLoading || !hasMoreLibrary || notification.depth != 0) {
      return false;
    }

    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) return false;
    final threshold = metrics.maxScrollExtent * 0.7;
    final nearEnd =
        metrics.pixels >= threshold ||
        metrics.extentAfter <= metrics.viewportDimension * 1.5;
    if (!nearEnd) return false;

    _loadMoreLibraryItems(
      filterMode: filterMode,
      hasMoreLibrary: hasMoreLibrary,
    );
    return false;
  }

  void _onFilterPageChanged(int index) {
    if (widget.librarySection != null) return;
    HapticFeedback.selectionClick();
    ref
        .read(settingsProvider.notifier)
        .setHistoryFilterMode(_modeForPage(index));
  }

  void _animateToFilterPage(int index) {
    if (index >= 0 && index < _filterModes.length) {
      final filterMode = _modeForPage(index);
      if (ref.read(settingsProvider).historyFilterMode != filterMode) {
        ref.read(settingsProvider.notifier).setHistoryFilterMode(filterMode);
      }
    }
    final motion = AppMotion.spatialSlow(
      context,
      const AppMotionSpec(Duration(milliseconds: 300), Curves.easeOutCubic),
    );
    _filterPageController?.animateToPage(
      index,
      duration: motion.duration,
      curve: motion.curve,
    );
  }

  /// Switches the Albums page between albums and singles.
  void _setAlbumsShowSingles(bool singles) {
    if (_albumsShowSingles == singles) return;
    HapticFeedback.selectionClick();
    setState(() => _albumsShowSingles = singles);
    ref
        .read(settingsProvider.notifier)
        .setHistoryFilterMode(singles ? 'singles' : 'albums');
  }

  void _onEmbeddedCoverChanged() {
    if (!mounted || _embeddedCoverRefreshScheduled) return;
    _embeddedCoverRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _embeddedCoverRefreshScheduled = false;
      if (mounted) {
        _embeddedCoverVersion.value++;
      }
    });
  }

  Future<void> _scheduleDownloadedEmbeddedCoverRefreshForPath(
    String? filePath, {
    int? beforeModTime,
    bool force = false,
  }) async {
    await DownloadedEmbeddedCoverResolver.scheduleRefreshForPath(
      filePath,
      beforeModTime: beforeModTime,
      force: force,
      onChanged: _onEmbeddedCoverChanged,
    );
  }

  String? _resolveDownloadedEmbeddedCoverPath(String? filePath) {
    return DownloadedEmbeddedCoverResolver.resolve(
      filePath,
      onChanged: _onEmbeddedCoverChanged,
    );
  }

  ValueListenable<bool> _fileExistsListenable(String? filePath) {
    return _fileExistsCache.listenable(filePath);
  }

  int get _activeFilterCount {
    int count = 0;
    if (_filterSource != null) count++;
    if (_filterQuality != null) count++;
    if (_filterFormat != null) count++;
    if (_filterMetadata != null) count++;
    return count;
  }

  void _resetFilters() {
    setState(() {
      _filterSource = null;
      _filterQuality = null;
      _filterFormat = null;
      _filterMetadata = null;
      _sortMode = 'latest';
      _resetLibraryPaging();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (context.isMornye && widget.librarySection == null) {
      return MornyeLibraryScreen(
        onOpenSection: (section) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: QueueTab(librarySection: section)),
          ),
        ),
      );
    }
    _initializePageController();
    _applyDefaultLibraryViewOnTabVisible();
    final localLibraryEnabled = ref.watch(
      settingsProvider.select((s) => s.localLibraryEnabled),
    );

    ref.listen(downloadQueueLookupProvider, (previous, next) {
      if (previous == null) return;
      if (_completionBridge.keys.any((id) => !next.byItemId.containsKey(id))) {
        setState(() {
          _completionBridge.removeWhere(
            (id, _) => !next.byItemId.containsKey(id),
          );
          _completionBridgeAt.removeWhere(
            (id, _) => !next.byItemId.containsKey(id),
          );
          _bridgePrecacheStarted.removeWhere(
            (id) => !next.byItemId.containsKey(id),
          );
        });
      }
      if (identical(previous.notCompletedItemIds, next.notCompletedItemIds)) {
        return;
      }
      for (final id in previous.notCompletedItemIds) {
        final prevItem = previous.byItemId[id];
        final nextItem = next.byItemId[id];
        if (prevItem == null) continue;
        final wasActive =
            prevItem.status == DownloadStatus.downloading ||
            prevItem.status == DownloadStatus.finalizing ||
            prevItem.status == DownloadStatus.queued;
        final nowCompleted =
            nextItem != null && nextItem.status == DownloadStatus.completed;
        if (wasActive && nowCompleted) {
          _fileExistsCache.refreshForPath(nextItem.filePath);
          _completionBridgePlayableProbe.refreshForPath(nextItem.filePath);
          _completionBridge[id] = nextItem;
          _completionBridgeAt[id] = DateTime.now();
        }
      }
    });
    ref.listen<int>(
      downloadHistoryProvider.select((state) => state.loadedIndexVersion),
      (previous, next) {
        if (previous == null || previous == next) return;
        final historyItems = ref.read(downloadHistoryProvider).items;
        for (final bridgeItem in _completionBridge.values) {
          _fileExistsCache.refreshForPath(bridgeItem.filePath);
          _completionBridgePlayableProbe.refreshForPath(bridgeItem.filePath);
          final historyPath = _historyItemForCompletionBridge(
            bridgeItem,
            historyItems,
          )?.filePath;
          _fileExistsCache.refreshForPath(historyPath);
          _completionBridgePlayableProbe.refreshForPath(historyPath);
        }
        // The family provider already reruns for the new revision. Retain its
        // last successful page while SQLite is loading so metadata backfills
        // and download completions cannot flash the Library as empty.
        _resetLibraryOffsets();
        if (mounted) setState(() {});
      },
    );
    if (localLibraryEnabled) {
      ref.listen<int>(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
        (previous, next) {
          if (previous == null || previous == next) return;
          // Keep stale rows visible until the refreshed query replaces them.
          _resetLibraryOffsets();
          if (mounted) setState(() {});
        },
      );
    }

    if (widget.librarySection == 'downloads') {
      final ids = ref.watch(
        downloadQueueLookupProvider.select((s) => s.notCompletedItemIds),
      );
      final colors = Theme.of(context).colorScheme;
      return CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: context.l10n.libraryDownloads),
          _buildQueueHeaderSliver(context, colors),
          SliverList.builder(
            itemCount: ids.length,
            itemBuilder: (context, index) => TrackCardSegment.at(
              key: ValueKey(ids[index]),
              index: index,
              count: ids.length,
              child: _QueueItemSliverRow(
                itemId: ids[index],
                colorScheme: colors,
                itemBuilder: _buildQueueItem,
              ),
            ),
          ),
          if (ids.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(context.l10n.libraryNoActiveDownloads)),
            ),
          const NavBarSliverSpacer(),
        ],
      );
    }

    final hasQueueItems = ref.watch(
      downloadQueueLookupProvider.select((lookup) => lookup.itemIds.isNotEmpty),
    );
    final historyTotalCount = ref.watch(
      downloadHistoryProvider.select((state) => state.totalCount),
    );
    // Completion-bridge cells need the finalized in-memory history record
    // immediately, before the database-backed Library page refresh lands.
    final inMemoryHistoryItems = ref.watch(
      downloadHistoryProvider.select((state) => state.items),
    );
    final localLibraryTotalCount = localLibraryEnabled
        ? ref.watch(localLibraryProvider.select((state) => state.totalCount))
        : 0;
    // Watch with selector on key fields to reduce unnecessary rebuilds.
    // LibraryCollectionsState doesn't implement == so watching without
    // selector rebuilds on every provider notification.
    ref.watch(
      libraryCollectionsProvider.select(
        (s) => (
          s.wishlistCount,
          s.lovedCount,
          s.favoriteArtistCount,
          s.playlistCount,
          s.hasPlaylistTracks,
          s.isLoaded,
        ),
      ),
    );
    final collectionState = ref.read(libraryCollectionsProvider);
    final historyViewMode = ref.watch(
      settingsProvider.select((s) => s.historyViewMode),
    );
    final String historyFilterMode =
        widget.librarySection ??
        ref.watch<String>(settingsProvider.select((s) => s.historyFilterMode));
    // Keep this mode out of the page-provider request: changing only badge
    // text must not re-query the database or reset Library pagination.
    _libraryQualityLabelMode = ref.watch(
      settingsProvider.select((s) => s.libraryQualityLabelMode),
    );
    final colorScheme = Theme.of(context).colorScheme;
    final countsRequest = _QueueLibraryCountsRequest(
      searchQuery: _searchQuery,
      filterSource: _filterSource,
      filterQuality: _filterQuality,
      filterFormat: _filterFormat,
      filterMetadata: _filterMetadata,
      localLibraryEnabled: localLibraryEnabled,
    );
    final searchingLibrary =
        _searchQuery.isNotEmpty &&
        !isAlbumCompletenessFilter(_filterMetadata) &&
        !_isSelectionMode &&
        !_isPlaylistSelectionMode;
    final countsValue = searchingLibrary
        ? const AsyncData(
            QueueLibraryCounts(
              allTrackCount: 0,
              albumCount: 0,
              singleTrackCount: 0,
            ),
          )
        : ref.watch(_queueLibraryCountsProvider(countsRequest));
    final historySnapshotFallbackEnabled =
        hasQueueItems &&
        inMemoryHistoryItems.isNotEmpty &&
        countsRequest.allowsInMemoryHistoryFallback;
    final historySnapshotCounts = historySnapshotFallbackEnabled
        ? _historySnapshotCounts(
            inMemoryHistoryItems,
            persistedTotalCount: historyTotalCount,
          )
        : null;
    final queueCounts = _resolveQueueLibraryCounts(
      countsValue,
      countsRequest,
      nonEmptyFallback: historySnapshotCounts,
    );

    _QueueLibraryPageRequest pageRequest(String filterMode) {
      final offset = _libraryPageOffsetFor(filterMode);
      final baseRequest = _QueueLibraryPageRequest(
        filterMode: filterMode,
        limit: _libraryPageSize,
        offset: offset,
        searchQuery: _searchQuery,
        filterSource: _filterSource,
        filterQuality: _filterQuality,
        filterFormat: _filterFormat,
        filterMetadata: _filterMetadata,
        sortMode: _sortMode,
        localLibraryEnabled: localLibraryEnabled,
      );
      if (offset == 0) return baseRequest;
      final previousPage = _cachedQueueLibraryPageAt(
        baseRequest,
        offset - _libraryPageSize,
      );
      return _QueueLibraryPageRequest(
        filterMode: baseRequest.filterMode,
        limit: baseRequest.limit,
        offset: baseRequest.offset,
        searchQuery: baseRequest.searchQuery,
        filterSource: baseRequest.filterSource,
        filterQuality: baseRequest.filterQuality,
        filterFormat: baseRequest.filterFormat,
        filterMetadata: baseRequest.filterMetadata,
        sortMode: baseRequest.sortMode,
        localLibraryEnabled: baseRequest.localLibraryEnabled,
        cursor: previousPage?.nextCursor,
      );
    }

    final activePageRequest = pageRequest(historyFilterMode);
    // The Artists page browses its own query.
    final activePageValue = searchingLibrary || historyFilterMode == 'artists'
        ? const AsyncData(_QueueLibraryPageData())
        : ref.watch(_queueLibraryPageProvider(activePageRequest));

    // The in-memory snapshot regroups every history item. It is only needed
    // when a page is still empty, so build it on demand and at most once per
    // mode for this build's (immutable) history list.
    final historySnapshots = <(String, int), _QueueLibraryPageData>{};
    _QueueLibraryPageData pageData(String filterMode) {
      final request = filterMode == historyFilterMode
          ? activePageRequest
          : pageRequest(filterMode);
      final historySnapshotAvailable =
          hasQueueItems &&
          inMemoryHistoryItems.isNotEmpty &&
          request.allowsInMemoryHistoryFallback;
      return _resolveQueueLibraryPageData(
        filterMode == historyFilterMode ? activePageValue : null,
        request,
        nonEmptyFallback: historySnapshotAvailable
            ? () => historySnapshots.putIfAbsent(
                (request.filterMode, request.limit),
                () => _QueueLibraryPageData.fromHistorySnapshot(
                  inMemoryHistoryItems,
                  filterMode: request.filterMode,
                  limit: request.limit,
                ),
              )
            : null,
      );
    }

    _FilterContentData getFilterData(String filterMode) {
      return pageData(filterMode).toFilterContentData(
        collectionState,
        totalTrackCount: switch (filterMode) {
          'singles' => queueCounts.singleTrackCount,
          'albums' || 'playlists' => 0,
          _ => queueCounts.allTrackCount,
        },
        totalAlbumCount: filterMode == 'albums' ? queueCounts.albumCount : null,
      );
    }

    final currentPageData = pageData(historyFilterMode);
    final currentLoadedCount = historyFilterMode == 'albums'
        ? currentPageData.groupedAlbums.length +
              currentPageData.groupedLocalAlbums.length
        : currentPageData.items.length;
    final currentTotalCount = switch (historyFilterMode) {
      'albums' => queueCounts.albumCount,
      'singles' => queueCounts.singleTrackCount,
      'playlists' || 'artists' => 0,
      _ => queueCounts.allTrackCount,
    };
    final hasMoreLibrary = currentLoadedCount < currentTotalCount;
    final isLibraryPageLoading =
        countsValue.isLoading || activePageValue.isLoading;
    final hasAnyLibraryItems =
        queueCounts.allTrackCount > 0 || queueCounts.albumCount > 0;
    final hasLibraryContent =
        historyTotalCount > 0 ||
        inMemoryHistoryItems.isNotEmpty ||
        (localLibraryEnabled && localLibraryTotalCount > 0);
    final hasActiveSearch =
        _searchQuery.isNotEmpty || _searchController.text.trim().isNotEmpty;
    final shouldShowLibraryControls =
        hasLibraryContent || hasAnyLibraryItems || hasActiveSearch;
    final listInset = wideListInset(context);
    if (!searchingLibrary) {
      _scheduleBlankLibraryRepair(
        hasQueueItems: hasQueueItems,
        hasLibraryContent: hasLibraryContent,
        hasAnyLibraryItems: hasAnyLibraryItems,
        isLibraryPageLoading: isLibraryPageLoading,
      );
    }

    final selectionItems = getFilterData(
      historyFilterMode,
    ).filteredUnifiedItems;
    if (_isSelectionMode || _isPlaylistSelectionMode) {
      final bottomPadding = MediaQuery.paddingOf(context).bottom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isSelectionMode) {
          _syncSelectionOverlay(
            items: selectionItems,
            bottomPadding: bottomPadding,
          );
        }
        if (_isPlaylistSelectionMode) {
          _syncPlaylistSelectionOverlay(
            playlists: collectionState.playlists,
            bottomPadding: bottomPadding,
          );
        }
      });
    }

    return PopScope(
      canPop: !_isSelectionMode && !_isPlaylistSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_isPlaylistSelectionMode) {
            _exitPlaylistSelectionMode();
          } else if (_isSelectionMode) {
            _exitSelectionMode();
          }
        }
      },
      child: Stack(
        children: [
          // ScrollConfiguration disables stretch overscroll to fix _StretchController exception
          // This is a known Flutter issue with NestedScrollView + Material 3 stretch indicator
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(overscroll: false),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                if (widget.librarySection == null)
                  AppSliverHeader.tabRoot(
                    title: context.l10n.navLibrary,
                    alignToContent: true,
                  )
                else
                  AppSliverHeader.page(
                    title: widget.librarySection == 'playlists'
                        ? context.l10n.searchPlaylists
                        : context.l10n.searchSongs,
                  ),

                if (shouldShowLibraryControls || hasQueueItems)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16 + listInset,
                        8,
                        16 + listInset,
                        0,
                      ),
                      child: GestureDetector(
                        onTap: () {},
                        child: AppSearchField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          hintText: context.l10n.librarySearchHint,
                          clearTooltip: context.l10n.dialogClear,
                          onChanged: _onSearchChanged,
                          onClear: () {
                            _clearSearch();
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ),
                    ),
                  ),

                if (!searchingLibrary &&
                    shouldShowLibraryControls &&
                    widget.librarySection == null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16 + listInset,
                        12,
                        16 + listInset,
                        4,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final activePage = _pageIndexFor(historyFilterMode);
                          Widget tab(
                            int index,
                            IconData icon,
                            String label,
                            int? count,
                          ) => _FilterChip(
                            label: label,
                            icon: icon,
                            count: count,
                            isSelected: activePage == index,
                            onTap: () => _animateToFilterPage(index),
                          );
                          return ScrollEdgeFade(
                            axis: Axis.horizontal,
                            size: 48,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: context.isMornye
                                  ? const EdgeInsets.symmetric(vertical: 4)
                                  : EdgeInsets.zero,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                // Mornye spreads its glass pills across the
                                // search field; Material chips sit 8dp apart
                                // from the start like other filter rows.
                                child: Row(
                                  mainAxisAlignment: context.isMornye
                                      ? MainAxisAlignment.spaceBetween
                                      : MainAxisAlignment.start,
                                  children: [
                                    tab(
                                      0,
                                      Icons.music_note_outlined,
                                      context.l10n.searchSongs,
                                      queueCounts.allTrackCount,
                                    ),
                                    const SizedBox(width: 8),
                                    tab(
                                      1,
                                      Icons.album_outlined,
                                      context.l10n.historyFilterAlbums,
                                      queueCounts.albumCount,
                                    ),
                                    const SizedBox(width: 8),
                                    // Artist totals need a full scan; the
                                    // tab shows none rather than a guess.
                                    tab(
                                      2,
                                      Icons.person_outline,
                                      context.l10n.searchArtists,
                                      null,
                                    ),
                                    const SizedBox(width: 8),
                                    tab(
                                      3,
                                      Icons.queue_music_outlined,
                                      context.l10n.searchPlaylists,
                                      _getVisibleCollectionEntries(
                                        collectionState,
                                      ).length,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
              body: searchingLibrary
                  ? CustomScrollView(
                      key: const ValueKey('library-search-results'),
                      slivers: [
                        LibrarySearchResults(
                          query: _searchQuery,
                          onOpenArtist: (artist) => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                body: MornyeLibraryScreen(
                                  page: MornyeLibraryPage.albums,
                                  artist: artist,
                                  onOpenSection: (_) {},
                                ),
                              ),
                            ),
                          ),
                        ),
                        const NavBarSliverSpacer(),
                      ],
                    )
                  : widget.librarySection != null
                  ? _buildFilterContent(
                      context: context,
                      colorScheme: colorScheme,
                      filterMode: historyFilterMode,
                      historyViewMode: 'list',
                      hasQueueItems: false,
                      filterData: getFilterData(historyFilterMode),
                      collectionState: collectionState,
                      hasMoreLibrary: hasMoreLibrary,
                      isPageLoading: isLibraryPageLoading,
                      inMemoryHistoryItems: inMemoryHistoryItems,
                    )
                  : PageView.builder(
                      controller: _filterPageController!,
                      physics: const ClampingScrollPhysics(),
                      onPageChanged: _onFilterPageChanged,
                      itemCount: _filterModes.length,
                      itemBuilder: (context, index) {
                        if (_filterModes[index] == 'artists') {
                          return _buildArtistsPage(context, colorScheme);
                        }
                        final filterMode = _modeForPage(index);
                        final filterData = getFilterData(filterMode);
                        return _buildFilterContent(
                          context: context,
                          colorScheme: colorScheme,
                          filterMode: filterMode,
                          historyViewMode: historyViewMode,
                          hasQueueItems: hasQueueItems,
                          filterData: filterData,
                          collectionState: collectionState,
                          hasMoreLibrary: filterMode == historyFilterMode
                              ? hasMoreLibrary
                              : false,
                          isPageLoading: isLibraryPageLoading,
                          inMemoryHistoryItems: inMemoryHistoryItems,
                        );
                      },
                    ),
            ),
          ), // ScrollConfiguration
        ],
      ),
    );
  }

  Widget _buildQueueHeaderSliver(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return Consumer(
      builder: (context, ref, child) {
        final queueCount = ref.watch(
          downloadQueueLookupProvider.select(
            (lookup) => lookup.notCompletedItemIds.length,
          ),
        );
        final failedCount = ref.watch(
          downloadQueueProvider.select((state) => state.failedCount),
        );
        final isProcessing = ref.watch(
          downloadQueueProvider.select((state) => state.isProcessing),
        );
        final isPaused = ref.watch(
          downloadQueueProvider.select((state) => state.isPaused),
        );
        return SliverToBoxAdapter(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: queueCount == 0
                ? const SizedBox(
                    width: double.infinity,
                    key: ValueKey('dl_header_empty'),
                  )
                : Padding(
                    key: const ValueKey('dl_header'),
                    padding: EdgeInsets.fromLTRB(
                      16 + wideListInset(context),
                      4,
                      4 + wideListInset(context),
                      4,
                    ),
                    child: Row(
                      children: [
                        AppIcon(
                          Icons.downloading_rounded,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.queueDownloadingCount(queueCount),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (failedCount > 0 && !isProcessing)
                          AppIconButton(
                            onPressed: () => ref
                                .read(downloadQueueProvider.notifier)
                                .retryAllFailed(),
                            icon: const Icon(Icons.replay_rounded, size: 20),
                            tooltip: context.l10n.queueRetryAllFailed(
                              failedCount,
                            ),
                            color: colorScheme.primary,
                            visualDensity: VisualDensity.compact,
                          ),
                        AppIconButton(
                          onPressed: () => ref
                              .read(downloadQueueProvider.notifier)
                              .togglePause(),
                          icon: Icon(
                            isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 20,
                          ),
                          tooltip: isPaused
                              ? context.l10n.actionResume
                              : context.l10n.actionPause,
                          color: colorScheme.onSurfaceVariant,
                          visualDensity: VisualDensity.compact,
                        ),
                        AppIconButton(
                          onPressed: () =>
                              _showClearAllDialog(context, ref, colorScheme),
                          icon: const Icon(Icons.clear_all_rounded, size: 20),
                          tooltip: context.l10n.queueClearAll,
                          color: colorScheme.error,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

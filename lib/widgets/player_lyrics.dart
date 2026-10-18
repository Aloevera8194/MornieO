import 'dart:async';
import 'dart:ui' show BoxHeightStyle, ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/rendering.dart'
    show OverflowBoxFit, RenderAbstractViewport, ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/utils/lyrics_parser.dart';
import 'package:spotiflac_android/utils/lyrics_timeline.dart';
import 'package:spotiflac_android/utils/synced_lyrics_scroll.dart';
import 'package:spotiflac_android/widgets/aligned_lyric_pronunciation.dart';
import 'package:spotiflac_android/widgets/lyric_supplement_transition.dart';
import 'package:spotiflac_android/widgets/lyric_scroll_motion.dart';
import 'package:spotiflac_android/widgets/lyric_gap_indicator.dart';
import 'package:spotiflac_android/widgets/mornye_player_slider.dart';
import 'package:spotiflac_android/widgets/lyrics_text_scale.dart';

part 'player_lyrics_line_style.dart';
part 'player_lyrics_word_sweep.dart';

const _mornyeLyricFontSize = 34.0;
const mornyeLyricsContentInset = 28.0 + MornyePlayerSlider.horizontalInset;

class SyncedLyricsView extends ConsumerStatefulWidget {
  final ParsedLyrics lyrics;
  final ValueListenable<Duration?> seekPreview;
  final LyricsCredits? credits;
  final ColorScheme colorScheme;
  final bool isActive;
  final bool showPronunciation;
  final bool showTranslation;

  /// Long-pressing a sung line starts sharing it.
  final ValueChanged<LyricLine>? onLongPressLine;

  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.seekPreview,
    this.credits,
    required this.colorScheme,
    required this.isActive,
    required this.showPronunciation,
    required this.showTranslation,
    this.onLongPressLine,
  });

  @override
  ConsumerState<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends ConsumerState<SyncedLyricsView>
    with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  ProviderSubscription<Duration>? _positionSubscription;
  ProviderSubscription<bool>? _playingSubscription;
  ProviderSubscription<bool>? _loadingSubscription;
  Timer? _lineBoundaryTimer;
  Timer? _userScrollIdleTimer;
  late List<LyricLine> _lines;
  late LyricDisplayLayout _displayLayout;
  late List<GlobalKey> _lineKeys;
  int _active = -1;
  Set<int> _activeLines = {};

  /// The line the view scrolls to; see [_focusFor].
  int _focus = -1;
  Duration _activeTransitionPosition = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  bool _hasStarted = false;
  bool _userScrolling = false;
  static const double _estimatedLyricExtent = 64;
  List<double>? _lineExtents;
  List<(double, double, double)> _lineMeasurements = [];
  List<LyricPronunciationLayout?> _pronunciationLayouts = [];
  Object? _lineLayoutKey;
  double? _viewportHeight;
  Offset? _layoutVisibility;
  late final AnimationController _rowReveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..addListener(_revealTick);
  List<double> _revealFrom = [];
  List<double> _revealTo = [];
  List<double>? _layoutRowVisibility;
  List<double>? _targetLineExtents;
  bool _preserveRevealAnchor = false;
  late final AnimationController _scrollMotion = AnimationController(
    vsync: this,
    duration: LyricScrollMotion.duration,
    value: 1,
  );
  double _scrollMotionDistance = 0;
  int _scrollMotionFocus = 0;

  void _stopScrollMotion() {
    _scrollMotion.stop();
    _scrollMotion.value = 1;
  }

  void _startScrollMotion(int row, double distance) {
    if (distance.abs() < 0.5 ||
        widget.seekPreview.value != null ||
        MediaQuery.disableAnimationsOf(context)) {
      _stopScrollMotion();
      return;
    }
    setState(() {
      _scrollMotionDistance = distance;
      _scrollMotionFocus = row;
    });
    _scrollMotion.forward(from: 0);
  }

  void _revealTick() {
    if (mounted) setState(() {});
  }

  List<double> get _rowVisibility {
    final progress = Curves.easeInOutCubic.transform(_rowReveal.value);
    return List.generate(
      _lines.length,
      (index) =>
          _revealFrom[index] +
          (_revealTo[index] - _revealFrom[index]) * progress,
    );
  }

  void _updateRowVisibility({bool immediate = false, bool sameFocus = false}) {
    _preserveRevealAnchor = sameFocus;
    final target = List.generate(_lines.length, (index) {
      final line = _lines[index];
      if (line.text.isEmpty) return _activeLines.contains(index) ? 1.0 : 0.0;
      if (line.isBackground) return index <= _active ? 1.0 : 0.0;
      return 1.0;
    });
    if (immediate || MediaQuery.disableAnimationsOf(context)) {
      _rowReveal.stop();
      _revealFrom = target;
      _revealTo = target;
      return;
    }
    if (listEquals(target, _revealTo)) return;
    _revealFrom = _rowVisibility;
    _revealTo = target;
    _rowReveal.forward(from: 0);
  }

  // The header stays fixed when controls collapse. Anchor lyrics to it, not
  // to a fraction of the growing viewport, including during the transition.
  double get _focusInset =>
      (MediaQuery.sizeOf(context).height * 0.06).clamp(16.0, 48.0);

  @override
  void initState() {
    super.initState();
    _resetLineKeys();
    widget.seekPreview.addListener(_previewChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Appearance can rebuild when transport controls fade (for example with
    // custom glass clarity). Keep the existing playback subscription and the
    // user's scroll ownership; only new lyrics/page activation should reset it.
    if (_positionSubscription == null && widget.isActive) {
      _syncPositionSubscription();
    }
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seekPreview != widget.seekPreview) {
      oldWidget.seekPreview.removeListener(_previewChanged);
      widget.seekPreview.addListener(_previewChanged);
    }
    if (oldWidget.lyrics != widget.lyrics) {
      _resetLineKeys();
    }
    if (oldWidget.showPronunciation != widget.showPronunciation ||
        oldWidget.showTranslation != widget.showTranslation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_userScrolling && _scroll.hasClients) {
          // Cancel a pending line-scroll once, then let layout preserve the
          // current anchor throughout the supplement animation.
          _scroll.jumpTo(_scroll.offset);
        }
      });
    }
    if (oldWidget.isActive != widget.isActive ||
        oldWidget.lyrics != widget.lyrics) {
      _syncPositionSubscription();
    }
  }

  void _resetLineKeys() {
    _stopScrollMotion();
    _hasStarted = false;
    _lineExtents = null;
    _lineLayoutKey = null;
    _lines = lyricsWithDisplayEnds(lyricsTimelineWithGaps(widget.lyrics.lines));
    _rowReveal.stop();
    _revealFrom = _revealTo = [
      for (final line in _lines)
        if (line.isBackground || line.text.isEmpty) 0.0 else 1.0,
    ];
    _layoutRowVisibility = null;
    _targetLineExtents = null;
    _displayLayout = LyricDisplayLayout(_lines);
    _lineKeys = List<GlobalKey>.generate(
      _lines.length,
      (index) => GlobalKey(debugLabel: 'lyric-line-$index'),
      growable: false,
    );
  }

  void _syncPositionSubscription() {
    _positionSubscription?.close();
    _playingSubscription?.close();
    _loadingSubscription?.close();
    _lineBoundaryTimer?.cancel();
    _positionSubscription = null;
    _playingSubscription = null;
    _loadingSubscription = null;
    if (!widget.isActive) {
      _stopScrollMotion();
      return;
    }
    _userScrollIdleTimer?.cancel();
    _userScrolling = false;

    final position = _displayPosition;
    _playing = ref.read(playbackPlayingProvider);
    _loading = ref.read(playbackLoadingProvider);
    _active = _activeIndexAt(position);
    _activeLines = activeLyricIndices(_lines, position, _active);
    _focus = _focusFor(_active, _activeLines, position);
    _updateRowVisibility(immediate: true);
    _activeTransitionPosition = position;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_maybeAutoScroll(_active, immediate: true));
    });
    _scheduleNextLine(position);
    _positionSubscription = ref.listenManual<Duration>(
      playbackPositionProvider,
      (previous, next) {
        if (widget.seekPreview.value != null) return;
        final active = _activeIndexAt(next);
        _setActiveLine(active, position: next);
        _scheduleNextLine(next);
      },
    );
    _playingSubscription = ref.listenManual<bool>(playbackPlayingProvider, (
      previous,
      next,
    ) {
      _playing = next;
      final position = _displayPosition;
      _setActiveLine(_activeIndexAt(position), position: position);
      _scheduleNextLine(position);
    });
    _loadingSubscription = ref.listenManual<bool>(playbackLoadingProvider, (
      previous,
      next,
    ) {
      _loading = next;
      final position = _displayPosition;
      _setActiveLine(_activeIndexAt(position), position: position);
      _scheduleNextLine(position);
    });
  }

  Duration get _displayPosition =>
      widget.seekPreview.value ?? ref.read(playbackPositionProvider);

  void _previewChanged() {
    if (!mounted || !widget.isActive) return;
    final position = _displayPosition;
    final wasUserScrolling = _userScrolling;
    _userScrolling = false;
    _userScrollIdleTimer?.cancel();
    final active = _activeIndexAt(position);
    if (active == _active && (wasUserScrolling || active < 0)) {
      unawaited(_maybeAutoScroll(active));
    }
    _setActiveLine(active, position: position);
    _scheduleNextLine(position);
  }

  int _activeIndexAt(Duration position) {
    // Scrubbing is an explicit preview, even at zero or while audio buffers.
    if (widget.seekPreview.value != null) {
      return LyricsParser.activeIndex(_lines, position);
    }
    if (context.isMornye) {
      // Read one transport snapshot: playing/loading derived providers can
      // notify separately during the same playback event.
      final playback = ref.read(playbackStateProvider).value;
      if (playback?.processingState == AudioProcessingState.loading ||
          playback?.processingState == AudioProcessingState.buffering) {
        return -1;
      }
      _hasStarted =
          _hasStarted || playback?.playing == true || position > Duration.zero;
      if (!_hasStarted) return -1;
    }
    return LyricsParser.activeIndex(_lines, position);
  }

  /// The scroll anchor for [active]. When the next line starts while the
  /// previous one is still being sung, the view holds on the earlier line
  /// until its timed end, so both stay fully visible instead of the unfinished
  /// one scrolling away. Only the directly preceding lead line can hold.
  int _focusFor(int active, Set<int> activeLines, Duration position) {
    if (active < 0) return -1;
    final focus = _displayLayout.focusForLine[active];
    final start = _lines[focus].time;
    for (var i = focus - 1; i >= 0; i--) {
      final line = _lines[i];
      if (line.isBackground || line.time >= start) continue;
      if (line.text.isEmpty) return focus;
      final end = line.end;
      final held = _displayLayout.focusForLine[i];
      return activeLines.contains(i) && end != null && end > position
          ? held
          : focus;
    }
    return focus;
  }

  void _setActiveLine(int active, {required Duration position}) {
    if (!mounted) return;
    final activeLines = activeLyricIndices(_lines, position, active);
    final indexChanged = active != _active;
    final previousFocus = _focus;
    if (!indexChanged &&
        activeLines.length == _activeLines.length &&
        activeLines.containsAll(_activeLines)) {
      return;
    }
    final focus = _focusFor(active, activeLines, position);
    setState(() {
      _active = active;
      _activeLines = activeLines;
      _focus = focus;
      _activeTransitionPosition = position;
      _updateRowVisibility(sameFocus: focus >= 0 && focus == previousFocus);
    });
    if (focus == previousFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && active == _active) unawaited(_maybeAutoScroll(active));
    });
  }

  void _scheduleNextLine(Duration position) {
    _lineBoundaryTimer?.cancel();
    if (!widget.isActive ||
        !_playing ||
        _loading ||
        widget.seekPreview.value != null) {
      return;
    }

    final lines = _lines;
    final dueIndex = syncedLyricsDueLineIndex(
      lineStarts: lines.map((line) => line.time).toList(growable: false),
      currentIndex: _active,
      position: position,
    );
    _setActiveLine(dueIndex, position: position);

    final nextIndex = dueIndex + 1;
    Duration? nextBoundary = nextIndex < lines.length
        ? lines[nextIndex].time
        : null;
    for (final index in _activeLines) {
      final end = lines[index].end;
      if ((index != dueIndex ||
              lines[index].voice != null ||
              lines[index].isBackground) &&
          end != null &&
          end > position &&
          (nextBoundary == null || end < nextBoundary)) {
        nextBoundary = end;
      }
    }
    if (nextBoundary == null) return;
    final boundary = nextBoundary;
    _lineBoundaryTimer = Timer(boundary - position, () {
      if (!mounted || !widget.isActive || !_playing || _loading) return;
      _scheduleNextLine(boundary);
    });
  }

  @override
  void dispose() {
    widget.seekPreview.removeListener(_previewChanged);
    _positionSubscription?.close();
    _playingSubscription?.close();
    _loadingSubscription?.close();
    _lineBoundaryTimer?.cancel();
    _userScrollIdleTimer?.cancel();
    _scroll.dispose();
    _rowReveal.dispose();
    _scrollMotion.dispose();
    super.dispose();
  }

  void _measureMornyeLines(BuildContext context, double width) {
    final style = _mornyeLyricStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final key = (width, style, scaler, direction, locale);
    if (_lineLayoutKey == key) return;
    _lineLayoutKey = key;
    final painter = TextPainter(
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
    );
    final measurements = <(double, double, double)>[];
    final layouts = List<LyricPronunciationLayout?>.filled(_lines.length, null);
    for (final index in _displayLayout.lineOrder) {
      final line = _lines[index];
      if (line.text.isEmpty) {
        measurements.add((56, 0, 0));
        continue;
      }
      painter.text = TextSpan(
        text: line.text,
        style: _mornyeLyricStyle(context, background: line.isBackground),
      );
      painter.layout(maxWidth: width);
      final padding = _linePadding(index).vertical;
      var height = painter.height + padding;
      var pronunciationHeight = 0.0;
      var translationHeight = 0.0;
      LyricPronunciationLayout? pronunciationLayout;
      for (final (text, style, _, translation) in _lyricSupplements(
        context,
        line,
      )) {
        painter.text = TextSpan(text: text, style: style);
        painter.layout(maxWidth: width);
        if (translation) {
          translationHeight = 6 + painter.height;
        } else {
          pronunciationHeight = 6 + painter.height;
          final aligned = LyricPronunciationLayout.measure(
            line: line,
            primaryStyle: _mornyeLyricStyle(
              context,
              background: line.isBackground,
            ),
            pronunciationStyle: style,
            maxWidth: width,
            textScaler: scaler,
            textDirection: direction,
            locale: locale,
          );
          if (aligned != null) {
            pronunciationLayout = aligned;
            height = aligned.primaryHeight + padding;
            pronunciationHeight = aligned.pronunciationHeight;
          }
        }
      }
      measurements.add((height, pronunciationHeight, translationHeight));
      layouts[index] = pronunciationLayout;
    }
    _lineMeasurements = measurements;
    _pronunciationLayouts = layouts;
    painter.dispose();
  }

  Future<void> _maybeAutoScroll(int index, {bool immediate = false}) async {
    // A short intro may have no countdown row. Still return to the first
    // upcoming lyric when the user scrubs back before any vocals.
    if (index < 0 && widget.seekPreview.value != null) index = 0;
    if (_userScrolling ||
        index < 0 ||
        index >= _lines.length ||
        !_scroll.hasClients) {
      return;
    }
    index = index == _active && _focus >= 0
        ? _focus
        : _displayLayout.focusForLine[index];
    final row = _displayLayout.rowForLine[index];
    final duration = immediate || MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: widget.seekPreview.value != null ? 220 : 380);
    if (duration == Duration.zero) _stopScrollMotion();
    final extents = _targetLineExtents;
    if (context.isMornye && extents != null && row < extents.length) {
      final position = _scroll.position;
      final target = extents.take(row).fold(0.0, (sum, extent) => sum + extent);
      final offset = target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (duration == Duration.zero) {
        _scroll.jumpTo(offset);
      } else {
        _startScrollMotion(row, offset - position.pixels);
        await _scroll.animateTo(
          offset,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    if (index < _lineKeys.length) {
      final lineContext = _lineKeys[index].currentContext;
      if (lineContext != null) {
        final object = lineContext.findRenderObject();
        final viewport = object == null
            ? null
            : RenderAbstractViewport.maybeOf(object);
        if (duration != Duration.zero && viewport != null) {
          _startScrollMotion(
            row,
            viewport.getOffsetToReveal(object!, 0.5).offset - _scroll.offset,
          );
        }
        await Scrollable.ensureVisible(
          lineContext,
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
        return;
      }
    }

    final position = _scroll.position;
    final target = syncedLyricsEstimatedOffset(
      index: row,
      estimatedLineExtent: _estimatedLyricExtent,
    );
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (duration == Duration.zero) {
      _scroll.jumpTo(clamped.toDouble());
    } else {
      _startScrollMotion(row, clamped - position.pixels);
      await _scroll.animateTo(
        clamped.toDouble(),
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted ||
        _userScrolling ||
        (_active >= 0 && index != _focus) ||
        index >= _lineKeys.length) {
      return;
    }
    final lineContext = _lineKeys[index].currentContext;
    if (lineContext != null && lineContext.mounted) {
      await Scrollable.ensureVisible(
        lineContext,
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: duration == Duration.zero
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) => LyricsTextScale(
    child: TweenAnimationBuilder<Offset>(
      tween: Tween(
        end: Offset(
          widget.showPronunciation ? 1 : 0,
          widget.showTranslation ? 1 : 0,
        ),
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      builder: (context, visibility, _) => _buildLyrics(context, visibility),
    ),
  );

  Widget _buildLyrics(BuildContext context, Offset visibility) {
    final lines = _lines;
    final active = _active;
    final rowVisibility = _rowVisibility;
    final loading = ref.watch(playbackLoadingProvider);
    final mornye = context.isMornye;
    final highContrast = MediaQuery.highContrastOf(context);
    final blurLyrics =
        mornye &&
        !highContrast &&
        // Every defocused line is filtered again on each playback frame.
        ref.watch(mornyeLiquidGlassProvider);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0 ||
            notification.metrics.axis != Axis.vertical) {
          return false;
        }
        final dragging =
            (notification is ScrollStartNotification &&
                notification.dragDetails != null) ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null) ||
            (notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle);
        if (dragging) {
          _stopScrollMotion();
          _userScrolling = true;
          _userScrollIdleTimer?.cancel();
        } else if (notification is ScrollEndNotification && _userScrolling) {
          // Start the return-to-playback timeout only after the drag and its
          // momentum finish. A direction notification is not an idle event:
          // a long drag can keep that direction while controls fade in/out.
          _userScrollIdleTimer?.cancel();
          _userScrollIdleTimer = Timer(const Duration(seconds: 4), () {
            if (!mounted || !widget.isActive) return;
            _userScrolling = false;
            unawaited(_maybeAutoScroll(_active));
          });
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inset = mornye ? mornyeLyricsContentInset : 24.0;
          final contentWidth = (constraints.maxWidth - inset * 2).clamp(
            0.0,
            double.infinity,
          );
          // Lay out at the existing lyric width, then fit the whole line to
          // the timeline. Scaling text, phrase gaps and supplements together
          // preserves wrapping instead of pushing extra words onto a new row.
          final layoutWidth = (constraints.maxWidth - 48).clamp(
            0.0,
            double.infinity,
          );
          final lyricScale = mornye && layoutWidth > 0
              ? contentWidth / layoutWidth
              : 1.0;
          if (mornye) {
            final previousExtents = _lineExtents;
            _measureMornyeLines(context, layoutWidth);
            // Reuse text measurements; only interpolate row heights as the
            // supplements fade. Scrolling follows the same animation clock.
            final fullExtents = List.generate(_lineMeasurements.length, (row) {
              final (primary, pronunciation, translation) =
                  _lineMeasurements[row];
              final index = _displayLayout.lineOrder[row];
              if (_lines[index].text.isEmpty) return primary;
              final padding = _linePadding(index).vertical;
              return padding +
                  (primary -
                          padding +
                          pronunciation * visibility.dx +
                          translation * visibility.dy) *
                      lyricScale;
            });
            _lineExtents = List.generate(fullExtents.length, (row) {
              return fullExtents[row] *
                  rowVisibility[_displayLayout.lineOrder[row]];
            });
            _targetLineExtents = List.generate(fullExtents.length, (row) {
              return fullExtents[row] *
                  _revealTo[_displayLayout.lineOrder[row]];
            });
            if (previousExtents != null &&
                ((_layoutVisibility != null &&
                        _layoutVisibility != visibility) ||
                    (_preserveRevealAnchor &&
                        _layoutRowVisibility != null &&
                        !listEquals(_layoutRowVisibility, rowVisibility))) &&
                previousExtents.length == _lineExtents!.length &&
                _scroll.hasClients) {
              var anchor = _focus < 0 ? 0 : _displayLayout.rowForLine[_focus];
              if (_userScrolling) {
                anchor = 0;
                var extent = 0.0;
                while (anchor < previousExtents.length &&
                    extent + previousExtents[anchor] <= _scroll.offset) {
                  extent += previousExtents[anchor++];
                }
              }
              var correction = 0.0;
              for (var i = 0; i < anchor; i++) {
                correction += _lineExtents![i] - previousExtents[i];
              }
              // Correct before the ListView lays out/paints. A post-frame
              // jump leaves every painted frame one animation step behind.
              if (correction != 0) _scroll.position.correctBy(correction);
            }
          }
          _layoutVisibility = visibility;
          _layoutRowVisibility = rowVisibility;
          if (_viewportHeight != constraints.maxHeight) {
            _viewportHeight = constraints.maxHeight;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                unawaited(_maybeAutoScroll(_active, immediate: true));
              }
            });
          }
          final topPadding = mornye
              ? _focusInset
              : syncedLyricsCenterPadding(
                  viewportDimension: constraints.maxHeight,
                  estimatedLineExtent: _estimatedLyricExtent,
                );
          // Leave enough trailing space for the final line to reach the same
          // upper focus position as every other line.
          final bottomPadding = mornye && _lineExtents!.isNotEmpty
              ? (constraints.maxHeight - _lineExtents!.last - topPadding).clamp(
                  topPadding,
                  double.infinity,
                )
              : topPadding;
          return ListView.builder(
            controller: _scroll,
            itemExtentBuilder: mornye
                ? (index, _) => index < lines.length
                      ? _lineExtents![index]
                      : widget.credits!.heightFor(context, contentWidth)
                : null,
            padding: EdgeInsets.fromLTRB(
              inset,
              topPadding,
              inset,
              bottomPadding,
            ),
            itemCount: lines.length + (widget.credits == null ? 0 : 1),
            itemBuilder: (context, row) {
              if (row == lines.length) return widget.credits!;
              final index = _displayLayout.lineOrder[row];
              final line = lines[index];
              final leadIndex = _displayLayout.leadForLine[index];
              final textAlign = _lyricTextAlign(context, lines[leadIndex]);
              final reveal = rowVisibility[index];
              if (reveal == 0) return SizedBox.shrink(key: _lineKeys[index]);
              final isActive = _activeLines.contains(index);
              final isPast = index < active;

              final color = mornye
                  ? Colors.white
                  : isActive
                  ? widget.colorScheme.onSurface
                  : isPast
                  ? widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                  : widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.8);

              if (line.text.isEmpty) {
                return _revealRow(
                  index,
                  reveal,
                  textAlign,
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: context.tokens.lyricsLinePaddingV,
                    ),
                    child: SizedBox(
                      height: 24,
                      child: Align(
                        alignment: mornye
                            ? Alignment.centerLeft
                            : Alignment.center,
                        child:
                            isActive &&
                                widget.isActive &&
                                (!loading || widget.seekPreview.value != null)
                            ? ValueListenableBuilder<Duration?>(
                                valueListenable: widget.seekPreview,
                                builder: (context, preview, _) =>
                                    LyricGapIndicator(
                                      key: ValueKey(line.time),
                                      start: line.time,
                                      end: line.end!,
                                      color: color,
                                      position: preview,
                                    ),
                              )
                            : null,
                      ),
                    ),
                  ),
                );
              }

              final timed =
                  isActive &&
                  (line.hasWordTiming || line.romanizationWords.isNotEmpty);
              Widget content;
              if (timed) {
                content = _WordHighlightedLyricLine(
                  line: line,
                  colorScheme: widget.colorScheme,
                  animate: widget.isActive,
                  initialPosition: _activeTransitionPosition,
                  seekPreview: widget.seekPreview,
                  supplementVisibility: visibility,
                  pronunciationLayout: mornye
                      ? _pronunciationLayouts[index]
                      : null,
                  textAlign: textAlign,
                );
              } else {
                content = Text(
                  line.text,
                  textAlign: textAlign,
                  style:
                      (mornye || isActive
                              ? Theme.of(context).textTheme.headlineSmall
                              : Theme.of(context).textTheme.titleLarge)
                          ?.copyWith(
                            height: context.tokens.lyricsLineHeight,
                            fontSize: line.isBackground
                                ? (mornye ? _mornyeLyricFontSize * 0.68 : 18)
                                : mornye
                                ? _mornyeLyricFontSize
                                : null,
                            fontWeight: mornye || isActive
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: color,
                          ),
                );
                content = _withLyricSupplements(
                  context,
                  line,
                  content,
                  color,
                  visibility: visibility,
                  pronunciationLayout: mornye
                      ? _pronunciationLayouts[index]
                      : null,
                  textAlign: textAlign,
                );
              }
              content = AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                reverseDuration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey(timed),
                  child: SizedBox(width: double.infinity, child: content),
                ),
              );
              if (mornye) {
                final activeLead = active < 0 ? -1 : _focus;
                final distance = activeLead < 0
                    ? row + 1
                    : (_displayLayout.rowForLine[leadIndex] -
                              _displayLayout.rowForLine[activeLead])
                          .abs();
                // Nearby lines need visible defocus at the larger lyric size;
                // progressively soften lines further from the current one.
                final sigma = !blurLyrics || isActive || leadIndex == activeLead
                    ? 0.0
                    : active < 0
                    ? 4.8
                    : distance == 1
                    ? 2.4
                    : distance == 2
                    ? 3.6
                    : 4.8;
                content = TweenAnimationBuilder<double>(
                  tween: Tween(end: sigma),
                  duration: motion,
                  child: RepaintBoundary(child: content),
                  builder: (context, value, child) => ImageFiltered(
                    enabled: value > 0,
                    imageFilter: ImageFilter.blur(sigmaX: value, sigmaY: value),
                    child: child,
                  ),
                );
                content = FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: layoutWidth, child: content),
                );
              }

              content = LyricScrollMotion(
                progress: _scrollMotion,
                distance: _scrollMotionDistance,
                rowsAfterFocus: row - _scrollMotionFocus,
                enabled: !isActive,
                child: content,
              );
              return _revealRow(
                index,
                reveal,
                textAlign,
                Padding(
                  padding: _linePadding(index),
                  child: GestureDetector(
                    onTap: () =>
                        ref.read(musicPlayerControllerProvider).seek(line.time),
                    onLongPress: widget.onLongPressLine == null
                        ? null
                        : () {
                            HapticFeedback.mediumImpact();
                            widget.onLongPressLine!(line);
                          },
                    child: AnimatedScale(
                      scale: isActive ? 1.0 : 0.96,
                      alignment: !mornye
                          ? Alignment.center
                          : textAlign == TextAlign.right
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      duration: motion,
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: mornye
                            ? (isActive || highContrast ? 1 : 0.48)
                            : (isActive ? 1.0 : (isPast ? 0.55 : 0.85)),
                        duration: motion,
                        child: content,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _revealRow(
    int index,
    double visibility,
    TextAlign align,
    Widget child,
  ) {
    final alignment = align == TextAlign.right
        ? Alignment.topRight
        : align == TextAlign.center
        ? Alignment.topCenter
        : Alignment.topLeft;
    // A fixed-extent row is already shrinking. Measure its contents at full
    // height so fitting does not scale it twice.
    final fullHeight = OverflowBox(
      minHeight: 0,
      maxHeight: double.infinity,
      fit: OverflowBoxFit.deferToChild,
      alignment: Alignment.topCenter,
      child: child,
    );
    return KeyedSubtree(
      key: _lineKeys[index],
      child: !_lines[index].isBackground && _lines[index].text.isNotEmpty
          ? child
          : IgnorePointer(
              ignoring: visibility < 1,
              child: _lines[index].isBackground
                  ? LyricBackingTransition(
                      visibility: visibility,
                      alignment: alignment,
                      child: fullHeight,
                    )
                  : LyricSupplementTransition(
                      visibility: visibility,
                      alignment: alignment,
                      child: fullHeight,
                    ),
            ),
    );
  }

  EdgeInsets _linePadding(int index) {
    final row = _displayLayout.rowForLine[index];
    final order = _displayLayout.lineOrder;
    final hasBackingBelow =
        row + 1 < order.length &&
        _lines[order[row + 1]].isBackground &&
        _displayLayout.leadForLine[order[row + 1]] ==
            _displayLayout.leadForLine[index];
    return EdgeInsets.only(
      top: _lines[index].isBackground ? 6 : context.tokens.lyricsLinePaddingV,
      bottom: hasBackingBelow ? 0 : context.tokens.lyricsLinePaddingV,
    );
  }
}

class LyricsCredits extends StatelessWidget {
  const LyricsCredits({super.key, this.writers, this.provider});

  final String? writers;
  final String? provider;

  String _text(BuildContext context) => [
    if (writers != null) context.l10n.nowPlayingWrittenBy(writers!),
    if (provider != null) context.l10n.nowPlayingLyricsProvider(provider!),
  ].join('\n');

  TextStyle _style(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: context.isMornye ? 17 : 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.48),
      );

  double heightFor(BuildContext context, double width) {
    final painter = TextPainter(
      text: TextSpan(text: _text(context), style: _style(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width.clamp(0, double.infinity));
    final height = painter.height + 32;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(_text(context), style: _style(context)),
  );
}

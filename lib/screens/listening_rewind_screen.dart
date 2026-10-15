import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageByteFormat, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_3_expressive/material_3_expressive.dart'
    show M3EShapeKind;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/listening_rewind.dart';
import 'package:spotiflac_android/services/listening_statistics.dart';
import 'package:spotiflac_android/theme/app_motion.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/app_action_button.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/app_content_card.dart';
import 'package:spotiflac_android/widgets/app_icon.dart';
import 'package:spotiflac_android/widgets/app_icon_button.dart';
import 'package:spotiflac_android/widgets/app_loading_indicator.dart';
import 'package:spotiflac_android/widgets/app_shape.dart';
import 'package:spotiflac_android/widgets/player_artwork.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

final listeningRewindProvider = FutureProvider.autoDispose
    .family<ListeningRewind, ListeningRewindPeriod>((ref, period) async {
      await listeningRecorder.flush();
      final range = ListeningRewindRange.of(period, DateTime.now());
      return ListeningStatisticsStore.instance.read(
        (db) => readListeningRewind(
          db,
          range,
          yearly: period == ListeningRewindPeriod.year,
        ),
      );
    });

/// The Rewind the Library advertises today, or null. A window without any
/// listening is not advertised, so the banner never opens an empty story.
final listeningRewindSpotlightProvider =
    FutureProvider.autoDispose<ListeningRewindSpotlight?>((ref) async {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final refresh = Timer(tomorrow.difference(now), ref.invalidateSelf);
      ref.onDispose(refresh.cancel);
      final spotlight = ListeningRewindSpotlight.at(now);
      if (spotlight == null) return null;
      await listeningRecorder.flush();
      final range = ListeningRewindRange.of(spotlight.period, now);
      final rows = await ListeningStatisticsStore.instance.read(
        (db) => db.rawQuery(
          'SELECT 1 FROM listening '
          'WHERE day >= ? AND day < ? AND milliseconds > 0 LIMIT 1',
          [listeningDay(range.start), listeningDay(range.end)],
        ),
      );
      return rows.isEmpty ? null : spotlight;
    });

String listeningRewindPeriodLabel(
  BuildContext context,
  ListeningRewindPeriod period,
) => switch (period) {
  ListeningRewindPeriod.weeks => context.l10n.listeningRewindLastWeeks(4),
  ListeningRewindPeriod.quarter => context.l10n.listeningRewindLastMonths(3),
  ListeningRewindPeriod.halfYear => context.l10n.listeningRewindLastMonths(6),
  ListeningRewindPeriod.year => context.l10n.listeningRewindThisYear(
    DateTime.now().year,
  ),
};

/// Asks for a window, then plays its Rewind.
Future<void> showListeningRewind(BuildContext context) async {
  const icons = {
    ListeningRewindPeriod.weeks: Icons.today,
    ListeningRewindPeriod.quarter: Icons.date_range,
    ListeningRewindPeriod.halfYear: Icons.event_outlined,
    ListeningRewindPeriod.year: Icons.auto_awesome,
  };
  // Opened from the Library tab: the sheet and the story cover the shell
  // chrome instead of sliding beneath the tab bar and mini player.
  final period = await showAppBottomSheet<ListeningRewindPeriod>(
    context: context,
    useRootNavigator: true,
    title: context.l10n.listeningRewindChoosePeriod,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: sheetContext.tokens.gapLg),
      child: SettingsGroup(
        children: [
          for (final period in ListeningRewindPeriod.values)
            SettingsItem(
              icon: icons[period],
              showIconInMornye: true,
              title: listeningRewindPeriodLabel(sheetContext, period),
              showDivider: period != ListeningRewindPeriod.values.last,
              onTap: () => Navigator.pop(sheetContext, period),
            ),
        ],
      ),
    ),
  );
  if (period == null || !context.mounted) return;
  await openListeningRewind(context, period);
}

/// Plays the Rewind of [period] above the shell chrome.
Future<void> openListeningRewind(
  BuildContext context,
  ListeningRewindPeriod period,
) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => ListeningRewindScreen(period: period),
  ),
);

/// The permanent way in, on the listening statistics screen: a row that asks
/// for any window.
class ListeningRewindEntry extends StatelessWidget {
  const ListeningRewindEntry({super.key});

  @override
  Widget build(BuildContext context) => SettingsGroup(
    children: [
      SettingsItem(
        icon: Icons.auto_awesome,
        showIconInMornye: true,
        title: context.l10n.listeningRewind,
        subtitle: context.l10n.listeningRewindDescription,
        showDivider: false,
        onTap: () => showListeningRewind(context),
      ),
    ],
  );
}

/// The Library's seasonal Rewind banner. It shows only while
/// [listeningRewindSpotlightProvider] has a Rewind to offer and opens that
/// window directly.
class ListeningRewindBanner extends ConsumerWidget {
  const ListeningRewindBanner({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spotlight = ref.watch(listeningRewindSpotlightProvider).value;
    final child = switch (spotlight) {
      null => null,
      ListeningRewindSpotlight.monthly => _MonthlyRewindBanner(margin: margin),
      ListeningRewindSpotlight.yearly => _YearlyRewindBanner(margin: margin),
    };
    // Grows in rather than shifting the list when the check completes.
    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: child ?? const SizedBox(width: double.infinity),
    );
  }
}

/// The four-weekly invitation: a quiet tonal card.
class _MonthlyRewindBanner extends StatelessWidget {
  const _MonthlyRewindBanner({this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mornye = context.isMornye;
    // Mornye keeps its neutral control fill and accent tint.
    final foreground = mornye ? colors.onSurface : colors.onTertiaryContainer;
    final accent = mornye ? colors.primary : colors.tertiary;
    final onAccent = mornye ? colors.onPrimary : colors.onTertiary;
    return AppContentCard(
      margin: margin,
      color: colors.tertiaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: context.tokens.borderRadiusCard,
      ),
      onTap: () => openListeningRewind(context, ListeningRewindPeriod.weeks),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AppShapeBadge(
              kind: AppShapes.badge,
              size: 48,
              color: accent,
              child: AppIcon(Icons.auto_awesome, color: onAccent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.listeningRewind,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.listeningRewindMonthlyReady,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
            AppIcon(Icons.chevron_right, color: foreground),
          ],
        ),
      ),
    );
  }
}

/// The once-a-year invitation: a gradient poster with the year set large
/// behind the title and expressive shapes scattered around it.
class _YearlyRewindBanner extends StatelessWidget {
  const _YearlyRewindBanner({this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final year = '${DateTime.now().year}';
    final foreground = colors.onPrimary;
    final radius = context.isMornye
        ? BorderRadius.circular(28)
        : context.tokens.borderRadiusCard;
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primary, colors.tertiary],
            ),
          ),
          child: InkWell(
            onTap: () =>
                openListeningRewind(context, ListeningRewindPeriod.year),
            child: Stack(
              children: [
                // The year as a giant, faded watermark.
                PositionedDirectional(
                  end: -8,
                  bottom: -28,
                  child: ExcludeSemantics(
                    child: Text(
                      year,
                      style: textTheme.displayLarge?.copyWith(
                        fontSize: 112,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: foreground.withValues(alpha: 0.16),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  end: 96,
                  top: -18,
                  child: AppShapeBadge(
                    kind: AppShapes.badge,
                    size: 64,
                    color: foreground.withValues(alpha: 0.12),
                    child: const SizedBox.shrink(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                AppIcon(
                                  Icons.auto_awesome,
                                  size: 18,
                                  color: foreground,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  l10n.listeningRewindYearEyebrow,
                                  style: textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                    color: foreground,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l10n.listeningRewindYearTitle(year),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: foreground,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.listeningRewindYearBanner,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                color: foreground.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      DecoratedBox(
                        decoration: ShapeDecoration(
                          color: foreground,
                          shape: const CircleBorder(),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: AppIcon(
                            Icons.play_arrow_rounded,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ListeningRewindScreen extends ConsumerWidget {
  const ListeningRewindScreen({super.key, required this.period});

  final ListeningRewindPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewind = ref.watch(listeningRewindProvider(period));
    final mornye = context.isMornye;
    final colors = Theme.of(context).colorScheme;
    final background = mornye ? Colors.black : colors.surface;
    final foreground = mornye ? Colors.white : colors.onSurface;
    Widget message(String text) => _RewindMessage(
      text: text,
      background: background,
      foreground: foreground,
    );
    return Scaffold(
      backgroundColor: background,
      body: rewind.when(
        loading: () => Center(child: AppLoadingIndicator(color: foreground)),
        error: (_, _) => message(context.l10n.listeningRewindLoadError),
        data: (rewind) => rewind.isEmpty
            ? message(context.l10n.listeningRewindEmpty)
            : _RewindStory(rewind: rewind, period: period),
      ),
    );
  }
}

class _RewindMessage extends StatelessWidget {
  const _RewindMessage({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: foreground),
            ),
          ),
        ),
        Positioned(top: 8, right: 8, child: _CloseButton(color: foreground)),
      ],
    ),
  );
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => AppIconButton(
    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
    color: color,
    icon: AppIcon.adaptive(Icons.close, color: color),
    onPressed: () => Navigator.of(context).maybePop(),
  );
}

enum _Slide {
  intro,
  minutes,
  yearNumbers,
  months,
  topArtist,
  artists,
  monthlyArtists,
  loyal,
  topTrack,
  tracks,
  album,
  firstSong,
  discoveries,
  rhythm,
  replay,
  outro,
}

/// A calendar-year Rewind adds its year-in-review slides between the regular
/// highlights.
List<_Slide> _slidesFor(ListeningRewind rewind) {
  final year = rewind.year;
  return [
    _Slide.intro,
    _Slide.minutes,
    if (year != null) _Slide.yearNumbers,
    if (year != null && rewind.monthlyMilliseconds.length >= 2) _Slide.months,
    if (rewind.topArtists.isNotEmpty) _Slide.topArtist,
    if (rewind.topArtists.length >= 3) _Slide.artists,
    if (year != null && year.monthlyTopArtists.length >= 2)
      _Slide.monthlyArtists,
    if (year != null && year.loyalArtist != null && year.loyalArtistDays > 1)
      _Slide.loyal,
    if (rewind.summary.tracks.isNotEmpty) _Slide.topTrack,
    if (rewind.summary.tracks.length >= 3) _Slide.tracks,
    if (rewind.topAlbums.isNotEmpty) _Slide.album,
    if (year?.firstPlay != null) _Slide.firstSong,
    if (rewind.newArtists.isNotEmpty) _Slide.discoveries,
    if (rewind.peakDay != null) _Slide.rhythm,
    if (rewind.replay != null) _Slide.replay,
    _Slide.outro,
  ];
}

/// Full-screen story of Rewind slides. Slides advance on their own unless the
/// system asks for reduced motion; tapping the left third goes back, the rest
/// goes forward, holding pauses, and swiping pages manually.
class _RewindStory extends StatefulWidget {
  const _RewindStory({required this.rewind, required this.period});

  final ListeningRewind rewind;
  final ListeningRewindPeriod period;

  @override
  State<_RewindStory> createState() => _RewindStoryState();
}

class _RewindStoryState extends State<_RewindStory>
    with SingleTickerProviderStateMixin {
  static const _slideDuration = Duration(seconds: 6);

  late final List<_Slide> _slides = _slidesFor(widget.rewind);
  final _pages = PageController();
  late final _progress = AnimationController(
    vsync: this,
    duration: _slideDuration,
  )..addStatusListener(_onProgressStatus);
  final _captureKey = GlobalKey();
  var _index = 0;
  var _autoAdvance = false;
  var _sharing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final autoAdvance = !MediaQuery.disableAnimationsOf(context);
    if (autoAdvance != _autoAdvance) {
      _autoAdvance = autoAdvance;
      _restartProgress();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _go(_index + 1);
  }

  void _restartProgress() {
    if (!_autoAdvance) {
      _progress.stop();
      return;
    }
    _progress.value = 0;
    if (_index < _slides.length - 1) {
      _progress.forward();
    } else {
      _progress.value = 1;
    }
  }

  void _go(int index) {
    if (index < 0 || index >= _slides.length) return;
    final motion = AppMotion.spatialSlow(
      context,
      AppMotionSpec(
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        Curves.easeOutCubic,
      ),
    );
    if (motion.duration == Duration.zero) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: motion.duration,
        curve: motion.curve,
      );
    }
  }

  /// Shares the visible slide, without the story controls, as an image.
  Future<void> _share() async {
    if (_sharing) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    setState(() => _sharing = true);
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return;
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/spotiflac_rewind.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: l10n.listeningRewindIntroTitle,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.listeningRewindShareError)),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palettes = [
      for (var i = 0; i < _slides.length; i++)
        _RewindPalette.of(context, i, widget.rewind),
    ];
    final palette = palettes[_index];
    final lastSlide = _index == _slides.length - 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          ThemeData.estimateBrightnessForColor(palette.background) ==
              Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: l10n.listeningRewindNext): () =>
              _go(_index + 1),
          CustomSemanticsAction(label: l10n.listeningRewindPrevious): () =>
              _go(_index - 1),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final width = context.size?.width ?? 0;
            _go(details.localPosition.dx < width / 3 ? _index - 1 : _index + 1);
          },
          onLongPressStart: (_) => _progress.stop(),
          onLongPressEnd: (_) {
            if (_autoAdvance && _index < _slides.length - 1) {
              _progress.forward();
            }
          },
          child: Stack(
            children: [
              RepaintBoundary(
                key: _captureKey,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _RewindBackdrop(
                        pages: _pages,
                        palettes: palettes,
                        artworks: [
                          for (final slide in _slides)
                            _slideArtwork(slide, widget.rewind),
                        ],
                      ),
                    ),
                    PageView.builder(
                      controller: _pages,
                      itemCount: _slides.length,
                      onPageChanged: (index) {
                        setState(() => _index = index);
                        _restartProgress();
                      },
                      itemBuilder: (context, index) => Semantics(
                        label: l10n.listeningRewindSlide(
                          index + 1,
                          _slides.length,
                        ),
                        child: _RewindSlide(
                          slide: _slides[index],
                          rewind: widget.rewind,
                          period: widget.period,
                          palette: palettes[index],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (lastSlide)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Center(
                        child: _Reveal(
                          order: 4,
                          child: AppActionButton(
                            onPressed: _sharing ? null : _share,
                            icon: const Icon(Icons.share),
                            label: Text(l10n.listeningRewindShare),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _progress,
                          builder: (context, _) => _StoryProgress(
                            count: _slides.length,
                            index: _index,
                            value: _autoAdvance ? _progress.value : 1,
                            color: palette.foreground,
                          ),
                        ),
                      ),
                      _CloseButton(color: palette.foreground),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryProgress extends StatelessWidget {
  const _StoryProgress({
    required this.count,
    required this.index,
    required this.value,
    required this.color,
  });

  final int count;
  final int index;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 4,
              decoration: ShapeDecoration(
                color: color.withValues(alpha: 0.28),
                shape: const StadiumBorder(),
              ),
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                heightFactor: 1,
                widthFactor: i < index
                    ? 1
                    : i == index
                    ? value.clamp(0.0, 1.0)
                    : 0,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: color,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Colors of one slide. Material cycles through the tonal containers;
/// Mornye stays dark over blurred artwork.
class _RewindPalette {
  const _RewindPalette(this.background, this.foreground, this.accent);

  factory _RewindPalette.of(
    BuildContext context,
    int index,
    ListeningRewind rewind,
  ) {
    if (context.isMornye) {
      return _RewindPalette(
        Colors.black,
        Colors.white,
        Theme.of(context).colorScheme.primary,
      );
    }
    final c = Theme.of(context).colorScheme;
    final pairs = [
      (c.primaryContainer, c.onPrimaryContainer, c.primary),
      (c.tertiaryContainer, c.onTertiaryContainer, c.tertiary),
      (c.secondaryContainer, c.onSecondaryContainer, c.secondary),
      (c.primary, c.onPrimary, c.primaryContainer),
      (c.tertiary, c.onTertiary, c.tertiaryContainer),
      (c.surfaceContainerHighest, c.onSurface, c.primary),
    ];
    final (background, foreground, accent) = pairs[index % pairs.length];
    return _RewindPalette(background, foreground, accent);
  }

  final Color background;
  final Color foreground;
  final Color accent;
}

class _RewindSlide extends StatelessWidget {
  const _RewindSlide({
    required this.slide,
    required this.rewind,
    required this.period,
    required this.palette,
  });

  final _Slide slide;
  final ListeningRewind rewind;
  final ListeningRewindPeriod period;
  final _RewindPalette palette;

  /// The slide's content only; [_RewindBackdrop] paints the shared, moving
  /// background behind every slide.
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          // Room for the progress bar above and the share button below.
          padding: const EdgeInsets.fromLTRB(28, 64, 28, 88),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              primary: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: palette.foreground),
                  child: IconTheme.merge(
                    data: IconThemeData(color: palette.foreground),
                    child: _content(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final number = NumberFormat.decimalPattern(locale);
    final shortDate = DateFormat.MMMd(locale);
    final minutes = rewind.minutes;
    String minutesOf(int milliseconds) =>
        l10n.listeningStatsMinutes((milliseconds / 60000).round());
    final tracks = rewind.summary.tracks;
    final artwork = rewind.summary.artistArtwork;
    final yearDetails = rewind.year;
    final yearLabel = '${rewind.range.start.year}';
    String monthName(int month) => DateFormat.MMMM(
      locale,
    ).format(DateTime(rewind.range.start.year, month));

    switch (slide) {
      case _Slide.intro:
        if (yearDetails != null) {
          return _Column(
            center: true,
            children: [
              _Eyebrow(l10n.listeningRewindYearEyebrow),
              _Headline(
                l10n.listeningRewindYearTitle(yearLabel),
                size: _Size.huge,
              ),
              _Body(l10n.listeningRewindYearIntroBody),
            ],
          );
        }
        return _Column(
          center: true,
          children: [
            _Eyebrow(listeningRewindPeriodLabel(context, period)),
            _Headline(l10n.listeningRewindIntroTitle, size: _Size.huge),
            _Body(
              l10n.listeningRewindIntroBody(
                shortDate.format(rewind.range.start),
                shortDate.format(rewind.range.lastDay),
              ),
            ),
          ],
        );
      case _Slide.yearNumbers:
        return _Column(
          children: [
            _Headline(l10n.listeningRewindNumbersTitle),
            _StatGrid(
              stats: [
                (tracks.length, l10n.listeningRewindSongsLabel),
                (rewind.topArtists.length, l10n.listeningRewindArtistsLabel),
                (rewind.topAlbums.length, l10n.listeningRewindAlbumsLabel),
                (rewind.activeDays, l10n.listeningRewindDaysLabel),
              ],
              format: number.format,
            ),
            // "0% of your days" reads as a mistake, so tiny shares stay out.
            if (rewind.activeDayShare >= 1)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _Pill(
                  l10n.listeningRewindDaysShare(rewind.activeDayShare),
                  color: palette.foreground,
                ),
              ),
          ],
        );
      case _Slide.months:
        final biggest = rewind.biggestMonth!;
        return _Column(
          children: [
            _Headline(l10n.listeningRewindMonthsTitle),
            _MonthChart(
              milliseconds: rewind.monthlyMilliseconds,
              highlight: biggest,
              year: rewind.range.start.year,
              accent: palette.foreground,
            ),
            _Body(l10n.listeningRewindBiggestMonth(monthName(biggest))),
          ],
        );
      case _Slide.monthlyArtists:
        final months = yearDetails!.monthlyTopArtists.keys.toList()..sort();
        return _Column(
          children: [
            _Headline(l10n.listeningRewindMonthlyArtistsTitle),
            _MonthArtists(
              months: [
                for (final month in months)
                  (
                    DateFormat.MMM(
                      locale,
                    ).format(DateTime(rewind.range.start.year, month)),
                    yearDetails.monthlyTopArtists[month]!,
                  ),
              ],
              artwork: artwork,
            ),
          ],
        );
      case _Slide.loyal:
        final name = yearDetails!.loyalArtist!;
        return _Column(
          center: true,
          children: [
            _Eyebrow(l10n.listeningRewindLoyalTitle),
            _Artwork(uri: artwork[name], size: 200, artist: true),
            _Headline(name, size: _Size.large),
            _Pill(
              l10n.listeningRewindLoyalBody(yearDetails.loyalArtistDays),
              color: palette.foreground,
            ),
          ],
        );
      case _Slide.firstSong:
        final first = yearDetails!.firstPlay!;
        return _Column(
          center: true,
          children: [
            _Eyebrow(l10n.listeningRewindFirstSongTitle),
            _Artwork(uri: first.track.artwork, size: 220),
            _Headline(first.track.title, size: _Size.large),
            _Body(first.track.artist),
            _Pill(
              l10n.listeningRewindFirstSongBody(shortDate.format(first.day)),
              color: palette.foreground,
            ),
          ],
        );
      case _Slide.minutes:
        final change = rewind.changePercent;
        return _Column(
          center: true,
          children: [
            _Eyebrow(l10n.listeningRewindMinutesTitle),
            _CountUp(value: minutes, format: number.format),
            _Headline(l10n.listeningRewindMinutesUnit(minutes)),
            if (minutes >= 60)
              _Body(l10n.listeningRewindHours((minutes / 60).round())),
            if (change != null)
              _Pill(
                change.abs() < 5
                    ? l10n.listeningRewindSame
                    : change > 0
                    ? l10n.listeningRewindMore(change)
                    : l10n.listeningRewindLess(change.abs()),
                color: palette.foreground,
              ),
            _Body(
              l10n.listeningStatsTotals(
                rewind.summary.plays,
                tracks.length,
                rewind.summary.days.length,
              ),
            ),
          ],
        );
      case _Slide.topArtist:
        final top = rewind.topArtists.first;
        return _Column(
          center: true,
          children: [
            _Eyebrow(l10n.listeningRewindTopArtistTitle),
            _Artwork(uri: artwork[top.key], size: 220, artist: true),
            _Headline(top.key, size: _Size.large),
            _Body(
              '${minutesOf(top.value)} · '
              '${l10n.listeningRewindArtistShare(rewind.topArtistShare)}',
            ),
          ],
        );
      case _Slide.artists:
        return _Column(
          children: [
            _Headline(l10n.listeningRewindArtistsTitle),
            for (final (index, artist) in rewind.topArtists.take(5).indexed)
              _RankedRow(
                rank: index + 1,
                artwork: _Artwork(
                  uri: artwork[artist.key],
                  size: 56,
                  artist: true,
                ),
                title: artist.key,
                subtitle: minutesOf(artist.value),
              ),
          ],
        );
      case _Slide.topTrack:
        final top = tracks.first;
        return _Column(
          center: true,
          children: [
            _Eyebrow(l10n.listeningRewindTopTrackTitle),
            _Artwork(uri: top.track.artwork, size: 240),
            _Headline(top.track.title, size: _Size.large),
            _Body(top.track.artist),
            _Pill(
              '${l10n.listeningRewindPlays(top.plays)} · '
              '${minutesOf(top.milliseconds)}',
              color: palette.foreground,
            ),
          ],
        );
      case _Slide.tracks:
        return _Column(
          children: [
            _Headline(l10n.listeningRewindTracksTitle),
            for (final (index, total) in tracks.take(5).indexed)
              _RankedRow(
                rank: index + 1,
                artwork: _Artwork(uri: total.track.artwork, size: 56),
                title: total.track.title,
                subtitle: total.track.artist,
              ),
          ],
        );
      case _Slide.album:
        final album = rewind.topAlbums.first;
        return _Column(
          center: true,
          children: [
            _Eyebrow(l10n.listeningRewindTopAlbumTitle),
            _Artwork(uri: album.artwork, size: 240),
            _Headline(album.album, size: _Size.large),
            _Body('${album.artist} · ${minutesOf(album.milliseconds)}'),
          ],
        );
      case _Slide.discoveries:
        final count = rewind.newArtists.length;
        return _Column(
          center: true,
          children: [
            _Eyebrow(l10n.listeningRewindNewArtistsTitle),
            _CountUp(value: count, format: number.format),
            _Body(l10n.listeningRewindNewArtistsBody(count)),
            for (final name in rewind.newArtists.take(3))
              _RankedRow(
                artwork: _Artwork(uri: artwork[name], size: 48, artist: true),
                title: name,
                subtitle: minutesOf(rewind.summary.artists[name] ?? 0),
              ),
          ],
        );
      case _Slide.rhythm:
        final weekday = rewind.favoriteWeekday;
        return _Column(
          children: [
            _Headline(l10n.listeningRewindRhythmTitle),
            _Fact(
              label: l10n.listeningRewindPeakDay,
              value: shortDate.format(rewind.peakDay!),
              detail: minutesOf(rewind.peakDayMilliseconds),
            ),
            if (weekday != null)
              _Fact(
                label: l10n.listeningRewindFavoriteDay,
                // 1 January 2024 was a Monday.
                value: DateFormat.EEEE(
                  locale,
                ).format(DateTime(2024, 1, weekday)),
              ),
            _Fact(
              label: l10n.listeningRewindStreak,
              value: l10n.listeningRewindStreakDays(rewind.longestStreak),
            ),
          ],
        );
      case _Slide.replay:
        final replay = rewind.replay!;
        return _Column(
          center: true,
          children: [
            _Eyebrow(l10n.listeningRewindReplayTitle),
            _Artwork(uri: replay.track.artwork, size: 220),
            _Headline(replay.track.title, size: _Size.large),
            _Body(replay.track.artist),
            _Pill(
              l10n.listeningRewindReplayBody(
                replay.plays,
                shortDate.format(replay.day),
              ),
              color: palette.foreground,
            ),
          ],
        );
      case _Slide.outro:
        final biggestMonth = rewind.biggestMonth;
        return _Column(
          children: [
            _Headline(
              yearDetails != null
                  ? l10n.listeningRewindYearOutroTitle(yearLabel)
                  : l10n.listeningRewindOutroTitle,
              size: _Size.large,
            ),
            _Body(
              yearDetails != null
                  ? l10n.listeningRewindYearOutroBody
                  : l10n.listeningRewindOutroBody,
            ),
            _Fact(
              label: l10n.listeningRewindMinutesTitle,
              value:
                  '${number.format(minutes)} '
                  '${l10n.listeningRewindMinutesUnit(minutes)}',
            ),
            if (rewind.topArtists.isNotEmpty)
              _Fact(
                label: l10n.listeningRewindTopArtistTitle,
                value: rewind.topArtists.first.key,
              ),
            if (tracks.isNotEmpty)
              _Fact(
                label: l10n.listeningRewindTopTrackTitle,
                value: tracks.first.track.title,
              ),
            if (yearDetails != null && biggestMonth != null)
              _Fact(
                label: l10n.listeningRewindBiggestMonthLabel,
                value: monthName(biggestMonth),
              ),
            if (rewind.longestStreak > 1)
              _Fact(
                label: l10n.listeningRewindStreak,
                value: l10n.listeningRewindStreakDays(rewind.longestStreak),
              ),
          ],
        );
    }
  }
}

/// Artwork the Mornye backdrop shows behind [slide].
String? _slideArtwork(_Slide slide, ListeningRewind rewind) => switch (slide) {
  _Slide.topArtist ||
  _Slide.artists ||
  _Slide.monthlyArtists ||
  _Slide.discoveries =>
    rewind.summary.artistArtwork[rewind.topArtists.first.key],
  _Slide.loyal => rewind.summary.artistArtwork[rewind.year?.loyalArtist],
  _Slide.firstSong => rewind.year?.firstPlay?.track.artwork,
  _Slide.album => rewind.topAlbums.first.artwork,
  _Slide.replay => rewind.replay?.track.artwork,
  _ => rewind.summary.tracks.firstOrNull?.track.artwork,
};

/// One background behind every slide, so colors blend while swiping.
///
/// Material floats large expressive shapes that drift, turn and follow the
/// swipe. Mornye cross-fades the slides' blurred artwork while it slowly
/// zooms. Reduced motion keeps the shapes and artwork still.
class _RewindBackdrop extends StatefulWidget {
  const _RewindBackdrop({
    required this.pages,
    required this.palettes,
    required this.artworks,
  });

  final PageController pages;
  final List<_RewindPalette> palettes;
  final List<String?> artworks;

  @override
  State<_RewindBackdrop> createState() => _RewindBackdropState();
}

class _RewindBackdropState extends State<_RewindBackdrop>
    with SingleTickerProviderStateMixin {
  late final _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ambient.stop();
    } else if (!_ambient.isAnimating) {
      _ambient.repeat();
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  double get _page {
    final pages = widget.pages;
    if (pages.hasClients && pages.position.haveDimensions) {
      return pages.page ?? 0;
    }
    return pages.initialPage.toDouble();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.pages, _ambient]),
        builder: (context, _) {
          final last = widget.palettes.length - 1;
          final page = _page.clamp(0.0, last.toDouble());
          final from = page.floor();
          final to = math.min(from + 1, last);
          final blend = page - from;
          final t = _ambient.value * 2 * math.pi;
          return context.isMornye
              ? _mornye(from, to, blend, t)
              : _material(from, to, blend, page, t);
        },
      ),
    ),
  );

  Widget _material(int from, int to, double blend, double page, double t) {
    final a = widget.palettes[from];
    final b = widget.palettes[to];
    final foreground = Color.lerp(a.foreground, b.foreground, blend)!;
    final accent = Color.lerp(a.accent, b.accent, blend)!;
    // Each shape drifts on its own orbit, turns slowly, and leans into the
    // swipe so the background feels continuous across slides.
    Widget shape({
      required M3EShapeKind kind,
      required double size,
      required Alignment alignment,
      required Offset orbit,
      required double speed,
      required double spin,
      required Color color,
    }) => Align(
      alignment: alignment,
      child: Transform.translate(
        offset: Offset(
          math.sin(t * speed) * orbit.dx - page * size * 0.12,
          math.cos(t * speed) * orbit.dy,
        ),
        child: Transform.rotate(
          angle: t * spin + page * 0.5,
          child: Transform.scale(
            scale: 1 + 0.05 * math.sin(t * speed * 2),
            child: AppShapeBadge(
              kind: kind,
              size: size,
              color: color,
              child: const SizedBox(),
            ),
          ),
        ),
      ),
    );
    return ColoredBox(
      color: Color.lerp(a.background, b.background, blend)!,
      child: Stack(
        fit: StackFit.expand,
        children: [
          shape(
            kind: AppShapes.badge,
            size: 340,
            alignment: const Alignment(1.6, -1.1),
            orbit: const Offset(18, 14),
            speed: 1,
            spin: 0.25,
            color: foreground.withValues(alpha: 0.07),
          ),
          shape(
            kind: AppShapes.brand,
            size: 260,
            alignment: const Alignment(-1.7, 1.15),
            orbit: const Offset(14, 20),
            speed: 1.3,
            spin: -0.2,
            color: foreground.withValues(alpha: 0.07),
          ),
          shape(
            kind: AppShapes.artist,
            size: 96,
            alignment: const Alignment(0.95, 0.72),
            orbit: const Offset(10, 16),
            speed: 2,
            spin: 0.6,
            color: accent.withValues(alpha: 0.35),
          ),
          shape(
            kind: AppShapes.badge,
            size: 56,
            alignment: const Alignment(-0.85, -0.55),
            orbit: const Offset(12, 8),
            speed: 1.7,
            spin: -0.8,
            color: accent.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _mornye(int from, int to, double blend, double t) {
    Widget artwork(String? uri, double opacity) => uri == null || opacity <= 0
        ? const SizedBox.shrink()
        : Opacity(
            opacity: opacity,
            child: Transform.scale(
              // A slow Ken Burns drift.
              scale: 1.15 + 0.06 * math.sin(t),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                child: PlayerArtwork(
                  artUri: uri,
                  colorScheme: Theme.of(context).colorScheme,
                  cacheWidth: 200,
                ),
              ),
            ),
          );
    final current = widget.artworks[from];
    final next = widget.artworks[to];
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (current == next)
            artwork(current, 1)
          else ...[
            artwork(current, 1 - blend),
            artwork(next, blend),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide content with a staggered spring entrance.
class _Column extends StatelessWidget {
  const _Column({required this.children, this.center = false});

  final List<Widget> children;
  final bool center;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    textAlign: center ? TextAlign.center : TextAlign.start,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.stretch,
      children: [
        for (final (index, child) in children.indexed)
          _Reveal(
            order: index,
            child: Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
              child: child,
            ),
          ),
      ],
    ),
  );
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final motion = AppMotion.spatial(
      context,
      AppMotionSpec(
        reduced ? Duration.zero : const Duration(milliseconds: 420),
        Curves.easeOutCubic,
      ),
    );
    if (motion.duration == Duration.zero) return child;
    const stagger = Duration(milliseconds: 90);
    final total = motion.duration + stagger * order;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(
        stagger.inMicroseconds * order / total.inMicroseconds,
        1,
        curve: motion.curve,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 28 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.format, this.fontSize});

  final int value;
  final String Function(num) format;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: reduced ? value.toDouble() : 0,
        end: value.toDouble(),
      ),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (context, current, _) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          format(current.round()),
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontSize: fontSize ?? 96,
            height: 1,
            fontWeight: FontWeight.w800,
            color: DefaultTextStyle.of(context).style.color,
          ),
        ),
      ),
    );
  }
}

enum _Size { regular, large, huge }

class _Headline extends StatelessWidget {
  const _Headline(this.text, {this.size = _Size.regular});

  final String text;
  final _Size size;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = switch (size) {
      _Size.regular => textTheme.headlineMedium,
      _Size.large => textTheme.headlineLarge,
      _Size.huge => textTheme.displayMedium,
    };
    return Text(
      text,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: style?.copyWith(
        fontWeight: FontWeight.w800,
        color: DefaultTextStyle.of(context).style.color,
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.8),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.85),
    ),
  );
}

/// A short highlighted statement. A tinted pill rather than a card.
class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: color.withValues(alpha: 0.14),
      shape: const StadiumBorder(),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: DefaultTextStyle.of(context).style.color,
        ),
      ),
    ),
  );
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.uri, required this.size, this.artist = false});

  final String? uri;
  final double size;
  final bool artist;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final image = SizedBox.square(
      dimension: size,
      child: uri == null
          ? ColoredBox(
              color: colors.surfaceContainerHighest,
              child: AppIcon(
                artist ? Icons.person : Icons.music_note,
                size: size * 0.4,
                color: colors.onSurfaceVariant,
              ),
            )
          : PlayerArtwork(
              artUri: uri,
              colorScheme: colors,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              iconSize: size * 0.4,
            ),
    );
    if (artist) return AppShapeClip(kind: AppShapes.artist, child: image);
    final radius = context.isMornye
        ? size * 0.06
        : size >= 120
        ? 28.0
        : 12.0;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

class _RankedRow extends StatelessWidget {
  const _RankedRow({
    required this.artwork,
    required this.title,
    required this.subtitle,
    this.rank,
  });

  final int? rank;
  final Widget artwork;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = DefaultTextStyle.of(context).style.color;
    return Row(
      children: [
        if (rank case final rank?)
          SizedBox(
            width: 40,
            child: Text(
              '$rank',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color?.withValues(alpha: 0.55),
              ),
            ),
          ),
        artwork,
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: color?.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Big counted-up figures in a two-column grid.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats, required this.format});

  final List<(int, String)> stats;
  final String Function(num) format;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = DefaultTextStyle.of(context).style.color;
    Widget stat((int, String) entry) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CountUp(value: entry.$1, format: format, fontSize: 56),
        Text(
          entry.$2,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color?.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
    return Column(
      children: [
        for (var i = 0; i < stats.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: stat(stats[i])),
              const SizedBox(width: 16),
              Expanded(
                child: i + 1 < stats.length
                    ? stat(stats[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Twelve bars of monthly listening; [highlight] stands out at full color.
class _MonthChart extends StatelessWidget {
  const _MonthChart({
    required this.milliseconds,
    required this.highlight,
    required this.year,
    required this.accent,
  });

  final Map<int, int> milliseconds;
  final int highlight;
  final int year;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    // Stand-alone narrow month names (J, F, M...).
    final narrow = DateFormat('LLLLL', locale);
    final peak = milliseconds.values.fold(0, math.max);
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: accent.withValues(alpha: 0.8),
    );
    final reduced = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: 180,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var month = 1; month <= 12; month++) ...[
              if (month > 1) const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        // Bars grow from the baseline, the peak month last.
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: reduced ? 1 : 0, end: 1),
                          duration: reduced
                              ? Duration.zero
                              : Duration(milliseconds: 600 + month * 60),
                          curve: Curves.easeOutCubic,
                          builder: (context, t, _) => FractionallySizedBox(
                            heightFactor:
                                peak <= 0 || (milliseconds[month] ?? 0) <= 0
                                ? 0
                                : math.max(
                                        0.04,
                                        (milliseconds[month] ?? 0) / peak,
                                      ) *
                                      t,
                            child: DecoratedBox(
                              decoration: ShapeDecoration(
                                color: month == highlight
                                    ? accent
                                    : accent.withValues(alpha: 0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const SizedBox(width: double.infinity),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      narrow.format(DateTime(year, month)),
                      style: labelStyle,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Each month beside the artist heard longest that month, in two columns.
class _MonthArtists extends StatelessWidget {
  const _MonthArtists({required this.months, required this.artwork});

  /// Short month name and artist, in calendar order.
  final List<(String, String)> months;
  final Map<String, String> artwork;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = DefaultTextStyle.of(context).style.color;
    Widget row((String, String) entry) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          _Artwork(uri: artwork[entry.$2], size: 36, artist: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.$1,
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color?.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  entry.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final half = (months.length / 2).ceil();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(children: [for (final e in months.take(half)) row(e)]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(children: [for (final e in months.skip(half)) row(e)]),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = DefaultTextStyle.of(context).style.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelLarge?.copyWith(
            color: color?.withValues(alpha: 0.75),
          ),
        ),
        Text(
          detail == null ? value : '$value · $detail',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

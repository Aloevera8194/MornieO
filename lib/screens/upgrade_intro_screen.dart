import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart'
    show
        M3EShapeKind,
        Morph,
        MorphToPathExtension,
        RoundedPolygonToPathExtension;
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/theme_settings.dart';
import 'package:spotiflac_android/providers/theme_provider.dart';
import 'package:spotiflac_android/services/upgrade_intro_service.dart';
import 'package:spotiflac_android/theme/app_theme.dart';
import 'package:spotiflac_android/theme/mornye_icons.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/app_icon_button.dart';
import 'package:spotiflac_android/widgets/app_shape.dart';
import 'package:spotiflac_android/widgets/beta_badge.dart';
import 'package:spotiflac_android/widgets/expressive_button.dart';

/// A local, replayable release tour. Theme changes require an explicit choice.
class UpgradeIntroScreen extends StatefulWidget {
  const UpgradeIntroScreen({super.key});

  @override
  State<UpgradeIntroScreen> createState() => _UpgradeIntroScreenState();
}

class _UpgradeIntroScreenState extends State<UpgradeIntroScreen> {
  static const _pageCount = 6;

  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
  }

  void _finish() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final mornye = context.isMornye;
    final last = _page == _pageCount - 1;
    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(_page - 1);
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        if (_page > 0)
                          AppIconButton(
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).backButtonTooltip,
                            onPressed: () => _goTo(_page - 1),
                            color: scheme.primary,
                            icon: Icon(
                              mornye
                                  ? CupertinoIcons.chevron_back
                                  : Icons.arrow_back,
                            ),
                          )
                        else
                          const SizedBox(width: 48, height: 48),
                        Expanded(
                          child: _PageIndicator(count: _pageCount, page: _page),
                        ),
                        ExpressiveButton(
                          text: true,
                          onPressed: _finish,
                          child: Text(l10n.upgradeIntroSkip),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pages,
                      onPageChanged: (page) => setState(() => _page = page),
                      children: [
                        _TourPage(
                          hero: const _TourHero(
                            shape: M3EShapeKind.cookie12Sided,
                            accent: M3EShapeKind.sunny,
                            logo: true,
                          ),
                          title: l10n.whatsNewWelcomeTitle(
                            UpgradeIntroService.tourVersion,
                          ),
                          description: l10n.whatsNewWelcomeBody,
                          features: [
                            _TourFeature(
                              icon: Icons.interests_outlined,
                              title: 'Material 3 Expressive',
                              body: l10n.whatsNewSummaryExpressiveBody,
                            ),
                            _TourFeature(
                              icon: Icons.play_circle_outline,
                              title: l10n.whatsNewSummaryPlayerTitle,
                              body: l10n.whatsNewSummaryPlayerBody,
                            ),
                            _TourFeature(
                              icon: Icons.format_quote_outlined,
                              title: l10n.lyricsShareTitle,
                              body: l10n.whatsNewSummaryLyricsBody,
                            ),
                          ],
                        ),
                        _TourPage(
                          hero: const _TourHero(
                            icon: Icons.palette_outlined,
                            shape: M3EShapeKind.flower,
                            accent: M3EShapeKind.pill,
                          ),
                          title: l10n.upgradeIntroThemeTitle,
                          description: l10n.upgradeIntroThemeBody,
                          child: const _ThemePicker(),
                        ),
                        _TourPage(
                          hero: const _TourHero(
                            icon: Icons.interests_outlined,
                            shape: M3EShapeKind.softBurst,
                            accent: M3EShapeKind.clover4Leaf,
                          ),
                          title: l10n.whatsNewExpressiveTitle,
                          description: l10n.whatsNewExpressiveBody,
                          features: [
                            _TourFeature(
                              icon: Icons.category_outlined,
                              title: l10n.whatsNewSymbolsTitle,
                              body: l10n.whatsNewSymbolsBody,
                            ),
                            _TourFeature(
                              icon: Icons.animation_outlined,
                              title: l10n.whatsNewMotionTitle,
                              body: l10n.whatsNewMotionBody,
                            ),
                            _TourFeature(
                              icon: Icons.tablet_outlined,
                              title: l10n.whatsNewLargeScreenTitle,
                              body: l10n.whatsNewLargeScreenBody,
                            ),
                          ],
                        ),
                        _TourPage(
                          hero: const _TourHero(
                            icon: Icons.graphic_eq,
                            shape: M3EShapeKind.cookie9Sided,
                            accent: M3EShapeKind.burst,
                          ),
                          title: l10n.whatsNewPlayerTitle,
                          description: l10n.whatsNewPlayerBody,
                          features: [
                            _TourFeature(
                              icon: Icons.equalizer,
                              title: l10n.equalizerTitle,
                              beta: true,
                              body: l10n.whatsNewEqualizerBody,
                            ),
                            _TourFeature(
                              icon: Icons.fullscreen,
                              title: l10n.whatsNewCoverTitle,
                              body: l10n.whatsNewCoverBody,
                            ),
                            _TourFeature(
                              icon: Icons.info_outline,
                              title: l10n.whatsNewAudioInfoTitle,
                              body: l10n.whatsNewAudioInfoBody,
                            ),
                            _TourFeature(
                              icon: Icons.vibration,
                              title: l10n.musicHaptics,
                              body: l10n.whatsNewHapticsBody,
                            ),
                          ],
                        ),
                        _TourPage(
                          hero: const _TourHero(
                            icon: Icons.format_quote_outlined,
                            shape: M3EShapeKind.puffy,
                            accent: M3EShapeKind.cookie4Sided,
                          ),
                          title: l10n.whatsNewLyricsTitle,
                          description: l10n.whatsNewLyricsBody,
                          features: [
                            _TourFeature(
                              icon: Icons.ios_share,
                              title: l10n.whatsNewLyricCardsTitle,
                              body: l10n.whatsNewLyricCardsBody,
                            ),
                            _TourFeature(
                              icon: Icons.lyrics_outlined,
                              title: l10n.whatsNewLyricSyncTitle,
                              body: l10n.whatsNewLyricSyncBody,
                            ),
                            _TourFeature(
                              icon: Icons.cloud_done_outlined,
                              title: l10n.whatsNewLyricFallbackTitle,
                              body: l10n.whatsNewLyricFallbackBody,
                            ),
                          ],
                        ),
                        _TourPage(
                          hero: const _TourHero(
                            icon: Icons.library_music_outlined,
                            shape: M3EShapeKind.clover8Leaf,
                            accent: M3EShapeKind.gem,
                          ),
                          title: l10n.whatsNewLibraryTitle,
                          description: l10n.whatsNewLibraryBody,
                          features: [
                            _TourFeature(
                              icon: Icons.view_agenda_outlined,
                              title: l10n.whatsNewBrowseTitle,
                              body: l10n.whatsNewBrowseBody,
                            ),
                            _TourFeature(
                              icon: Icons.history,
                              title: l10n.listeningRewind,
                              body: l10n.whatsNewRewindBody,
                            ),
                            _TourFeature(
                              icon: Icons.waving_hand_outlined,
                              title: l10n.whatsNewGreetingTitle,
                              body: l10n.whatsNewGreetingBody,
                            ),
                            // The redesigned launcher widgets are Android's.
                            if (Platform.isAndroid)
                              _TourFeature(
                                icon: Icons.widgets_outlined,
                                title: l10n.whatsNewWidgetsTitle,
                                body: l10n.whatsNewWidgetsBody,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ExpressiveButton(
                        onPressed: last ? _finish : () => _goTo(_page + 1),
                        icon: last
                            ? null
                            : Icon(
                                mornye
                                    ? CupertinoIcons.arrow_right
                                    : Icons.arrow_forward,
                              ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: mornye
                              ? RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                )
                              : null,
                          textStyle: Theme.of(context).textTheme.titleMedium,
                        ),
                        child: Text(
                          last
                              ? l10n.upgradeIntroDone
                              : l10n.upgradeIntroContinue,
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
    );
  }
}

/// Dots that stretch into a pill for the current page.
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.page});

  final int count;
  final int page;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 360);
    return Semantics(
      label: '${page + 1} / $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < count; index++)
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutBack,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: index == page ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: index == page
                      ? scheme.primary
                      : index < page
                      ? scheme.primary.withValues(alpha: 0.38)
                      : scheme.outlineVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TourPage extends StatelessWidget {
  const _TourPage({
    required this.hero,
    required this.title,
    required this.description,
    this.features = const [],
    this.child,
  });

  final Widget hero;
  final String title;
  final String description;
  final List<_TourFeature> features;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mornye = context.isMornye;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: hero),
          const SizedBox(height: 24),
          Text(
            title,
            style: mornye
                ? theme.textTheme.headlineLarge?.copyWith(
                    fontSize: 36,
                    height: 1.08,
                    letterSpacing: -1.2,
                    fontWeight: FontWeight.w700,
                  )
                : theme.textTheme.displaySmall?.copyWith(
                    height: 1.1,
                    letterSpacing: -0.4,
                    fontWeight: FontWeight.w500,
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 17,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          ?child,
          for (var index = 0; index < features.length; index++)
            _FeatureRow(
              feature: features[index],
              index: index,
              first: index == 0,
              last: index == features.length - 1,
            ),
        ],
      ),
    );
  }
}

/// A large expressive shape with two smaller ones beside it, over a faint
/// tonal glow. It springs in with its page, morphs once on its own, and
/// morphs into the next shape on each tap.
class _TourHero extends StatefulWidget {
  const _TourHero({
    required this.shape,
    required this.accent,
    this.icon,
    this.logo = false,
  });

  final M3EShapeKind shape;
  final M3EShapeKind accent;
  final IconData? icon;
  final bool logo;

  @override
  State<_TourHero> createState() => _TourHeroState();
}

class _TourHeroState extends State<_TourHero> with TickerProviderStateMixin {
  /// Shapes the hero morphs through, after the page's own shape.
  static const _cycle = [
    M3EShapeKind.cookie12Sided,
    M3EShapeKind.flower,
    M3EShapeKind.softBurst,
    M3EShapeKind.cookie9Sided,
    M3EShapeKind.puffy,
    M3EShapeKind.clover8Leaf,
    M3EShapeKind.sunny,
    M3EShapeKind.cookie6Sided,
  ];

  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    value: 1,
  );
  late M3EShapeKind _to = widget.shape;
  Morph? _shapeMorph;
  int _turns = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
      return;
    }
    // One unprompted morph shows the shape can change.
    _entrance.forward().whenComplete(() {
      if (mounted) _next();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    _morph.dispose();
    super.dispose();
  }

  void _next() {
    if (context.isMornye || MediaQuery.disableAnimationsOf(context)) return;
    final from = _to;
    _to = _cycle[(_cycle.indexOf(from) + 1) % _cycle.length];
    _shapeMorph = Morph(from.polygon, _to.polygon);
    _turns++;
    _morph.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mornye = context.isMornye;
    final accent = widget.accent;
    // The logo asset is a disc with the glyph cut out. Tinting the disc like
    // the shape and backing it with a smaller dark circle leaves only the
    // glyph visible on the expressive shape.
    final glyph = widget.logo
        ? Stack(
            alignment: Alignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.onPrimaryContainer,
                ),
                child: const SizedBox.square(dimension: 92),
              ),
              Image.asset(
                'assets/images/logo-transparent.png',
                width: 96,
                height: 96,
                color: scheme.primaryContainer,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ],
          )
        : Icon(
            context.adaptiveIcon(widget.icon!),
            size: 56,
            color: scheme.onPrimaryContainer,
          );
    // Decorative: tapping to morph is a small extra, not a control.
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: Listenable.merge([_entrance, _morph]),
        child: glyph,
        builder: (context, glyph) {
          final t = Curves.elasticOut.transform(_entrance.value);
          final morph = Curves.easeInOutCubicEmphasized.transform(_morph.value);
          // Each morph adds an eighth of a turn, settling with a spring.
          final turn =
              (_turns - 1 + Curves.elasticOut.transform(_morph.value)) *
              math.pi /
              4;
          final shape = GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _next();
            },
            child: Transform.rotate(
              angle: (1 - t) * -0.35 + turn,
              child: Transform.scale(
                scale: 0.6 + 0.4 * t,
                child: SizedBox.square(
                  dimension: 132,
                  child: CustomPaint(
                    painter: _MorphPainter(
                      morph: mornye ? null : _shapeMorph,
                      kind: mornye ? M3EShapeKind.circle : _to,
                      progress: morph,
                      color: scheme.primaryContainer,
                    ),
                    // Keep the glyph upright while the shape turns.
                    child: Transform.rotate(
                      angle: -turn,
                      child: Center(child: glyph),
                    ),
                  ),
                ),
              ),
            ),
          );
          return _heroStage(scheme, accent, t, shape);
        },
      ),
    );
  }

  Widget _heroStage(
    ColorScheme scheme,
    M3EShapeKind accent,
    double t,
    Widget child,
  ) => SizedBox(
    width: 220,
    height: 172,
    child: Stack(
      alignment: Alignment.center,
      children: [
        // A thin tonal glow behind the shape.
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                scheme.primary.withValues(alpha: 0.14),
                scheme.primary.withValues(alpha: 0),
              ],
            ),
          ),
          child: const SizedBox.square(dimension: 220),
        ),
        child,
        Positioned(
          right: 18,
          top: 8,
          child: Transform.scale(
            scale: t,
            child: AppShapeBadge(
              kind: accent,
              size: 44,
              color: scheme.tertiaryContainer,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
        Positioned(
          left: 30,
          bottom: 16,
          child: Transform.scale(
            scale: t,
            child: AppShapeBadge(
              kind: M3EShapeKind.circle,
              size: 20,
              color: scheme.secondaryContainer,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Fills the shape between two expressive polygons; [morph] null draws [kind].
class _MorphPainter extends CustomPainter {
  const _MorphPainter({
    required this.morph,
    required this.kind,
    required this.progress,
    required this.color,
  });

  final Morph? morph;
  final M3EShapeKind kind;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Catalog polygons are normalized to the unit square.
    final unit = morph?.toPath(progress: progress) ?? kind.polygon.toPath();
    final scale = Matrix4.diagonal3Values(size.width, size.height, 1);
    canvas.drawPath(
      unit.transform(scale.storage),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_MorphPainter oldDelegate) =>
      morph != oldDelegate.morph ||
      kind != oldDelegate.kind ||
      progress != oldDelegate.progress ||
      color != oldDelegate.color;
}

class _TourFeature {
  const _TourFeature({
    required this.icon,
    required this.title,
    required this.body,
    this.beta = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool beta;
}

/// One row of a connected list: large outer corners, small inner ones.
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.feature,
    required this.index,
    required this.first,
    required this.last,
  });

  static const _shapes = [
    M3EShapeKind.cookie4Sided,
    M3EShapeKind.pentagon,
    M3EShapeKind.cookie6Sided,
    M3EShapeKind.clover4Leaf,
  ];

  final _TourFeature feature;
  final int index;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outer = Radius.circular(context.isMornye ? 18 : 24);
    const inner = Radius.circular(6);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 2),
      child: MergeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.vertical(
              top: first ? outer : inner,
              bottom: last ? outer : inner,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppShapeBadge(
                kind: _shapes[index % _shapes.length],
                size: 44,
                color: scheme.secondaryContainer,
                child: Icon(
                  context.adaptiveIcon(feature.icon),
                  size: 22,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          feature.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (feature.beta) const BetaBadge(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feature.body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeProvider);
    final brightness = Theme.of(context).brightness;
    final l10n = context.l10n;
    return Column(
      children: [
        for (final style in AppThemeStyle.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Theme(
              data: style == AppThemeStyle.mornye
                  ? MornyeTheme.build(
                      brightness,
                      accent: settings.mornyeAccent,
                      useSystemFont: settings.useSystemFont,
                      glassClarity: settings.mornyeGlassClarity,
                      glassOutlines: settings.mornyeGlassOutlines,
                    )
                  : brightness == Brightness.dark
                  ? AppTheme.dark(
                      seedColor: settings.seedColor,
                      isAmoled: settings.useAmoled,
                      useSystemFont: settings.useSystemFont,
                    )
                  : AppTheme.light(
                      seedColor: settings.seedColor,
                      useSystemFont: settings.useSystemFont,
                    ),
              child: _ThemeOption(
                style: style,
                selected: settings.style == style,
                label: style == AppThemeStyle.mornye ? 'Mornye' : 'Material',
                description: style == AppThemeStyle.mornye
                    ? l10n.upgradeIntroThemeMornyeBody
                    : l10n.whatsNewThemeMaterialBody,
                onTap: () => ref.read(themeProvider.notifier).setStyle(style),
              ),
            ),
          ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.style,
    required this.selected,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final AppThemeStyle style;
  final bool selected;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mornye = style == AppThemeStyle.mornye;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);
    return Semantics(
      selected: selected,
      // The container clips its ink, so the press follows the morphing corners.
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(
            mornye ? (selected ? 22 : 16) : (selected ? 32 : 16),
          ),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('intro-theme-${style.name}'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? scheme.onSecondaryContainer
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      AnimatedContainer(
                        duration: duration,
                        curve: Curves.easeOutBack,
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary : null,
                          borderRadius: BorderRadius.circular(
                            selected ? 9 : 14,
                          ),
                          border: selected
                              ? null
                              : Border.all(color: scheme.outline, width: 2),
                        ),
                        child: selected
                            ? Icon(
                                Icons.check_rounded,
                                size: 20,
                                color: scheme.onPrimary,
                              )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        for (final icon in [
                          Icons.home_rounded,
                          Icons.library_music,
                          Icons.extension,
                          mornye ? Icons.search : Icons.settings_outlined,
                        ])
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: icon == Icons.home_rounded
                                  ? mornye
                                        ? scheme.onSurface.withValues(
                                            alpha: 0.08,
                                          )
                                        : scheme.primary.withValues(alpha: 0.14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Icon(
                              mornye
                                  ? icon == Icons.home_rounded
                                        ? CupertinoIcons.house_fill
                                        : mornyeIconFor(icon)
                                  : icon,
                              size: 22,
                              color: icon == Icons.home_rounded
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
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
      ),
    );
  }
}

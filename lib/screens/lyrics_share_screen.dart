import 'dart:io';
import 'dart:ui' show ImageByteFormat, ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';
import 'package:spotiflac_android/utils/lyrics_parser.dart';
import 'package:spotiflac_android/widgets/app_icon.dart';
import 'package:spotiflac_android/widgets/app_icon_button.dart';
import 'package:spotiflac_android/widgets/expressive_button.dart';
import 'package:spotiflac_android/widgets/player_artwork.dart';

/// Story-sized lyric cards stay short, like quoting a song rather than
/// reproducing its lyrics.
const lyricsShareMaxLines = 5;

/// The logical size of the shared card; captured at 3× for 1080×1920.
const lyricsShareCardSize = Size(360, 640);

/// One selectable lyric line.
typedef LyricsShareLine = ({String text, bool background});

/// Lines a card can quote: timed lines in order, or the plain text's lines.
List<LyricsShareLine> lyricsShareLines(ParsedLyrics lyrics) {
  if (lyrics.lines.isNotEmpty) {
    return [
      for (final line in lyrics.lines)
        if (line.text.trim().isNotEmpty)
          (text: line.text.trim(), background: line.isBackground),
    ];
  }
  return [
    for (final line in lyrics.plainText.split(RegExp(r'\r\n|\r|\n')))
      if (line.trim().isNotEmpty) (text: line.trim(), background: false),
  ];
}

/// Opens the lyric card editor. [initial] preselects the line the user
/// long-pressed in the player.
Future<void> openLyricsShare(
  BuildContext context, {
  required MediaItem mediaItem,
  required ParsedLyrics lyrics,
  LyricLine? initial,
}) {
  final lines = lyricsShareLines(lyrics);
  var selected = -1;
  if (initial != null) {
    var row = 0;
    for (final line in lyrics.lines) {
      if (line.text.trim().isEmpty) continue;
      if (line.time == initial.time &&
          line.text.trim() == initial.text.trim()) {
        selected = row;
        break;
      }
      row++;
    }
  }
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => LyricsShareScreen(
        mediaItem: mediaItem,
        lines: lines,
        initialSelection: {if (selected >= 0) selected},
      ),
    ),
  );
}

enum LyricsCardBackground { artwork, color, dark, light }

class LyricsShareScreen extends StatefulWidget {
  const LyricsShareScreen({
    super.key,
    required this.mediaItem,
    required this.lines,
    this.initialSelection = const {},
  });

  final MediaItem mediaItem;
  final List<LyricsShareLine> lines;
  final Set<int> initialSelection;

  @override
  State<LyricsShareScreen> createState() => _LyricsShareScreenState();
}

class _LyricsShareScreenState extends State<LyricsShareScreen> {
  final _cardKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  late final Set<int> _selected = {...widget.initialSelection};
  late final ScrollController _list = ScrollController(
    initialScrollOffset: widget.initialSelection.isEmpty
        ? 0
        : (widget.initialSelection.first - 2).clamp(0, 1 << 20) * 52.0,
  );
  LyricsCardBackground _background = LyricsCardBackground.artwork;
  bool _sharing = false;

  String? get _artSource {
    final art = widget.mediaItem.artUri;
    if (art == null) return null;
    return art.scheme == 'file' ? art.toFilePath() : art.toString();
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  void _toggle(int index) {
    setState(() {
      if (_selected.remove(index)) return;
      if (_selected.length >= lyricsShareMaxLines) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.l10n.lyricsShareLimit(lyricsShareMaxLines)),
            ),
          );
        return;
      }
      _selected.add(index);
    });
  }

  List<LyricsShareLine> get _quoted => [
    for (final index in _selected.toList()..sort()) widget.lines[index],
  ];

  Future<void> _share() async {
    if (_sharing || _selected.isEmpty) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final origin = _originOf(_shareButtonKey.currentContext);
    setState(() => _sharing = true);
    try {
      // A selection/background change can still be waiting for paint when
      // Share is tapped. Capture the current card after that frame finishes.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Card is not laid out');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Card could not be encoded');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/spotiflac_lyrics.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: [
            widget.mediaItem.title,
            if ((widget.mediaItem.artist ?? '').trim().isNotEmpty)
              widget.mediaItem.artist!.trim(),
          ].join(' — '),
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.lyricsShareError)));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  static Rect? _originOf(BuildContext? context) {
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = context.tokens;
    final l10n = context.l10n;
    final source = _artSource;
    return Scaffold(
      appBar: AppBar(
        leading: AppIconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const AppIcon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.lyricsShareTitle),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              flex: 6,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.gapSm),
                child: Center(
                  child: AspectRatio(
                    aspectRatio:
                        lyricsShareCardSize.width / lyricsShareCardSize.height,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: FittedBox(
                        child: CoverPaletteBuilder(
                          imageSource: source,
                          builder: (context, _) => RepaintBoundary(
                            key: _cardKey,
                            child: LyricsShareCard(
                              title: widget.mediaItem.title,
                              artist: widget.mediaItem.artist ?? '',
                              artUri: widget.mediaItem.artUri?.toString(),
                              lines: _quoted,
                              background: _background,
                              coverColor: source == null
                                  ? null
                                  : CoverPalette.sourceColor(
                                      source,
                                      Theme.of(context).brightness,
                                    ),
                              placeholder: l10n.lyricsShareSelectHint(
                                lyricsShareMaxLines,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _BackgroundPicker(
              value: _background,
              onChanged: (value) => setState(() => _background = value),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.gapXl,
                tokens.gapSm,
                tokens.gapXl,
                tokens.gapXs,
              ),
              child: Text(
                l10n.lyricsShareSelectHint(lyricsShareMaxLines),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: ListView.builder(
                controller: _list,
                padding: EdgeInsets.symmetric(horizontal: tokens.gapMd),
                itemCount: widget.lines.length,
                itemBuilder: (context, index) => _LineChoice(
                  line: widget.lines[index],
                  selected: _selected.contains(index),
                  onTap: () => _toggle(index),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.gapLg,
                tokens.gapSm,
                tokens.gapLg,
                tokens.gapLg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ExpressiveButton(
                  key: _shareButtonKey,
                  icon: const AppIcon(Icons.ios_share),
                  onPressed: _selected.isEmpty || _sharing ? null : _share,
                  child: Text(l10n.lyricsShareAction),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundPicker extends StatelessWidget {
  const _BackgroundPicker({required this.value, required this.onChanged});

  final LyricsCardBackground value;
  final ValueChanged<LyricsCardBackground> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final labels = {
      LyricsCardBackground.artwork: l10n.lyricsShareBackgroundArtwork,
      LyricsCardBackground.color: l10n.lyricsShareBackgroundColor,
      LyricsCardBackground.dark: l10n.lyricsShareBackgroundDark,
      LyricsCardBackground.light: l10n.lyricsShareBackgroundLight,
    };
    final swatches = {
      LyricsCardBackground.artwork: const LinearGradient(
        colors: [Color(0xFF8E6BBF), Color(0xFF2C5E8C)],
      ),
      LyricsCardBackground.color: LinearGradient(
        colors: [colors.primary, colors.primaryContainer],
      ),
      LyricsCardBackground.dark: const LinearGradient(
        colors: [Color(0xFF2A2A2A), Color(0xFF0E0E0E)],
      ),
      LyricsCardBackground.light: const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFE8E4DC)],
      ),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final option in LyricsCardBackground.values)
          Semantics(
            button: true,
            selected: option == value,
            inMutuallyExclusiveGroup: true,
            label: labels[option],
            child: Tooltip(
              message: labels[option],
              excludeFromSemantics: true,
              child: InkResponse(
                onTap: () => onChanged(option),
                radius: 26,
                child: SizedBox.square(
                  dimension: 52,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: swatches[option],
                        border: Border.all(
                          color: option == value
                              ? colors.primary
                              : colors.outlineVariant,
                          width: option == value ? 3 : 1,
                        ),
                      ),
                      child: option == LyricsCardBackground.artwork
                          ? const AppIcon(
                              Icons.image_outlined,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LineChoice extends StatelessWidget {
  const _LineChoice({
    required this.line,
    required this.selected,
    required this.onTap,
  });

  final LyricsShareLine line;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  AppIcon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 22,
                    color: selected ? colors.primary : colors.outline,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      line.text,
                      style:
                          (line.background
                                  ? theme.textTheme.bodyMedium
                                  : theme.textTheme.bodyLarge)
                              ?.copyWith(
                                color: selected
                                    ? colors.onSurface
                                    : colors.onSurfaceVariant,
                                fontWeight: selected ? FontWeight.w600 : null,
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

/// The shared image: quoted lines over a background derived from the cover.
/// It has a fixed logical size so the export never depends on the device.
class LyricsShareCard extends StatelessWidget {
  const LyricsShareCard({
    super.key,
    required this.title,
    required this.artist,
    required this.artUri,
    required this.lines,
    required this.background,
    this.coverColor,
    this.placeholder,
  });

  final String title;
  final String artist;
  final String? artUri;
  final List<LyricsShareLine> lines;
  final LyricsCardBackground background;

  /// Average cover color for [LyricsCardBackground.color].
  final Color? coverColor;

  /// Shown faintly in the preview while no line is selected.
  final String? placeholder;

  /// Larger type for short quotes, smaller for long ones, so every selection
  /// fills the card comfortably.
  static double fontSizeFor(List<LyricsShareLine> lines) {
    final length = lines.fold<int>(0, (sum, line) => sum + line.text.length);
    if (length <= 40) return 36;
    if (length <= 90) return 31;
    if (length <= 160) return 26;
    return 22;
  }

  @override
  Widget build(BuildContext context) {
    final light = background == LyricsCardBackground.light;
    final foreground = light ? const Color(0xFF111111) : Colors.white;
    final secondary = foreground.withValues(alpha: 0.7);
    final fontSize = fontSizeFor(lines);
    final scheme = Theme.of(context).colorScheme;
    return MediaQuery.withNoTextScaling(
      child: SizedBox.fromSize(
        size: lyricsShareCardSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _background(scheme),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: foreground.withValues(alpha: light ? 0.06 : 0.12),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox.square(
                                dimension: 44,
                                child: PlayerArtwork(
                                  artUri: artUri,
                                  colorScheme: scheme,
                                  iconSize: 22,
                                  cacheWidth: 132,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: foreground,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (artist.isNotEmpty)
                                    Text(
                                      artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: secondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 380),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: lyricsShareCardSize.width - 100,
                              child: lines.isEmpty
                                  ? Text(
                                      placeholder ?? '',
                                      style: TextStyle(
                                        color: foreground.withValues(
                                          alpha: 0.4,
                                        ),
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final line in lines)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            child: Text(
                                              line.text,
                                              style: TextStyle(
                                                color: line.background
                                                    ? secondary
                                                    : foreground,
                                                fontSize: line.background
                                                    ? fontSize * 0.72
                                                    : fontSize,
                                                height: 1.18,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.3,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Center(
                    child: Text(
                      'SpotiFLAC',
                      style: TextStyle(
                        color: secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _background(ColorScheme scheme) {
    switch (background) {
      case LyricsCardBackground.artwork:
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF1B1B1F)),
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 36,
                sigmaY: 36,
                tileMode: TileMode.mirror,
              ),
              child: Transform.scale(
                scale: 1.3,
                child: PlayerArtwork(
                  artUri: artUri,
                  colorScheme: scheme,
                  cacheWidth: 360,
                ),
              ),
            ),
            const ColoredBox(color: Color(0x47000000)),
          ],
        );
      case LyricsCardBackground.color:
        final hsl = HSLColor.fromColor(coverColor ?? scheme.primary);
        final base = hsl.withSaturation(hsl.saturation.clamp(0.25, 0.6));
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                base.withLightness(0.44).toColor(),
                base.withLightness(0.2).toColor(),
              ],
            ),
          ),
        );
      case LyricsCardBackground.dark:
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF26262B), Color(0xFF0B0B0D)],
            ),
          ),
        );
      case LyricsCardBackground.light:
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFEDE9E1)],
            ),
          ),
        );
    }
  }
}

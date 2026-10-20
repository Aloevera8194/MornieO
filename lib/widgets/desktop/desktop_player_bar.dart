import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/theme/app_tokens.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/utils/string_utils.dart';
import 'package:mornye/widgets/app_icon.dart';
import 'package:mornye/widgets/app_icon_button.dart';
import 'package:mornye/widgets/app_loading_indicator.dart';
import 'package:mornye/widgets/audio_quality_badges.dart';
import 'package:mornye/widgets/desktop/desktop_commands.dart';
import 'package:mornye/widgets/desktop/desktop_downloads_button.dart';
import 'package:mornye/widgets/desktop/desktop_inspector.dart';
import 'package:mornye/widgets/mornye_playback_button.dart';
import 'package:mornye/widgets/player_artwork.dart';
import 'package:mornye/widgets/player_volume_control.dart';
import 'package:mornye/widgets/playback_seek_slider.dart';

/// The persistent desktop player along the bottom of the window. It replaces
/// the mobile mini player: no swipe gestures, with transport, seek, volume,
/// lyrics and Up Next always in reach. Clicking the artwork or title shows
/// Now Playing in the content pane; lyrics and Up Next toggle the trailing
/// inspector.
///
/// Material draws an 80dp bar on a `surfaceContainer` fill. Mornye draws a
/// 72pt bar laid out like the macOS Music toolbar: transport, a center
/// "LCD" with the track and its progress, then lyrics, Up Next, downloads
/// and volume.
class DesktopPlayerBar extends ConsumerWidget {
  const DesktopPlayerBar({super.key});

  static const double materialHeight = 80;
  static const double mornyeHeight = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    return context.isMornye
        ? _MornyePlayerBar(mediaItem: mediaItem)
        : _MaterialPlayerBar(mediaItem: mediaItem);
  }
}

/// Shows Now Playing in the content pane, or returns to the content when it
/// is already showing.
void _toggleNowPlaying() =>
    desktopNowPlayingOpen.value = !desktopNowPlayingOpen.value;

class _MaterialPlayerBar extends StatelessWidget {
  const _MaterialPlayerBar({required this.mediaItem});

  final MediaItem? mediaItem;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final loaded = mediaItem != null;
    return Material(
      color: colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: DesktopPlayerBar.materialHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _TrackSummary(mediaItem: mediaItem),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Transport(enabled: loaded),
                      SizedBox(
                        height: 24,
                        child: _SeekRow(mediaItem: mediaItem),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: _TrailingControls(enabled: loaded)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MornyePlayerBar extends StatelessWidget {
  const _MornyePlayerBar({required this.mediaItem});

  final MediaItem? mediaItem;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final loaded = mediaItem != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: MornyeTheme.metadataDividerColor(context)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: DesktopPlayerBar.mornyeHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _Transport(enabled: loaded),
                  ),
                ),
                // The trailing group also holds downloads, so it keeps room
                // for the volume slider in narrow windows.
                Expanded(
                  flex: 4,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: _MornyeLcd(mediaItem: mediaItem),
                    ),
                  ),
                ),
                Expanded(flex: 4, child: _TrailingControls(enabled: loaded)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Artwork, title and artist for the Material bar. The whole group opens
/// Now Playing, like tapping the mobile mini player.
class _TrackSummary extends StatelessWidget {
  const _TrackSummary({required this.mediaItem});

  final MediaItem? mediaItem;

  @override
  Widget build(BuildContext context) {
    final item = mediaItem;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Artwork(mediaItem: item, size: 56, radius: 12),
        const SizedBox(width: 12),
        Flexible(
          child: item == null
              ? Text(
                  context.l10n.desktopPlayerIdle,
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : _TitleAndArtist(mediaItem: item),
        ),
        const SizedBox(width: 8),
      ],
    );
    if (item == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _toggleNowPlaying,
      child: Padding(padding: const EdgeInsets.all(4), child: content),
    );
  }
}

class _TitleAndArtist extends StatelessWidget {
  const _TitleAndArtist({
    required this.mediaItem,
    this.textAlign = TextAlign.start,
  });

  final MediaItem mediaItem;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final centered = textAlign == TextAlign.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        ExplicitTrackTitle(
          title: mediaItem.title,
          explicit: parseExplicitFlag(mediaItem.extras?['explicit']) == true,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          mediaItem.artist ?? '',
          textAlign: textAlign,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.mediaItem,
    required this.size,
    required this.radius,
    this.borderRadius,
  });

  final MediaItem? mediaItem;
  final double size;
  final double radius;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    // Now Playing opens in the content pane rather than as a route, so the
    // artwork has no route transition to fly in.
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: PlayerArtwork(
          artUri: mediaItem?.artUri?.toString(),
          colorScheme: Theme.of(context).colorScheme,
          cacheWidth: (size * 2).round(),
          iconSize: size * 0.4,
        ),
      ),
    );
  }
}

/// Previous, play/pause and next. Material keeps the mini player's filled
/// play button, round while paused and square while playing.
class _Transport extends ConsumerWidget {
  const _Transport({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(musicPlayerControllerProvider);
    final isPlaying = ref.watch(playbackPlayingProvider);
    final isLoading = ref.watch(playbackLoadingProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final playTooltip = desktopTooltip(
      context,
      isPlaying ? l10n.actionPause : l10n.tooltipPlay,
      DesktopCommand.playPause,
    );
    final previousTooltip = desktopTooltip(
      context,
      l10n.nowPlayingPreviousTrack,
      DesktopCommand.previous,
    );
    final nextTooltip = desktopTooltip(
      context,
      l10n.nowPlayingNextTrack,
      DesktopCommand.next,
    );
    final onPlayPause = enabled && !isLoading
        ? () => controller.togglePlayPause(isPlaying)
        : null;

    if (context.isMornye) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MornyePlaybackButton(
            icon: CupertinoIcons.backward_fill,
            tooltip: previousTooltip,
            color: colorScheme.onSurface,
            iconSize: 22,
            padding: const EdgeInsets.all(10),
            onPressed: enabled ? controller.previous : null,
          ),
          MornyePlaybackButton(
            icon: isPlaying
                ? CupertinoIcons.pause_fill
                : CupertinoIcons.play_fill,
            tooltip: playTooltip,
            color: colorScheme.onSurface,
            iconSize: 30,
            padding: const EdgeInsets.all(7),
            loading: isLoading,
            onPressed: onPlayPause,
          ),
          MornyePlaybackButton(
            icon: CupertinoIcons.forward_fill,
            tooltip: nextTooltip,
            color: colorScheme.onSurface,
            iconSize: 22,
            padding: const EdgeInsets.all(10),
            onPressed: enabled ? controller.next : null,
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          tooltip: previousTooltip,
          icon: const AppIcon(Icons.skip_previous),
          onPressed: enabled ? controller.previous : null,
        ),
        const SizedBox(width: 8),
        AppIconButton.filled(
          tooltip: playTooltip,
          isSelected: isPlaying,
          style: IconButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
          icon: isLoading
              ? AppLoadingIndicator(size: 20, color: colorScheme.onPrimary)
              : const AppIcon(Icons.play_arrow),
          selectedIcon: isLoading
              ? AppLoadingIndicator(size: 20, color: colorScheme.onPrimary)
              : const AppIcon(Icons.pause),
          onPressed: onPlayPause,
        ),
        const SizedBox(width: 8),
        AppIconButton(
          tooltip: nextTooltip,
          icon: const AppIcon(Icons.skip_next),
          onPressed: enabled ? controller.next : null,
        ),
      ],
    );
  }
}

/// Elapsed time, seek track and duration. Watches the playback position on
/// its own so the rest of the bar does not rebuild every tick.
class _SeekRow extends ConsumerWidget {
  const _SeekRow({required this.mediaItem});

  final MediaItem? mediaItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = mediaItem;
    final colorScheme = Theme.of(context).colorScheme;
    final mornye = context.isMornye;
    final duration = item?.duration ?? Duration.zero;
    final position = item == null
        ? Duration.zero
        : ref.watch(playbackPositionProvider);
    final playing =
        ref.watch(playbackPlayingProvider) &&
        !ref.watch(playbackLoadingProvider);
    final timeStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final elapsed = position.inSeconds.clamp(0, duration.inSeconds);
    return Row(
      children: [
        Text(formatClock(elapsed), style: timeStyle),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: mornye
                  ? colorScheme.onSurface.withValues(alpha: 0.6)
                  : colorScheme.primary,
              inactiveTrackColor: mornye
                  ? colorScheme.onSurface.withValues(alpha: 0.12)
                  : colorScheme.secondaryContainer,
              thumbColor: colorScheme.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: PlaybackSeekSlider(
              key: ValueKey(item?.id),
              position: position,
              duration: duration,
              playing: playing,
              onSeek: ref.read(musicPlayerControllerProvider).seek,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          mornye
              ? '-${formatClock(duration.inSeconds - elapsed)}'
              : formatClock(duration.inSeconds),
          style: timeStyle,
        ),
      ],
    );
  }
}

/// The Mornye center display: artwork, title and artist, with progress
/// along its bottom edge. Clicking the artwork or text opens Now Playing.
class _MornyeLcd extends StatelessWidget {
  const _MornyeLcd({required this.mediaItem});

  static const double _height = 56;

  final MediaItem? mediaItem;

  @override
  Widget build(BuildContext context) {
    final item = mediaItem;
    final textTheme = Theme.of(context).textTheme;
    final radius = context.tokens.radiusCover;
    final details = item == null
        ? Center(
            child: Text(
              context.l10n.desktopPlayerIdle,
              style: textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleNowPlaying,
                  child: _TitleAndArtist(
                    mediaItem: item,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              SizedBox(height: 14, child: _SeekRow(mediaItem: item)),
            ],
          );
    return Container(
      height: _height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: MornyeTheme.controlFill(context),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        children: [
          MouseRegion(
            cursor: item == null ? MouseCursor.defer : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: item == null ? null : _toggleNowPlaying,
              child: _Artwork(
                mediaItem: item,
                size: _height,
                radius: 0,
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: details,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lyrics and Up Next, which toggle the trailing inspector, then downloads
/// (Mornye, whose bar is its toolbar) and the volume slider.
class _TrailingControls extends StatelessWidget {
  const _TrailingControls({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final mornye = context.isMornye;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ValueListenableBuilder<DesktopInspectorPanel?>(
          valueListenable: desktopInspectorPanel,
          builder: (context, panel, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InspectorToggle(
                key: const ValueKey('desktop-player-lyrics'),
                panel: DesktopInspectorPanel.lyrics,
                selected: panel == DesktopInspectorPanel.lyrics,
                enabled: enabled,
                tooltip: desktopTooltip(
                  context,
                  l10n.nowPlayingTabLyrics,
                  DesktopCommand.lyrics,
                ),
                icon: mornye
                    ? CupertinoIcons.quote_bubble
                    : Icons.lyrics_outlined,
              ),
              _InspectorToggle(
                key: const ValueKey('desktop-player-up-next'),
                panel: DesktopInspectorPanel.upNext,
                selected: panel == DesktopInspectorPanel.upNext,
                enabled: enabled,
                tooltip: desktopTooltip(
                  context,
                  l10n.nowPlayingUpNext,
                  DesktopCommand.upNext,
                ),
                icon: mornye ? CupertinoIcons.list_bullet : Icons.queue_music,
              ),
            ],
          ),
        ),
        if (mornye) const DesktopDownloadsButton(),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: PlayerVolumeControl(foreground: colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}

/// A toggle for one inspector panel. Mornye marks the open panel with a
/// fill as well as the accent color, so the state differs by more than
/// color; Material uses the selected standard icon button.
class _InspectorToggle extends StatelessWidget {
  const _InspectorToggle({
    super.key,
    required this.panel,
    required this.selected,
    required this.enabled,
    required this.tooltip,
    required this.icon,
  });

  final DesktopInspectorPanel panel;
  final bool selected;
  final bool enabled;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final mornye = context.isMornye;
    final colorScheme = Theme.of(context).colorScheme;
    return AppIconButton(
      tooltip: tooltip,
      isSelected: selected,
      color: mornye
          ? (selected ? colorScheme.primary : colorScheme.onSurface)
          : null,
      style: mornye && selected
          ? IconButton.styleFrom(
              backgroundColor: MornyeTheme.controlFill(context),
            )
          : null,
      icon: AppIcon(icon),
      // An open panel can always close, even after playback stops.
      onPressed: enabled || selected
          ? () => toggleDesktopInspector(panel)
          : null,
    );
  }
}

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// The rail's own item, used for Settings at the bottom of the rail so it
// keeps the same pill, label and motion as the destinations above it.
import 'package:material_3_expressive/components/navigation_rail/components/m3e_rail_item.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/providers/library_collections_provider.dart';
import 'package:mornye/providers/user_profile_provider.dart';
import 'package:mornye/screens/now_playing_screen.dart';
import 'package:mornye/services/shell_navigation_service.dart';
import 'package:mornye/services/user_profile_store.dart';
import 'package:mornye/theme/app_tokens.dart';
import 'package:mornye/theme/material_expressive.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/app_icon.dart';
import 'package:mornye/widgets/app_icon_button.dart';
import 'package:mornye/widgets/desktop/desktop_commands.dart';
import 'package:mornye/widgets/desktop/desktop_inspector.dart';
import 'package:mornye/widgets/desktop/desktop_player_bar.dart';
import 'package:mornye/widgets/desktop/desktop_window.dart';
import 'package:mornye/widgets/profile_avatar.dart';

/// Window width at which the Material rail shows labels beside its icons.
const double desktopExpandedRailBreakpoint = 1200;

/// Expanded Material rail width.
const double desktopSidebarWidth = 220;

/// Window width below which the Mornye sidebar hides itself, as Music does
/// in narrow windows. The sidebar button shows it again.
const double desktopSidebarAutoHideWidth = 900;

/// Space between the expanded Material rail's destinations, so adjacent
/// 56dp indicators and hover layers never touch.
const double desktopRailItemGap = 8;

/// A Library page or playlist in the Mornye sidebar.
class DesktopSidebarLink {
  const DesktopSidebarLink({
    required this.id,
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });

  /// Identifies the link to [DesktopShellLayout.onOpenLibraryLink] and
  /// [desktopSidebarLink]. Playlists use [playlistId].
  final String id;
  final IconData icon;
  final String label;
  final int badgeCount;

  /// The link id of the user playlist [id].
  static String playlistId(String id) => 'playlist:$id';

  /// The link that opens the list of every playlist.
  static const allPlaylistsId = 'playlists';
}

/// The Library link open in the Mornye sidebar, or null for the Library
/// root, which the first Library link stands for.
final desktopSidebarLink = ValueNotifier<String?>(null);

/// The user's playlists listed in the Mornye sidebar.
final desktopSidebarPlaylistsProvider = Provider<List<UserPlaylistCollection>>(
  (ref) => ref.watch(libraryCollectionsProvider.select((s) => s.playlists)),
);

/// The profile in the Mornye sidebar's account row, once it has loaded.
final desktopSidebarProfileProvider = Provider<UserProfile?>(
  (ref) => ref.watch(userProfileProvider).value,
);

/// A top-level desktop destination.
class DesktopDestination {
  const DesktopDestination({
    required this.tab,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final ShellTab tab;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;
}

/// The desktop shell: navigation on the leading edge, the content pane and
/// the trailing inspector.
///
/// Material uses [DesktopNavigationRail] and the player bar docked across the bottom. Mornye follows Music: the
/// [DesktopSidebar] runs the full window height, and the player floats as a
/// glass capsule at the bottom of the content pane, which pads its pages so
/// their last rows scroll clear of it.
///
/// On macOS the window content reaches under a transparent title bar
/// ([desktopTitleBarInContent]): the traffic lights sit over the top of the
/// navigation, and the top [desktopTitleBarHeight] of the content pane drags
/// the window.
///
/// Now Playing replaces the content pane while [desktopNowPlayingOpen] is
/// set. Lyrics and Up Next ([desktopInspectorPanel]) sit beside the content
/// from [desktopInspectorBesideBreakpoint] and float over it below that.
class DesktopShellLayout extends StatelessWidget {
  const DesktopShellLayout({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
    required this.body,
    this.libraryLinks = const [],
    this.onOpenLibraryLink,
    this.onOpenProfile,
    this.playerBar = const DesktopPlayerBar(),
    this.nowPlaying = const DesktopNowPlayingPane(),
  });

  /// Destinations in [desktopDestinationTabs] order; Cmd/Ctrl+1..5 follow it.
  final List<DesktopDestination> destinations;
  final ShellTab? selected;
  final ValueChanged<ShellTab> onSelected;
  final Widget body;

  /// Mornye: the Library pages listed under the sidebar's Library heading.
  /// The first stands for the Library destination itself.
  final List<DesktopSidebarLink> libraryLinks;

  /// Mornye: opens a Library link or a playlist from the sidebar.
  final ValueChanged<String>? onOpenLibraryLink;

  /// Mornye: opens the profile from the sidebar's account row.
  final VoidCallback? onOpenProfile;
  final Widget playerBar;
  final Widget nowPlaying;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (context.isMornye) {
      return _DesktopSidebarAutoHide(
        windowWidth: width,
        child: ValueListenableBuilder<bool>(
          valueListenable: desktopSidebarCollapsed,
          // The page background shows around the inset sidebar panel.
          builder: (context, hidden, _) => ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DesktopSidebar(
                  destinations: destinations,
                  selected: selected,
                  onSelected: onSelected,
                  libraryLinks: libraryLinks,
                  onOpenLibraryLink: onOpenLibraryLink,
                  onOpenProfile: onOpenProfile,
                  hidden: hidden,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Without the sidebar, the window controls and the
                      // button that shows it again get a row of their own.
                      if (hidden) const _DesktopContentTitleBar(),
                      Expanded(
                        key: const ValueKey('desktop-content'),
                        child: _DesktopContentArea(
                          overlayInspector: desktopInspectorOverlays(width),
                          body: body,
                          nowPlaying: nowPlaying,
                          floatingPlayer: playerBar,
                          titleBarDrag: !hidden,
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
    final railBackground = Theme.of(context).colorScheme.surfaceContainer;
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: railBackground,
                child: Column(
                  children: [
                    // The traffic lights sit above the rail.
                    if (desktopTitleBarInContent)
                      const SizedBox(
                        height: desktopTitleBarHeight,
                        width: desktopWindowControlsWidth,
                        child: DesktopWindowDragArea(zoomOnDoubleClick: true),
                      ),
                    Expanded(
                      child: DesktopNavigationRail(
                        destinations: destinations,
                        selected: selected,
                        onSelected: onSelected,
                        extended: width >= desktopExpandedRailBreakpoint,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _DesktopContentArea(
                  overlayInspector: desktopInspectorOverlays(width),
                  body: body,
                  nowPlaying: nowPlaying,
                  titleBarDrag: true,
                ),
              ),
            ],
          ),
        ),
        playerBar,
      ],
    );
  }
}

/// Hides the Mornye sidebar when the window narrows past
/// [desktopSidebarAutoHideWidth] and shows it again when it widens back.
/// The sidebar button and shortcut still toggle it in between.
class _DesktopSidebarAutoHide extends StatefulWidget {
  const _DesktopSidebarAutoHide({
    required this.windowWidth,
    required this.child,
  });

  final double windowWidth;
  final Widget child;

  @override
  State<_DesktopSidebarAutoHide> createState() =>
      _DesktopSidebarAutoHideState();
}

class _DesktopSidebarAutoHideState extends State<_DesktopSidebarAutoHide> {
  bool? _narrow;

  void _update() {
    final narrow = widget.windowWidth < desktopSidebarAutoHideWidth;
    final previous = _narrow;
    _narrow = narrow;
    // A wide first frame keeps the remembered choice; crossing the width
    // either way follows the window.
    if (previous == narrow || (previous == null && !narrow)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _narrow == narrow) desktopSidebarCollapsed.value = narrow;
    });
  }

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(_DesktopSidebarAutoHide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowWidth != widget.windowWidth) _update();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The row above the content pane while the Mornye sidebar is hidden: room
/// for the macOS window controls, then the button that shows the sidebar.
class _DesktopContentTitleBar extends StatelessWidget {
  const _DesktopContentTitleBar();

  @override
  Widget build(BuildContext context) {
    final titleBar = desktopTitleBarInContent;
    return SizedBox(
      height: titleBar ? desktopTitleBarHeight : _SidebarHeader.height,
      child: Row(
        children: [
          SizedBox(width: titleBar ? desktopWindowControlsWidth : 8),
          const _SidebarToggle(hidden: true),
          const Expanded(
            child: DesktopWindowDragArea(
              zoomOnDoubleClick: true,
              child: SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gives [child] the size of the space it lays out in, so width-based layout
/// (centered columns, grids) measures the pane rather than the whole window.
/// [bottomInset] becomes the bottom padding, which pages add after their
/// last row ([NavBarInset]) so it scrolls clear of the floating player.
class _PaneMediaQuery extends StatelessWidget {
  const _PaneMediaQuery({required this.child, this.bottomInset = 0});

  final Widget child;
  final double bottomInset;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mediaQuery = MediaQuery.of(context);
      var data = mediaQuery
          .copyWith(size: Size(constraints.maxWidth, constraints.maxHeight))
          .removePadding(removeLeft: true, removeBottom: true);
      if (bottomInset > 0) {
        data = data.copyWith(
          padding: data.padding.copyWith(bottom: bottomInset),
          viewPadding: data.viewPadding.copyWith(bottom: bottomInset),
        );
      }
      return MediaQuery(data: data, child: child);
    },
  );
}

/// The content pane, Now Playing over it while open, the trailing inspector
/// and, in Mornye, the floating player. Pages bring their own search fields
/// (Home, Library), so there is no shell search bar above them.
class _DesktopContentArea extends StatelessWidget {
  const _DesktopContentArea({
    required this.overlayInspector,
    required this.body,
    required this.nowPlaying,
    this.floatingPlayer,
    this.titleBarDrag = false,
  });

  final bool overlayInspector;
  final Widget body;
  final Widget nowPlaying;

  /// The Mornye player capsule, floating over the bottom of the pane.
  final Widget? floatingPlayer;

  /// Whether the top of the pane is the window's title bar row, where a
  /// drag moves the window.
  final bool titleBarDrag;

  @override
  Widget build(BuildContext context) {
    final player = floatingPlayer;
    final playerInset = player == null ? 0.0 : DesktopPlayerBar.floatingInset;
    return ValueListenableBuilder<bool>(
      valueListenable: desktopNowPlayingOpen,
      builder: (context, nowPlayingOpen, _) =>
          ValueListenableBuilder<DesktopInspectorPanel?>(
            valueListenable: desktopInspectorPanel,
            builder: (context, panel, _) {
              final content = Stack(
                fit: StackFit.expand,
                children: [
                  // The destinations keep their state, but stop painting and
                  // ticking while Now Playing covers them.
                  Visibility(
                    visible: !nowPlayingOpen,
                    maintainState: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // A semantics container keeps the tab navigators'
                        // modal barriers from hiding the sidebar.
                        Expanded(
                          key: const ValueKey('desktop-pages'),
                          child: Semantics(
                            container: true,
                            child: _PaneMediaQuery(
                              bottomInset: playerInset,
                              child: body,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (nowPlayingOpen)
                    _PaneMediaQuery(
                      bottomInset: playerInset,
                      child: nowPlaying,
                    ),
                  if (player != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: DesktopPlayerBar.floatingMargin,
                      child: LayoutBuilder(
                        builder: (context, constraints) => Center(
                          child: SizedBox(
                            width: DesktopPlayerBar.floatingWidth(
                              constraints.maxWidth,
                            ),
                            child: player,
                          ),
                        ),
                      ),
                    ),
                  // A narrow window's inspector floats above the player.
                  if (panel != null && overlayInspector)
                    PositionedDirectional(
                      top: 0,
                      bottom: playerInset,
                      end: 0,
                      width: desktopInspectorWidth,
                      child: DesktopInspector(panel: panel, overlay: true),
                    ),
                ],
              );
              // One structure for every state, so opening the inspector never
              // remounts the destinations.
              final pane = Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: content),
                  if (panel != null && !overlayInspector)
                    DesktopInspector(panel: panel),
                ],
              );
              if (!titleBarDrag || !desktopTitleBarInContent) return pane;
              // Pages keep their clicks in the title bar row; a drag that
              // starts on it moves the window.
              return Stack(
                fit: StackFit.expand,
                children: [
                  pane,
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: desktopTitleBarHeight,
                    child: DesktopWindowDragArea(),
                  ),
                ],
              );
            },
          ),
    );
  }
}

/// Now Playing filling the content pane. Escape, Back or its minimize button
/// return to the content.
class DesktopNowPlayingPane extends StatelessWidget {
  const DesktopNowPlayingPane({super.key});

  @override
  Widget build(BuildContext context) => const HeroMode(
    // The pane is no route: there is nothing for a Hero to fly between.
    enabled: false,
    child: NowPlayingScreen(embedded: true),
  );
}

int _positionOf(List<DesktopDestination> destinations, ShellTab tab) =>
    destinations.indexWhere((destination) => destination.tab == tab) + 1;

/// Material 3 Expressive navigation rail for desktop windows: collapsed
/// below [desktopExpandedRailBreakpoint], expanded to [desktopSidebarWidth]
/// above it, with Settings anchored at the bottom.
class DesktopNavigationRail extends StatelessWidget {
  const DesktopNavigationRail({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
    required this.extended,
  });

  final List<DesktopDestination> destinations;
  final ShellTab? selected;
  final ValueChanged<ShellTab> onSelected;
  final bool extended;

  M3ENavigationRailDestination _railDestination(
    DesktopDestination destination,
  ) => M3ENavigationRailDestination(
    icon: AppIcon(destination.icon),
    selectedIcon: AppIcon(destination.selectedIcon),
    label: destination.label,
    badgeCount: destination.badgeCount > 0 ? destination.badgeCount : null,
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = colorScheme.surfaceContainer;
    if (!materialExpressiveEnabled(context)) {
      // Reduced motion keeps Flutter's rail; Settings stays last.
      final index = destinations.indexWhere((d) => d.tab == selected);
      return NavigationRail(
        extended: extended,
        minExtendedWidth: desktopSidebarWidth,
        labelType: extended
            ? NavigationRailLabelType.none
            : NavigationRailLabelType.all,
        backgroundColor: background,
        selectedIndex: index < 0 ? null : index,
        onDestinationSelected: (index) => onSelected(destinations[index].tab),
        destinations: [
          for (final destination in destinations)
            NavigationRailDestination(
              icon: Badge(
                isLabelVisible: destination.badgeCount > 0,
                label: Text('${destination.badgeCount}'),
                child: AppIcon(destination.icon),
              ),
              selectedIcon: AppIcon(destination.selectedIcon),
              label: Text(destination.label),
            ),
        ],
      );
    }
    final primary = [
      for (final destination in destinations)
        if (destination.tab != ShellTab.settings) destination,
    ];
    final settings = destinations
        .where((destination) => destination.tab == ShellTab.settings)
        .firstOrNull;
    return MaterialExpressiveScope(
      child: _RailItemSpacing(
        child: M3ENavigationRail(
          type: extended
              ? M3ENavigationRailType.alwaysExpand
              : M3ENavigationRailType.alwaysCollapse,
          expandedWidth: desktopSidebarWidth,
          background: background,
          selectedIndex: primary.indexWhere((d) => d.tab == selected),
          onDestinationSelected: (index) => onSelected(primary[index].tab),
          sections: [
            M3ENavigationRailSection(
              destinations: [
                for (final destination in primary)
                  _railDestination(destination),
              ],
            ),
          ],
          trailing: settings == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  // The rail insets its trailing slot by 16dp per side; undo
                  // that so Settings lines up with the destinations above.
                  child: LayoutBuilder(
                    builder: (context, constraints) => OverflowBox(
                      fit: OverflowBoxFit.deferToChild,
                      minWidth: constraints.maxWidth + 32,
                      maxWidth: constraints.maxWidth + 32,
                      child: M3ERailItem(
                        destination: _railDestination(settings),
                        selected: selected == ShellTab.settings,
                        onTap: () => onSelected(ShellTab.settings),
                        expanded: extended,
                        labelBehavior:
                            M3ENavigationRailLabelBehavior.alwaysShow,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Separates the expanded rail's destinations by [desktopRailItemGap]. The
/// package stacks its 56dp items with no gap, so the selected indicator and
/// a hovered item's state layer (the same pill) would touch. Collapsed items
/// keep the package's own gap below their label.
class _RailItemSpacing extends StatelessWidget {
  const _RailItemSpacing({required this.child});

  final Widget child;

  static final _themes = Expando<M3EThemeData>();

  @override
  Widget build(BuildContext context) {
    final base = M3ETheme.of(context);
    final spaced = _themes[base] ??= base.copyWith(
      navigationRailTheme: base.navigationRailTheme.copyWith(
        expandedItemGap: desktopRailItemGap,
        // The whole row is the click target, so the pill spans it too, as
        // in a navigation drawer; a pill hugging the label would light up
        // from clicks beside it.
        indicatorFillsWidth: true,
      ),
    );
    return M3ETheme(data: spaced, child: child);
  }
}

/// The Mornye source-list sidebar, laid out like Music's: a rounded panel
/// inset from the window edges, with the window controls and the sidebar
/// button on top, then Search and the top-level destinations, the Library
/// pages and the user's playlists under section headings, and the account
/// row pinned at the bottom with Settings beside it. The panel takes a tint
/// from the page's artwork color when the page sets one. The sidebar
/// button, View > Hide Sidebar and Control-Command-S hide it completely.
///
/// Without [onOpenLibraryLink] it lists the destinations alone, Library
/// included.
class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
    this.libraryLinks = const [],
    this.onOpenLibraryLink,
    this.onOpenProfile,
    this.hidden = false,
  });

  /// Width of the panel.
  static const double width = 210;

  /// Space between the panel and the window edges and content pane.
  static const double margin = 8;

  /// Width the sidebar takes from the window while shown.
  static const double footprint = width + 2 * margin;

  /// Corner radius of the panel.
  static const double radius = 12;

  final List<DesktopDestination> destinations;
  final ShellTab? selected;
  final ValueChanged<ShellTab> onSelected;

  /// The Library pages under the Library heading. The first stands for the
  /// Library destination and takes its place and shortcut.
  final List<DesktopSidebarLink> libraryLinks;

  /// Opens a Library link, All Playlists or a playlist by its link id.
  final ValueChanged<String>? onOpenLibraryLink;

  /// Opens the profile from the account row. Without it the row opens
  /// Settings.
  final VoidCallback? onOpenProfile;

  /// Hides the sidebar: it slides to no width and leaves focus order.
  final bool hidden;

  /// The panel fill: a step off the page background, tinted by the page's
  /// artwork color ([ShellNavigationService.chromeSurface]) when it has one.
  static Color panelColor(BuildContext context, Color? tint) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final base = dark ? const Color(0xff1e1e20) : const Color(0xffefeff3);
    if (tint == null) return base;
    return Color.lerp(base, tint, dark ? 0.32 : 0.18)!;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : context.tokens.motionMedium;
    final openLink = onOpenLibraryLink;
    final links = openLink == null
        ? const <DesktopSidebarLink>[]
        : libraryLinks;
    final playlists = openLink == null
        ? const <UserPlaylistCollection>[]
        : ref.watch(desktopSidebarPlaylistsProvider);
    Widget destinationRow(DesktopDestination destination) {
      final search = destination.tab == ShellTab.search;
      return _SidebarRow(
        // Search focuses its field, as Command-F does.
        key: search ? const ValueKey('desktop-sidebar-search') : null,
        icon: destination.icon,
        label: destination.label,
        badgeCount: destination.badgeCount,
        selected: destination.tab == selected,
        tooltip: search
            ? desktopTooltip(context, destination.label, DesktopCommand.search)
            : desktopDestinationTooltip(
                context,
                destination.label,
                _positionOf(destinations, destination.tab),
              ),
        onTap: search
            ? ShellNavigationService.requestSearch
            : () => onSelected(destination.tab),
      );
    }

    // Search leads the list, as in Music.
    final topLevel = [
      for (final tab in [ShellTab.search, ShellTab.home, ShellTab.repository])
        ...destinations.where((destination) => destination.tab == tab),
      if (links.isEmpty)
        ...destinations.where(
          (destination) => destination.tab == ShellTab.library,
        ),
    ];
    final libraryPosition = _positionOf(destinations, ShellTab.library);
    final settings = destinations
        .where((destination) => destination.tab == ShellTab.settings)
        .firstOrNull;
    final list = ValueListenableBuilder<String?>(
      valueListenable: desktopSidebarLink,
      builder: (context, openId, _) {
        final current = selected == ShellTab.library
            ? openId ?? links.firstOrNull?.id
            : null;
        Widget linkRow(DesktopSidebarLink link, {String? tooltip}) =>
            _SidebarRow(
              icon: link.icon,
              label: link.label,
              badgeCount: link.badgeCount,
              selected: link.id == current,
              tooltip: tooltip ?? link.label,
              onTap: () => openLink!(link.id),
            );
        return ListView(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          children: [
            for (final destination in topLevel) destinationRow(destination),
            if (links.isNotEmpty) ...[
              _SidebarSectionHeader(l10n.navLibrary),
              for (final (index, link) in links.indexed)
                linkRow(
                  link,
                  tooltip: index == 0 && libraryPosition > 0
                      ? desktopDestinationTooltip(
                          context,
                          link.label,
                          libraryPosition,
                        )
                      : null,
                ),
            ],
            if (openLink != null) ...[
              _SidebarSectionHeader(l10n.searchPlaylists),
              linkRow(
                DesktopSidebarLink(
                  id: DesktopSidebarLink.allPlaylistsId,
                  icon: CupertinoIcons.square_grid_2x2,
                  label: l10n.desktopAllPlaylists,
                ),
              ),
              for (final playlist in playlists)
                linkRow(
                  DesktopSidebarLink(
                    id: DesktopSidebarLink.playlistId(playlist.id),
                    icon: CupertinoIcons.music_note_list,
                    label: playlist.name,
                  ),
                ),
            ],
          ],
        );
      },
    );
    final panel = ValueListenableBuilder<Color?>(
      valueListenable: ShellNavigationService.chromeSurface,
      builder: (context, tint, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: panelColor(context, tint),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SidebarHeader(),
              Expanded(child: list),
              if (settings != null)
                _SidebarAccountRow(
                  settings: settings,
                  settingsSelected: selected == ShellTab.settings,
                  settingsTooltip: desktopDestinationTooltip(
                    context,
                    settings.label,
                    _positionOf(destinations, ShellTab.settings),
                  ),
                  onOpenSettings: () => onSelected(ShellTab.settings),
                  onOpenProfile:
                      onOpenProfile ?? () => onSelected(ShellTab.settings),
                ),
            ],
          ),
        ),
      ),
    );
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeInOutCubic,
      width: hidden ? 0 : footprint,
      child: ClipRect(
        child: ExcludeFocus(
          excluding: hidden,
          child: ExcludeSemantics(
            excluding: hidden,
            child: IgnorePointer(
              ignoring: hidden,
              child: OverflowBox(
                alignment: AlignmentDirectional.topStart,
                minWidth: footprint,
                maxWidth: footprint,
                child: Padding(
                  padding: const EdgeInsets.all(margin),
                  child: panel,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The account row pinned under the sidebar's list, as in Music: the
/// profile picture and name, which open the profile, then Settings.
class _SidebarAccountRow extends ConsumerWidget {
  const _SidebarAccountRow({
    required this.settings,
    required this.settingsSelected,
    required this.settingsTooltip,
    required this.onOpenSettings,
    required this.onOpenProfile,
  });

  final DesktopDestination settings;
  final bool settingsSelected;
  final String settingsTooltip;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final profile = ref.watch(desktopSidebarProfileProvider);
    final name = profile?.name.trim() ?? '';
    final label = name.isEmpty ? context.l10n.profileSetUp : name;
    final radius = BorderRadius.circular(_SidebarRow.radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: MornyeTheme.metadataDividerColor(context),
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: label,
                excludeSemantics: true,
                child: InkWell(
                  key: const ValueKey('desktop-sidebar-account'),
                  borderRadius: radius,
                  hoverColor: _SidebarRow.hoverFill(context),
                  onTap: onOpenProfile,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        SizedBox.square(
                          dimension: 28,
                          child: ProfileAvatar(
                            name: name,
                            photoPath: profile?.photoPath,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              selected: settingsSelected,
              child: AppIconButton(
                key: const ValueKey('desktop-sidebar-settings'),
                tooltip: settingsTooltip,
                isSelected: settingsSelected,
                iconSize: 18,
                color: settingsSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                // A fill marks Settings as open by more than its color.
                style: settingsSelected
                    ? IconButton.styleFrom(
                        backgroundColor: _SidebarRow.selectionFill(context),
                      )
                    : null,
                icon: AppIcon(
                  settingsSelected ? settings.selectedIcon : settings.icon,
                ),
                onPressed: onOpenSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The top of the sidebar panel: on macOS the rest of the title bar row,
/// where the traffic lights sit and a drag moves the window, with the
/// sidebar button at its end.
class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  /// Height without a title bar in the content (Windows, Linux).
  static const double height = 44;

  @override
  Widget build(BuildContext context) => SizedBox(
    // The panel starts [DesktopSidebar.margin] below the window top.
    height: desktopTitleBarInContent
        ? desktopTitleBarHeight - DesktopSidebar.margin
        : height,
    child: const Row(
      children: [
        Expanded(
          child: DesktopWindowDragArea(
            zoomOnDoubleClick: true,
            child: SizedBox.expand(),
          ),
        ),
        _SidebarToggle(hidden: false),
        SizedBox(width: 4),
      ],
    ),
  );
}

/// Hides the sidebar, or shows it from the content pane's title bar.
class _SidebarToggle extends StatelessWidget {
  const _SidebarToggle({required this.hidden});

  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppIconButton(
      key: ValueKey(hidden ? 'desktop-sidebar-show' : 'desktop-sidebar-toggle'),
      tooltip: desktopTooltip(
        context,
        hidden ? l10n.desktopShowSidebar : l10n.desktopHideSidebar,
        DesktopCommand.toggleSidebar,
      ),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      iconSize: 18,
      icon: const AppIcon(CupertinoIcons.sidebar_left),
      onPressed: () =>
          desktopSidebarCollapsed.value = !desktopSidebarCollapsed.value,
    );
  }
}

/// A sidebar section heading, in the small bold secondary style of macOS
/// source lists.
class _SidebarSectionHeader extends StatelessWidget {
  const _SidebarSectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(14, 16, 10, 4),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

/// One source-list row, measured from Music: a 32pt row inset 6pt from the
/// panel, an 18pt accent icon and a 13pt label, and an optional count. The
/// selected row gets a rounded translucent fill and a semibold label.
class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.tooltip,
    required this.onTap,
    this.badgeCount = 0,
  });

  /// Row height at the default text size; larger text grows the row.
  static const double height = 32;

  /// Corner radius of the selection fill.
  static const double radius = 8;

  /// The selected row's fill.
  static Color selectionFill(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.onSurface.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.12 : 0.08,
    );
  }

  /// A hovered row's fill, lighter than the selection.
  static Color hoverFill(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05);

  final IconData icon;
  final String label;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final borderRadius = BorderRadius.circular(radius);
    final badge = badgeCount > 0 ? '$badgeCount' : null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 800),
      child: Semantics(
        button: true,
        selected: selected,
        label: badge == null ? label : '$label, $badge',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: borderRadius,
          hoverColor: hoverFill(context),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? selectionFill(context) : null,
              borderRadius: borderRadius,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: height),
              child: Row(
                children: [
                  // Icon at 20pt and label at 56pt from the panel edge.
                  const SizedBox(width: 14),
                  AppIcon(icon, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      label,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badge != null)
                    Text(
                      badge,
                      style: textTheme.labelSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

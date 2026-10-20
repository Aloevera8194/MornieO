import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
// The rail's own item, used for Settings at the bottom of the rail so it
// keeps the same pill, label and motion as the destinations above it.
import 'package:material_3_expressive/components/navigation_rail/components/m3e_rail_item.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/screens/now_playing_screen.dart';
import 'package:mornye/services/shell_navigation_service.dart';
import 'package:mornye/theme/app_tokens.dart';
import 'package:mornye/theme/material_expressive.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/app_icon.dart';
import 'package:mornye/widgets/app_icon_button.dart';
import 'package:mornye/widgets/desktop/desktop_commands.dart';
import 'package:mornye/widgets/desktop/desktop_downloads_button.dart';
import 'package:mornye/widgets/desktop/desktop_inspector.dart';
import 'package:mornye/widgets/desktop/desktop_player_bar.dart';

/// Window width at which the Material rail shows labels beside its icons.
const double desktopExpandedRailBreakpoint = 1200;

/// Expanded rail and sidebar width.
const double desktopSidebarWidth = 220;

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

/// The desktop shell: navigation on the leading edge, the content pane, the
/// trailing inspector, and the persistent player bar across the bottom.
/// Material uses [DesktopNavigationRail] and a top bar with search and
/// downloads; Mornye uses [DesktopSidebar], with downloads in its player
/// toolbar.
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
    this.playerBar = const DesktopPlayerBar(),
    this.nowPlaying = const DesktopNowPlayingPane(),
  });

  /// Destinations in [desktopDestinationTabs] order; Cmd/Ctrl+1..5 follow it.
  final List<DesktopDestination> destinations;
  final ShellTab? selected;
  final ValueChanged<ShellTab> onSelected;
  final Widget body;
  final Widget playerBar;
  final Widget nowPlaying;

  @override
  Widget build(BuildContext context) {
    final mornye = context.isMornye;
    final width = MediaQuery.sizeOf(context).width;
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mornye)
                DesktopSidebar(
                  destinations: destinations,
                  selected: selected,
                  onSelected: onSelected,
                )
              else
                DesktopNavigationRail(
                  destinations: destinations,
                  selected: selected,
                  onSelected: onSelected,
                  extended: width >= desktopExpandedRailBreakpoint,
                ),
              if (mornye)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: MornyeTheme.metadataDividerColor(context),
                ),
              Expanded(
                child: _DesktopContentArea(
                  overlayInspector: desktopInspectorOverlays(width),
                  body: body,
                  nowPlaying: nowPlaying,
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

/// Gives [child] the size of the space it lays out in, so width-based layout
/// (centered columns, grids) measures the pane rather than the whole window.
class _PaneMediaQuery extends StatelessWidget {
  const _PaneMediaQuery({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mediaQuery = MediaQuery.of(context);
      return MediaQuery(
        data: mediaQuery
            .copyWith(size: Size(constraints.maxWidth, constraints.maxHeight))
            .removePadding(removeLeft: true, removeBottom: true),
        child: child,
      );
    },
  );
}

/// The content pane (with the Material top bar), Now Playing over it while
/// open, and the trailing inspector.
class _DesktopContentArea extends StatelessWidget {
  const _DesktopContentArea({
    required this.overlayInspector,
    required this.body,
    required this.nowPlaying,
  });

  final bool overlayInspector;
  final Widget body;
  final Widget nowPlaying;

  @override
  Widget build(BuildContext context) {
    final mornye = context.isMornye;
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
                        if (!mornye) const DesktopTopBar(),
                        // A semantics container keeps the tab navigators'
                        // modal barriers from hiding the sidebar and top bar.
                        Expanded(
                          child: Semantics(
                            container: true,
                            child: _PaneMediaQuery(child: body),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (nowPlayingOpen) _PaneMediaQuery(child: nowPlaying),
                  if (panel != null && overlayInspector)
                    PositionedDirectional(
                      top: 0,
                      bottom: 0,
                      end: 0,
                      width: desktopInspectorWidth,
                      child: DesktopInspector(panel: panel, overlay: true),
                    ),
                ],
              );
              // One structure for every state, so opening the inspector never
              // remounts the destinations.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: content),
                  if (panel != null && !overlayInspector)
                    DesktopInspector(panel: panel),
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

/// The Material top bar of the content pane: a persistent search field and
/// the downloads button. The field opens Search and focuses its input.
class DesktopTopBar extends StatelessWidget {
  const DesktopTopBar({super.key});

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hint = context.l10n.homeSearchHintDefault;
    final radius = BorderRadius.circular(context.tokens.radiusSheet);
    return Material(
      color: colorScheme.surface,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Tooltip(
                      message: desktopTooltip(
                        context,
                        context.l10n.mornyeSearch,
                        DesktopCommand.search,
                      ),
                      child: Semantics(
                        button: true,
                        label: hint,
                        excludeSemantics: true,
                        child: InkWell(
                          key: const ValueKey('desktop-top-bar-search'),
                          borderRadius: radius,
                          onTap: ShellNavigationService.requestSearch,
                          child: Ink(
                            height: 48,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHigh,
                              borderRadius: radius,
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 16),
                                AppIcon(
                                  Icons.search,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    hint,
                                    style: textTheme.bodyLarge?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
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
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const DesktopDownloadsButton(),
            ],
          ),
        ),
      ),
    );
  }
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
              for (final destination in primary) _railDestination(destination),
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
                      labelBehavior: M3ENavigationRailLabelBehavior.alwaysShow,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The Mornye source-list sidebar: a search field at the top, the
/// destinations, and Settings at the bottom. It collapses to icons with the
/// toolbar button, View > Hide Sidebar, or Control-Command-S.
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
  });

  static const double collapsedWidth = 64;

  final List<DesktopDestination> destinations;
  final ShellTab? selected;
  final ValueChanged<ShellTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : context.tokens.motionMedium;
    Widget row(DesktopDestination destination, bool collapsed) => _SidebarRow(
      icon: destination.icon,
      label: destination.label,
      badgeCount: destination.badgeCount,
      selected: destination.tab == selected,
      collapsed: collapsed,
      tooltip: desktopDestinationTooltip(
        context,
        destination.label,
        _positionOf(destinations, destination.tab),
      ),
      onTap: () => onSelected(destination.tab),
    );
    final settings = destinations
        .where((destination) => destination.tab == ShellTab.settings)
        .firstOrNull;
    return ValueListenableBuilder<bool>(
      valueListenable: desktopSidebarCollapsed,
      builder: (context, collapsed, _) => AnimatedContainer(
        duration: duration,
        curve: Curves.easeInOutCubic,
        width: collapsed ? collapsedWidth : desktopSidebarWidth,
        color: colorScheme.surfaceContainer,
        child: ClipRect(
          child: Material(
            type: MaterialType.transparency,
            child: OverflowBox(
              alignment: AlignmentDirectional.topStart,
              minWidth: collapsed ? collapsedWidth : desktopSidebarWidth,
              maxWidth: collapsed ? collapsedWidth : desktopSidebarWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: collapsed
                          ? Alignment.center
                          : AlignmentDirectional.centerStart,
                      child: AppIconButton(
                        key: const ValueKey('desktop-sidebar-toggle'),
                        tooltip: desktopTooltip(
                          context,
                          collapsed
                              ? l10n.desktopShowSidebar
                              : l10n.desktopHideSidebar,
                          DesktopCommand.toggleSidebar,
                        ),
                        color: colorScheme.onSurfaceVariant,
                        icon: const AppIcon(CupertinoIcons.sidebar_left),
                        onPressed: () => desktopSidebarCollapsed.value =
                            !desktopSidebarCollapsed.value,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _SidebarSearch(
                      collapsed: collapsed,
                      selected: selected == ShellTab.search,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final destination in destinations)
                            if (destination.tab != ShellTab.search &&
                                destination.tab != ShellTab.settings)
                              row(destination, collapsed),
                        ],
                      ),
                    ),
                    if (settings != null) row(settings, collapsed),
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

/// A search field in the sidebar's style. It opens the Search destination
/// and focuses its field, where results show in the content pane.
class _SidebarSearch extends StatelessWidget {
  const _SidebarSearch({required this.collapsed, required this.selected});

  final bool collapsed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = context.l10n.mornyeSearch;
    final tooltip = desktopTooltip(context, label, DesktopCommand.search);
    if (collapsed) {
      return _SidebarRow(
        icon: CupertinoIcons.search,
        label: label,
        selected: selected,
        collapsed: true,
        tooltip: tooltip,
        onTap: ShellNavigationService.requestSearch,
      );
    }
    final radius = BorderRadius.circular(context.tokens.radiusThumb + 2);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey('desktop-sidebar-search'),
          borderRadius: radius,
          hoverColor: colorScheme.onSurface.withValues(alpha: 0.04),
          onTap: ShellNavigationService.requestSearch,
          child: Ink(
            height: 32,
            decoration: BoxDecoration(
              color: MornyeTheme.controlFill(context),
              borderRadius: radius,
              border: selected
                  ? Border.all(color: colorScheme.primary, width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                AppIcon(
                  CupertinoIcons.search,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
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
    );
  }
}

/// One source-list row: an accent icon, the label and an optional count.
/// The selected row gets the gray selection fill used by macOS sidebars.
class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.tooltip,
    required this.onTap,
    this.badgeCount = 0,
  });

  static const double height = 36;

  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final String tooltip;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(context.tokens.radiusThumb + 2);
    final badge = badgeCount > 0 ? '$badgeCount' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: selected,
          label: badge == null ? label : '$label, $badge',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: radius,
            hoverColor: colorScheme.onSurface.withValues(alpha: 0.04),
            onTap: onTap,
            child: Ink(
              height: height,
              decoration: BoxDecoration(
                color: selected ? MornyeTheme.controlFill(context) : null,
                borderRadius: radius,
              ),
              child: collapsed
                  ? Center(
                      child: Badge(
                        isLabelVisible: badge != null,
                        label: Text(badge ?? ''),
                        child: AppIcon(
                          icon,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        const SizedBox(width: 8),
                        AppIcon(icon, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: textTheme.bodyMedium?.copyWith(
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
                            style: textTheme.labelMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(width: 8),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

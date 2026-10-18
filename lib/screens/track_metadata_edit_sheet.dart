import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:spotiflac_android/controllers/metadata_editor_controller.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/theme/app_motion.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/metadata_cover_resources.dart';
import 'package:spotiflac_android/services/metadata_autofill_service.dart';
import 'package:spotiflac_android/services/metadata_persistence_service.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/theme/mornye_icons.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';
import 'package:spotiflac_android/utils/extension_auth_launcher.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/widgets/app_action_button.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/app_choice_chip.dart';
import 'package:spotiflac_android/widgets/app_content_card.dart';
import 'package:spotiflac_android/widgets/app_progress_indicator.dart';
import 'package:spotiflac_android/widgets/app_icon_button.dart';
import 'package:spotiflac_android/widgets/app_loading_indicator.dart';
import 'package:spotiflac_android/widgets/app_snack_bar.dart';
import 'package:spotiflac_android/widgets/app_switch.dart';
import 'package:spotiflac_android/widgets/metadata_candidate_tile.dart';
import 'package:spotiflac_android/widgets/metadata_text_field.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

part 'track_metadata_edit_autofill.dart';
part 'track_metadata_edit_cover.dart';

final _log = AppLogger('MetadataEditor');

class EditMetadataSheet extends StatefulWidget {
  static const _onlineCoverSentinel = '__online_cover__';
  final ColorScheme colorScheme;
  final Map<String, String> initialValues;
  final String filePath;
  final String? sourceTrackId;
  final int durationMs;
  final String artistTagMode;

  const EditMetadataSheet({
    super.key,
    required this.colorScheme,
    required this.initialValues,
    required this.filePath,
    this.sourceTrackId,
    required this.durationMs,
    required this.artistTagMode,
  });

  @override
  State<EditMetadataSheet> createState() => _EditMetadataSheetState();
}

class _EditMetadataSheetState extends State<EditMetadataSheet> {
  static const _coverResizeDimensions = <int>[500, 1000, 1500, 2000, 3000];

  bool _saving = false;
  final _covers = MetadataCoverResources();
  late final _persistence = MetadataPersistenceService(covers: _covers);
  final _autofill = MetadataAutofillService();
  bool _showAdvanced = false;
  bool _showAutoFill = false;
  bool _fetching = false;
  String? _selectedCoverPath;
  String? _selectedCoverTempDir;
  String? _selectedCoverName;
  String? _currentCoverPath;
  String? _currentCoverTempDir;
  bool _loadingCurrentCover = false;
  int? _coverMaxDimension;
  final Map<String, ({int width, int height, int bytes})> _coverDetails = {};
  final Set<String> _coverDetailLoads = {};
  String? _selectedMetadataProviderId;
  _AutoFillPreview? _autoFillPreview;
  final GlobalKey<ScaffoldMessengerState> _sheetMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// setState is @protected, so the extension part files route rebuilds
  /// through this forwarder.
  void _setState(VoidCallback fn) => setState(fn);

  Future<T?> _showEditorOptionPicker<T>({
    required String Function(BuildContext sheetContext) title,
    required List<T> Function(BuildContext sheetContext) options,
    required bool Function(T option) isSelected,
    required String Function(BuildContext sheetContext, T option) label,
    required IconData Function(BuildContext sheetContext, T option) icon,
    bool ellipsizeLabels = false,
    bool checkInSheetTheme = false,
  }) {
    FocusScope.of(context).unfocus();
    return showModalBottomSheet<T>(
      context: context,
      sheetAnimationStyle: AppMotion.surfaceEntrance(context),
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        final items = options(sheetContext);

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Text(
                    title(sheetContext),
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _editorOptions(
                      children: [
                        for (var index = 0; index < items.length; index++)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 4,
                                ),
                                leading: Icon(
                                  icon(sheetContext, items[index]),
                                  color: isSelected(items[index])
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                                title: Text(
                                  label(sheetContext, items[index]),
                                  maxLines: ellipsizeLabels ? 2 : null,
                                  overflow: ellipsizeLabels
                                      ? TextOverflow.ellipsis
                                      : null,
                                ),
                                selected: isSelected(items[index]),
                                selectedColor: cs.primary,
                                trailing: isSelected(items[index])
                                    ? Icon(
                                        (checkInSheetTheme
                                                    ? sheetContext
                                                    : context)
                                                .isMornye
                                            ? CupertinoIcons.checkmark
                                            : Icons.check_rounded,
                                      )
                                    : null,
                                onTap: () =>
                                    Navigator.pop(sheetContext, items[index]),
                              ),
                              if (index != items.length - 1)
                                Divider(
                                  height: 1,
                                  indent: 60,
                                  endIndent: 20,
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSheetSnackBar(String message) {
    final snackBar = SnackBar(content: Text(message));
    final messenger = _sheetMessengerKey.currentState;
    if (messenger != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(snackBar);
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(snackBar);
  }

  late final MetadataEditorController _form;
  bool _fetchingMusicBrainz = false;

  bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;

  String _fieldLabel(String key) {
    final l10n = context.l10n;
    return switch (key) {
      'title' => l10n.editMetadataFieldTitle,
      'artist' => l10n.editMetadataFieldArtist,
      'album' => l10n.editMetadataFieldAlbum,
      'album_artist' => l10n.editMetadataFieldAlbumArtist,
      'date' => l10n.editMetadataFieldDate,
      'track_number' => l10n.editMetadataFieldTrackNum,
      'total_tracks' => l10n.editMetadataFieldTrackTotal,
      'disc_number' => l10n.editMetadataFieldDiscNum,
      'total_discs' => l10n.editMetadataFieldDiscTotal,
      'genre' => l10n.editMetadataFieldGenre,
      'isrc' => l10n.editMetadataFieldIsrc,
      'lyrics' => l10n.trackLyrics,
      'label' => l10n.editMetadataFieldLabel,
      'copyright' => l10n.editMetadataFieldCopyright,
      'composer' => l10n.editMetadataFieldComposer,
      'comment' => l10n.editMetadataFieldComment,
      'album_type' => l10n.trackAlbumType,
      'explicit' => l10n.editMetadataFieldExplicit,
      'upc' => l10n.editMetadataFieldUpc,
      'cover' => l10n.editMetadataFieldCover,
      _ => key,
    };
  }

  @override
  void initState() {
    super.initState();
    _form = MetadataEditorController(widget.initialValues);
    unawaited(_loadCurrentCoverPreview());
  }

  @override
  void dispose() {
    unawaited(_covers.dispose());
    _form.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _fetching || _fetchingMusicBrainz) return;
    setState(() => _saving = true);
    try {
      final result = await _persistence.save(
        MetadataSaveRequest(
          filePath: widget.filePath,
          metadata: _form.saveMetadata(artistTagMode: widget.artistTagMode),
          artistTagMode: widget.artistTagMode,
          selectedCoverPath: _selectedCoverPath,
          currentCoverPath: _currentCoverPath,
          coverMaxDimension: _coverMaxDimension,
        ),
      );
      if (!mounted) return;
      if (result.failure == null) {
        Navigator.pop(context, true);
        return;
      }
      final l10n = context.l10n;
      _showSheetSnackBar(switch (result.failure!) {
        MetadataSaveFailure.backend => context.friendlyError(
          result.error,
          fallback: l10n.metadataSaveFailedFfmpeg,
        ),
        MetadataSaveFailure.ffmpeg => l10n.metadataSaveFailedFfmpeg,
        MetadataSaveFailure.storage => l10n.metadataSaveFailedStorage,
        MetadataSaveFailure.noCover => l10n.snackbarError(
          l10n.trackCoverNoEmbeddedArt,
        ),
        MetadataSaveFailure.resize => l10n.snackbarError(
          l10n.trackCoverResizeFailed,
        ),
        MetadataSaveFailure.unexpected => l10n.snackbarError(
          context.friendlyError(result.error),
        ),
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => AppScaffoldMessenger(
          key: _sheetMessengerKey,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: const AppSheetHandle(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.trackEditMetadata,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_saving)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: context.isMornye
                                ? const CupertinoActivityIndicator()
                                : const AppLoadingIndicator(
                                    size: 22,
                                    strokeWidth: 2,
                                  ),
                          ),
                        )
                      else
                        AppActionButton(
                          onPressed: _fetching || _fetchingMusicBrainz
                              ? null
                              : _save,
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(context.l10n.dialogSave),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                    children: [
                      _buildCoverEditor(cs),
                      _buildAutoFillSection(cs),
                      _sectionCard(
                        icon: Icons.info_outline,
                        title: context.l10n.trackMetadata,
                        children: [
                          MetadataTextField(
                            cs,
                            context.l10n.editMetadataFieldTitle,
                            _form['title']!,
                          ),
                          MetadataTextField(
                            cs,
                            context.l10n.editMetadataFieldArtist,
                            _form['artist']!,
                          ),
                          MetadataTextField(
                            cs,
                            context.l10n.editMetadataFieldAlbum,
                            _form['album']!,
                          ),
                          MetadataTextField(
                            cs,
                            context.l10n.editMetadataFieldAlbumArtist,
                            _form['album_artist']!,
                          ),
                          MetadataTextField(
                            cs,
                            context.l10n.editMetadataFieldDate,
                            _form['date']!,
                            hint: context.l10n.editMetadataFieldDateHint,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: MetadataTextField(
                                  cs,
                                  context.l10n.editMetadataFieldTrackNum,
                                  _form['track_number']!,
                                  keyboard: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: MetadataTextField(
                                  cs,
                                  context.l10n.editMetadataFieldTrackTotal,
                                  _form['total_tracks']!,
                                  keyboard: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: MetadataTextField(
                                  cs,
                                  context.l10n.editMetadataFieldDiscNum,
                                  _form['disc_number']!,
                                  keyboard: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: MetadataTextField(
                                  cs,
                                  context.l10n.editMetadataFieldDiscTotal,
                                  _form['total_discs']!,
                                  keyboard: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          MetadataTextField(
                            cs,
                            context.l10n.editMetadataFieldGenre,
                            _form['genre']!,
                          ),
                          MetadataTextField(
                            cs,
                            context.l10n.editMetadataFieldIsrc,
                            _form['isrc']!,
                          ),
                        ],
                      ),
                      _sectionCard(
                        icon: Icons.lyrics_outlined,
                        title: context.l10n.trackLyrics,
                        children: [
                          MetadataTextField(
                            cs,
                            context.l10n.trackLyrics,
                            _form['lyrics']!,
                            maxLines: 8,
                            keyboard: TextInputType.multiline,
                          ),
                        ],
                      ),
                      _sectionCard(
                        icon: Icons.tune,
                        title: context.l10n.editMetadataAdvanced,
                        onHeaderTap: () =>
                            setState(() => _showAdvanced = !_showAdvanced),
                        expanded: _showAdvanced,
                        children: [
                          if (_showAdvanced) ...[
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldLabel,
                              _form['label']!,
                            ),
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldCopyright,
                              _form['copyright']!,
                            ),
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldComposer,
                              _form['composer']!,
                            ),
                            MetadataTextField(
                              cs,
                              context.l10n.trackAlbumType,
                              _form['album_type']!,
                              hint: context.l10n.editMetadataFieldAlbumTypeHint,
                            ),
                            _switchField(
                              label: context.l10n.editMetadataFieldExplicit,
                              subtitle:
                                  context.l10n.editMetadataFieldExplicitHint,
                              value: _form.explicit,
                              onChanged: (value) =>
                                  setState(() => _form.explicit = value),
                            ),
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldUpc,
                              _form['upc']!,
                              hint: context.l10n.editMetadataFieldUpcHint,
                              keyboard: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(18),
                              ],
                            ),
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldComment,
                              _form['comment']!,
                              maxLines: 3,
                            ),
                          ],
                        ],
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

  Widget _editorOptions({required List<Widget> children}) {
    if (!context.isMornye) return SettingsGroup(children: children);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: MornyeTheme.controlFill(context),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _quickSelectButton({
    required String label,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    if (context.isMornye) {
      return CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        onPressed: _fetching ? null : onTap,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: cs.primary),
        ),
      );
    }
    return InkWell(
      onTap: _fetching ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: cs.primary),
        ),
      ),
    );
  }

  Widget _switchField({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = widget.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Material(
            color: metadataEditorFieldFill(context, cs),
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: AppSwitchListTile(
              adaptive: true,
              value: value,
              onChanged: onChanged,
              contentPadding: EdgeInsets.symmetric(
                horizontal: context.isMornye ? 4 : 16,
              ),
              title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
              subtitle: Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          if (context.isMornye) const Divider(height: 0.5),
        ],
      ),
    );
  }

  Widget _selectionField({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final cs = widget.colorScheme;
    if (context.isMornye) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            CupertinoButton(
              color: metadataEditorFieldFill(context, cs),
              disabledColor: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
              onPressed: enabled ? onTap : null,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    CupertinoIcons.chevron_up_chevron_down,
                    size: 16,
                    color: cs.primary,
                  ),
                ],
              ),
            ),
            const Divider(height: 0.5),
          ],
        ),
      );
    }
    final radius = BorderRadius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: enabled ? cs.onSurfaceVariant : cs.outline,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
          Material(
            color: metadataEditorFieldFill(context, cs),
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: enabled ? cs.onSurface : cs.outline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.expand_more_rounded,
                      color: enabled ? cs.onSurfaceVariant : cs.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  RoundedRectangleBorder _sectionCardShape(ColorScheme cs) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
    );
  }

  /// Titled section card. When [onHeaderTap] is set the header is a full-width
  /// tappable row (ripple clipped to the card) with an auto chevron.
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
    VoidCallback? onHeaderTap,
    bool expanded = true,
  }) {
    final cs = widget.colorScheme;
    final collapsible = onHeaderTap != null;
    const inset = 16.0;

    final headerRow = Row(
      children: [
        Icon(context.adaptiveIcon(icon), size: 20, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        if (collapsible)
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Icon(
              context.isMornye
                  ? CupertinoIcons.chevron_down
                  : Icons.expand_more,
              size: 22,
              color: cs.onSurfaceVariant,
            ),
          ),
      ],
    );

    final Widget header = collapsible
        ? InkWell(
            onTap: onHeaderTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(inset, 16, inset, 16),
              child: headerRow,
            ),
          )
        : Padding(
            padding: EdgeInsets.fromLTRB(inset, 16, inset, 8),
            child: headerRow,
          );

    final content = AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          if (children.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(inset, 0, inset, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: context.isMornye
          ? Material(
              color: MornyeTheme.controlFill(context),
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: DividerTheme(
                data: DividerTheme.of(
                  context,
                ).copyWith(color: MornyeTheme.metadataDividerColor(context)),
                child: content,
              ),
            )
          : AppContentCard(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: settingsGroupColor(context),
              shape: _sectionCardShape(cs),
              clipBehavior: Clip.antiAlias,
              child: content,
            ),
    );
  }
}

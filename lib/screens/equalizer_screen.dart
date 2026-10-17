import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/equalizer_settings.dart';
import 'package:spotiflac_android/providers/equalizer_provider.dart';
import 'package:spotiflac_android/services/playback_equalizer.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/material_expressive.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/app_alert_dialog.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/app_choice_chip.dart';
import 'package:spotiflac_android/widgets/app_icon.dart';
import 'package:spotiflac_android/widgets/app_menu_button.dart';
import 'package:spotiflac_android/widgets/app_slider.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/app_switch.dart';
import 'package:spotiflac_android/widgets/app_text_field.dart';
import 'package:spotiflac_android/widgets/beta_badge.dart';
import 'package:spotiflac_android/widgets/expressive_button.dart';
import 'package:spotiflac_android/widgets/expressive_icon_button.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';
import 'package:spotiflac_android/widgets/mornye_level_slider.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

enum _PresetAction { manage, import, export }

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  bool _busy = false;

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _savePreset() async {
    final name = await showAppDialog<String>(
      context: context,
      builder: (context) => const _PresetNameDialog(),
    );
    if (!mounted || name == null) return;
    try {
      ref.read(equalizerProvider.notifier).savePreset(name);
      _message(context.l10n.equalizerSaved);
    } on FormatException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      if ((await file.length() ?? 65537) > 65536) throw const FormatException();
      final source = utf8.decode(await file.readAsBytes());
      if (!mounted) return;
      ref.read(equalizerProvider.notifier).importPreset(source);
      _message(context.l10n.equalizerSaved);
    } catch (_) {
      if (mounted) _message(context.l10n.equalizerImportInvalid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final source = ref
        .read(equalizerProvider.notifier)
        .exportPreset('Custom EQ');
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(source)),
              mimeType: 'application/json',
            ),
          ],
          fileNameOverrides: ['spotiflac-equalizer.json'],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      if (mounted) _message(context.l10n.snackbarError(error.toString()));
    }
  }

  Future<void> _presets() => showAppBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    title: context.l10n.equalizerPresets,
    maxHeightFactor: 0.85,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(equalizerProvider);
        final selected = _matchingPreset(state);
        final mornye = context.isMornye;
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final preset in [
                ...EqualizerPreset.builtIn,
                ...state.presets,
              ])
                AppSheetOption(
                  title: Text(preset.name),
                  selected: preset == selected,
                  // iOS lists mark the choice with a trailing checkmark.
                  leading: mornye
                      ? null
                      : preset == selected
                      ? const AppIcon(Icons.check)
                      : const AppIcon(Icons.graphic_eq),
                  trailing:
                      (mornye && preset == selected) ||
                          state.presets.contains(preset)
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (mornye && preset == selected)
                              AppIcon(
                                Icons.check,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            if (state.presets.contains(preset))
                              IconButton(
                                tooltip: context.l10n.equalizerDeletePreset,
                                icon: const AppIcon(Icons.delete_outline),
                                onPressed: () => ref
                                    .read(equalizerProvider.notifier)
                                    .deletePreset(preset.name),
                              ),
                          ],
                        )
                      : null,
                  onTap: () {
                    ref.read(equalizerProvider.notifier).applyPreset(preset);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _reset() async {
    final accepted = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.equalizerResetTitle),
        content: Text(context.l10n.equalizerResetDescription),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.dialogCancel),
          ),
          AppDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.libraryFilterReset),
          ),
        ],
      ),
    );
    if (mounted && accepted == true) {
      final enabled = ref.read(equalizerProvider).settings.enabled;
      ref
          .read(equalizerProvider.notifier)
          .update(EqualizerSettings(enabled: enabled));
    }
  }

  @override
  Widget build(BuildContext context) => MornyeSettingsTheme(
    // Reached from Playback and Now Playing alike, so the page brings its own
    // inset grouped surfaces in Mornye.
    child: Builder(builder: _buildPage),
  );

  Widget _buildPage(BuildContext context) {
    final state = ref.watch(equalizerProvider);
    final settings = state.settings;
    final notifier = ref.read(equalizerProvider.notifier);
    final l10n = context.l10n;
    final mornye = context.isMornye;
    final selectedPreset = _matchingPreset(state);
    final presetName = selectedPreset?.name ?? l10n.equalizerCustom;
    void update(EqualizerSettings next) => notifier.update(next);
    void setEnabled(bool v) => update(settings.copyWith(enabled: v));
    Widget section(Widget child) => SliverToBoxAdapter(child: child);
    final error = section(
      ValueListenableBuilder<String?>(
        valueListenable: playbackEqualizerError,
        builder: (context, error, _) {
          final message = error ?? state.error;
          return message == null
              ? const SizedBox.shrink()
              : SettingsInfoCard(
                  message: message,
                  icon: Icons.error_outline,
                  tone: SettingsInfoTone.error,
                  glass: true,
                );
        },
      ),
    );
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: l10n.equalizerTitle),
          if (mornye) ...[
            // iOS order: the master switch, its footnote, then the response.
            section(
              SettingsGroup(
                children: [
                  SettingsSwitchItem(
                    icon: Icons.graphic_eq,
                    title: l10n.equalizerEnable,
                    titleTrailing: const BetaBadge(),
                    value: settings.enabled,
                    onChanged: setEnabled,
                    showDivider: false,
                  ),
                ],
              ),
            ),
            section(_Footnote(l10n.equalizerBypass)),
            error,
            section(
              SettingsGroup(
                children: [
                  _EqualizerOverview(
                    settings: settings,
                    presetName: presetName,
                  ),
                ],
              ),
            ),
            // The value cell names the group, so it needs no header.
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
            section(
              SettingsGroup(
                children: [
                  SettingsItem(
                    title: l10n.equalizerPresets,
                    trailing: _DetailValue(presetName),
                    onTap: _presets,
                  ),
                  _ActionRow(
                    label: l10n.equalizerSavePreset,
                    onTap: _savePreset,
                  ),
                  _ActionRow(
                    label: l10n.equalizerImport,
                    onTap: _busy ? null : _import,
                  ),
                  _ActionRow(
                    label: l10n.equalizerExport,
                    onTap: _export,
                    last: true,
                  ),
                ],
              ),
            ),
          ] else ...[
            section(
              SettingsGroup(
                children: [
                  _EqualizerOverview(
                    settings: settings,
                    presetName: presetName,
                    onEnabledChanged: setEnabled,
                  ),
                ],
              ),
            ),
            error,
            section(
              SettingsInfoCard(
                message: l10n.equalizerBypass,
                icon: Icons.info_outline,
              ),
            ),
            section(SettingsSectionHeader(title: l10n.equalizerPresets)),
            section(
              _PresetBar(
                presets: [...EqualizerPreset.builtIn, ...state.presets],
                selected: selectedPreset,
                busy: _busy,
                onApply: notifier.applyPreset,
                onSave: _savePreset,
                onReset: _reset,
                onAction: (action) => switch (action) {
                  _PresetAction.manage => _presets(),
                  _PresetAction.import => _import(),
                  _PresetAction.export => _export(),
                },
              ),
            ),
          ],
          section(SettingsSectionHeader(title: l10n.equalizerBands)),
          section(
            SettingsGroup(
              children: [_BandEditor(settings: settings, onChanged: update)],
            ),
          ),
          section(SettingsSectionHeader(title: l10n.equalizerTone)),
          section(
            SettingsGroup(
              connected: true,
              children: [
                _SliderTile(
                  icon: Icons.volume_up_outlined,
                  title: l10n.equalizerPreamp,
                  subtitle:
                      '${l10n.equalizerEffectivePreamp}: ${_signed(settings.inputGain)} dB',
                  value: settings.preamp,
                  min: -24,
                  max: 12,
                  step: 0.5,
                  unit: 'dB',
                  onChanged: (v) => update(settings.copyWith(preamp: v)),
                ),
                _SliderTile(
                  icon: Icons.speaker_outlined,
                  title: l10n.equalizerBass,
                  value: settings.bass,
                  min: -12,
                  max: 12,
                  step: 0.5,
                  unit: 'dB',
                  centered: true,
                  onChanged: (v) => update(settings.copyWith(bass: v)),
                ),
                _SliderTile(
                  icon: Icons.music_note_outlined,
                  title: l10n.equalizerTreble,
                  value: settings.treble,
                  min: -12,
                  max: 12,
                  step: 0.5,
                  unit: 'dB',
                  centered: true,
                  onChanged: (v) => update(settings.copyWith(treble: v)),
                ),
                _SliderTile(
                  icon: Icons.surround_sound_outlined,
                  title: l10n.equalizerBalance,
                  value: settings.balance * 100,
                  min: -100,
                  max: 100,
                  step: 1,
                  unit: '%',
                  centered: true,
                  last: true,
                  onChanged: (v) => update(settings.copyWith(balance: v / 100)),
                ),
              ],
            ),
          ),
          section(SettingsSectionHeader(title: l10n.equalizerDynamics)),
          section(
            SettingsGroup(
              connected: true,
              children: [
                SettingsSwitchItem(
                  icon: Icons.vertical_align_bottom,
                  title: l10n.equalizerHeadroom,
                  subtitle: l10n.equalizerHeadroomDescription,
                  value: settings.autoHeadroom,
                  onChanged: (v) => update(settings.copyWith(autoHeadroom: v)),
                ),
                SettingsSwitchItem(
                  icon: Icons.health_and_safety_outlined,
                  title: l10n.equalizerLimiter,
                  subtitle: l10n.equalizerLimiterDescription,
                  value: settings.limiter,
                  onChanged: (v) => update(settings.copyWith(limiter: v)),
                ),
                SettingsSwitchItem(
                  icon: Icons.compress,
                  title: l10n.equalizerCompressor,
                  subtitle: l10n.equalizerCompressorDescription,
                  value: settings.compressor,
                  onChanged: (v) => update(settings.copyWith(compressor: v)),
                  showDivider: settings.compressor,
                ),
                if (settings.compressor) ...[
                  _SliderTile(
                    title: l10n.equalizerThreshold,
                    indented: true,
                    value: settings.threshold,
                    min: -60,
                    max: 0,
                    step: 0.5,
                    unit: 'dB',
                    onChanged: (v) => update(settings.copyWith(threshold: v)),
                  ),
                  _SliderTile(
                    title: l10n.equalizerRatio,
                    indented: true,
                    value: settings.ratio,
                    min: 1,
                    max: 20,
                    step: 0.5,
                    unit: ':1',
                    signed: false,
                    onChanged: (v) => update(settings.copyWith(ratio: v)),
                  ),
                  _SliderTile(
                    title: l10n.equalizerAttack,
                    indented: true,
                    value: settings.attack,
                    min: 1,
                    max: 100,
                    step: 1,
                    unit: 'ms',
                    signed: false,
                    onChanged: (v) => update(settings.copyWith(attack: v)),
                  ),
                  _SliderTile(
                    title: l10n.equalizerRelease,
                    indented: true,
                    value: settings.release,
                    min: 20,
                    max: 1000,
                    step: 10,
                    unit: 'ms',
                    signed: false,
                    last: true,
                    onChanged: (v) => update(settings.copyWith(release: v)),
                  ),
                ],
              ],
            ),
          ),
          if (mornye) ...[
            // iOS keeps a destructive command in its own group at the end.
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
            section(
              SettingsGroup(
                children: [
                  _ActionRow(
                    label: l10n.libraryFilterReset,
                    onTap: _reset,
                    destructive: true,
                    last: true,
                  ),
                ],
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: SizedBox(height: 40 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }
}

/// The preset whose curve, tone and dynamics match the current settings.
EqualizerPreset? _matchingPreset(EqualizerState state) {
  String key(EqualizerSettings settings) =>
      jsonEncode(settings.copyWith(enabled: false).toJson());
  final current = key(state.settings);
  for (final preset in [...EqualizerPreset.builtIn, ...state.presets]) {
    if (key(preset.settings) == current) return preset;
  }
  return null;
}

/// iOS section footer: secondary text under the group it explains.
class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inset = settingsHorizontalInset(constraints.maxWidth) + 16;
      final theme = Theme.of(context);
      return Padding(
        padding: EdgeInsets.fromLTRB(inset, 4, inset, 8),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    },
  );
}

/// iOS "value" cell detail: the current choice in secondary text before the
/// disclosure chevron.
class _DetailValue extends StatelessWidget {
  const _DetailValue(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(color: secondary),
          ),
        ),
        const SizedBox(width: 6),
        AppIcon(Icons.chevron_right, size: 20, color: secondary),
      ],
    );
  }
}

/// iOS action cell: tinted text that runs a command instead of navigating.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.last = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool destructive, last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = context.tokens;
    final color = onTap == null
        ? theme.disabledColor
        : destructive
        ? colors.error
        : colors.primary;
    return Semantics(
      button: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            highlightColor: colors.onSurface.withValues(alpha: 0.06),
            splashFactory: NoSplash.splashFactory,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: tokens.minTouchTarget),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tokens.rowPaddingH,
                  vertical: tokens.rowPaddingV,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(color: color),
                  ),
                ),
              ),
            ),
          ),
          if (!last)
            Divider(
              height: 1,
              indent: tokens.rowPaddingH,
              endIndent: tokens.rowPaddingH,
              color: colors.outlineVariant,
            ),
        ],
      ),
    );
  }
}

/// Status, master switch and the estimated response of the whole chain.
class _EqualizerOverview extends StatelessWidget {
  const _EqualizerOverview({
    required this.settings,
    required this.presetName,
    this.onEnabledChanged,
  });

  final EqualizerSettings settings;
  final String presetName;

  /// Shows the master switch beside the title; Mornye keeps it in its own
  /// row above.
  final ValueChanged<bool>? onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = context.tokens;
    final enabled = settings.enabled;
    final curveColor = enabled ? colors.primary : colors.outline;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.rowPaddingH,
        tokens.gapLg,
        tokens.gapLg,
        tokens.gapLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: tokens.motionMedium,
                      style: theme.textTheme.headlineSmall!.copyWith(
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                      ),
                      child: Text(
                        presetName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: tokens.gapXs),
                    Row(
                      children: [
                        const BetaBadge(),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${settings.gains.length} ${l10n.equalizerBands.toLowerCase()} · ${l10n.equalizerPreamp} ${_signed(settings.inputGain)} dB',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onEnabledChanged != null) ...[
                SizedBox(width: tokens.gapMd),
                AppSwitch(
                  value: enabled,
                  semanticLabel: l10n.equalizerEnable,
                  onChanged: onEnabledChanged,
                ),
              ],
            ],
          ),
          SizedBox(height: tokens.gapLg),
          Semantics(
            label: l10n.equalizerCurveDescription,
            child: SizedBox(
              height: 152,
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: curveColor),
                duration: tokens.motionMedium,
                builder: (context, color, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _EqualizerCurve(
                    settings: settings,
                    color: color ?? curveColor,
                    grid: colors.outlineVariant,
                    label: colors.onSurfaceVariant,
                    labelStyle: theme.textTheme.labelSmall!,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: tokens.gapSm),
          Text(
            l10n.equalizerCurve,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick-apply chips for every preset, plus save, reset and overflow actions.
class _PresetBar extends StatelessWidget {
  const _PresetBar({
    required this.presets,
    required this.selected,
    required this.busy,
    required this.onApply,
    required this.onSave,
    required this.onReset,
    required this.onAction,
  });

  final List<EqualizerPreset> presets;
  final EqualizerPreset? selected;
  final bool busy;
  final ValueChanged<EqualizerPreset> onApply;
  final VoidCallback onSave;
  final VoidCallback onReset;
  final ValueChanged<_PresetAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = settingsHorizontalInset(constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Row(
                children: [
                  for (final (index, preset) in presets.indexed) ...[
                    if (index > 0) SizedBox(width: tokens.gapSm),
                    AppChoiceChip(
                      label: Text(preset.name),
                      selected: preset == selected,
                      singleChoice: true,
                      onSelected: (_) => onApply(preset),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: tokens.gapMd),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Row(
                children: [
                  Flexible(
                    child: ExpressiveButton(
                      onPressed: onSave,
                      tonal: true,
                      icon: const AppIcon(Icons.bookmark_add_outlined),
                      child: Text(
                        l10n.equalizerSavePreset,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const Spacer(),
                  ExpressiveIconButton(
                    tooltip: l10n.libraryFilterReset,
                    icon: const AppIcon(Icons.restart_alt),
                    onPressed: onReset,
                  ),
                  AppMenuButton<_PresetAction>(
                    icon: const AppIcon(Icons.more_vert),
                    tooltip: l10n.equalizerPresets,
                    onSelected: onAction,
                    items: [
                      AppMenuItem(
                        value: _PresetAction.manage,
                        label: l10n.equalizerManagePresets,
                        leading: const AppIcon(Icons.tune),
                      ),
                      if (!busy)
                        AppMenuItem(
                          value: _PresetAction.import,
                          label: l10n.equalizerImport,
                          leading: const AppIcon(Icons.file_open_outlined),
                        ),
                      AppMenuItem(
                        value: _PresetAction.export,
                        label: l10n.equalizerExport,
                        leading: const AppIcon(Icons.ios_share),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Band count picker and one vertical gain fader per band.
class _BandEditor extends StatelessWidget {
  const _BandEditor({required this.settings, required this.onChanged});

  final EqualizerSettings settings;
  final ValueChanged<EqualizerSettings> onChanged;

  static const _minColumnWidth = 32.0;
  static const _faderHeight = 208.0;

  void _setGain(int index, double value) {
    final gains = [...settings.gains];
    gains[index] = value;
    onChanged(settings.copyWith(gains: gains));
  }

  Widget _countPicker(BuildContext context) {
    final count = settings.gains.length;
    const counts = EqualizerSettings.bandCounts;
    void select(int index) => onChanged(settings.withBandCount(counts[index]));
    if (context.isMornye) {
      return Semantics(
        label: context.l10n.equalizerBands,
        child: MornyeSegmentedControl(
          labels: [for (final value in counts) '$value'],
          selectedIndex: counts.indexOf(count),
          onChanged: select,
        ),
      );
    }
    if (materialExpressiveEnabled(context)) {
      return MaterialExpressiveScope(
        child: M3EButtonGroup(
          type: M3EButtonGroupType.connected,
          style: M3EButtonStyle.filled,
          // Connected segments fill the row, so the 40 dp small button gets
          // no inflated target; 48 keeps each segment a full touch target.
          size: M3EButtonSize.sm.copyWith(height: 48),
          selectedIndex: counts.indexOf(count),
          selectionRequired: true,
          onSelectedIndexChanged: (index) {
            if (index != null) select(index);
          },
          semanticLabel: context.l10n.equalizerBands,
          actions: [
            for (final value in counts)
              M3EButtonGroupAction(label: Text('$value')),
          ],
        ),
      );
    }
    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: [
        for (final value in counts)
          ButtonSegment(value: value, label: Text('$value')),
      ],
      selected: {count},
      onSelectionChanged: (value) => select(counts.indexOf(value.first)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final count = settings.gains.length;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.gapLg),
            child: SizedBox(
              width: double.infinity,
              child: _countPicker(context),
            ),
          ),
          SizedBox(height: tokens.gapLg),
          LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth - tokens.gapSm * 2;
              final width = math.max(_minColumnWidth, available / count);
              final scrolls = width * count > available + 0.5;
              final faders = Row(
                children: [
                  for (var i = 0; i < count; i++)
                    SizedBox(
                      width: width,
                      child: _BandFader(
                        frequency: settings.frequencies[i],
                        gain: settings.gains[i],
                        width: width,
                        height: _faderHeight,
                        resetLabel: l10n.libraryFilterReset,
                        onChanged: (v) => _setGain(i, v),
                      ),
                    ),
                ],
              );
              return Stack(
                children: [
                  // 0 dB reference across every fader.
                  Positioned(
                    left: tokens.gapSm,
                    right: tokens.gapSm,
                    top: _BandFader.labelExtent + _faderHeight / 2,
                    child: Divider(
                      height: 1,
                      color: colors.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  scrolls
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.gapSm,
                          ),
                          child: faders,
                        )
                      : Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.gapSm,
                          ),
                          child: faders,
                        ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BandFader extends StatelessWidget {
  const _BandFader({
    required this.frequency,
    required this.gain,
    required this.width,
    required this.height,
    required this.resetLabel,
    required this.onChanged,
  });

  final double frequency;
  final double gain;
  final double width;
  final double height;
  final String resetLabel;
  final ValueChanged<double> onChanged;

  /// Height of the gain label and its gap above the fader, so the 0 dB line
  /// can align with the faders' centers.
  static const labelExtent = 32.0 + 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = context.tokens;
    final active = gain != 0;
    final mornye = context.isMornye;
    final hz = _frequency(frequency);
    final valueStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: !active
          ? colors.onSurfaceVariant
          : mornye
          ? colors.primary
          : colors.onSecondaryContainer,
    );
    final semanticLabel = '$hz Hz';
    String semantics(double v) => '${v.toStringAsFixed(1)} dB';
    return Column(
      children: [
        // Tapping the gain returns the band to 0 dB.
        Tooltip(
          message: '$resetLabel $hz Hz',
          child: SizedBox(
            height: 32,
            child: Center(
              child: Material(
                // iOS shows the gain as plain tinted text, Material as a badge.
                color: active && !mornye
                    ? colors.secondaryContainer
                    : Colors.transparent,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                animationDuration: tokens.motionFast,
                child: InkWell(
                  onTap: active ? () => onChanged(0) : null,
                  child: Container(
                    height: 28,
                    constraints: BoxConstraints(maxWidth: width - 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_signed(gain), style: valueStyle),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: height,
          child: mornye
              ? MornyeLevelSlider(
                  vertical: true,
                  value: gain,
                  min: -15,
                  max: 15,
                  origin: 0,
                  step: 0.5,
                  knobRadius: ((width - 8) / 2).clamp(9.0, 14.0),
                  semanticLabel: semanticLabel,
                  semanticFormatterCallback: semantics,
                  onChanged: (v) => onChanged(_snap(v, 0.5)),
                )
              : AppSlider(
                  vertical: true,
                  centered: true,
                  value: gain,
                  min: -15,
                  max: 15,
                  trackThickness: (width * 0.4).clamp(12.0, 24.0),
                  thumbLength: (width * 0.75).clamp(24.0, 44.0),
                  semanticLabel: semanticLabel,
                  semanticFormatterCallback: semantics,
                  onChanged: (v) => onChanged(_snap(v, 0.5)),
                ),
        ),
        SizedBox(height: tokens.gapSm),
        SizedBox(
          height: 20,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              hz,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A labelled slider row with its live value in a tonal badge.
class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
    this.icon,
    this.subtitle,
    this.centered = false,
    this.signed = true,
    this.indented = false,
    this.last = false,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final double value, min, max, step;
  final String unit;
  final bool centered, signed;

  /// Aligns an icon-less sub-setting with the text of the rows above it.
  final bool indented;

  /// Ends a Mornye group, which separates rows with hairlines.
  final bool last;
  final ValueChanged<double> onChanged;

  String _format(double v) {
    final digits = step < 1 ? 1 : 0;
    final text = signed && v > 0
        ? '+${v.toStringAsFixed(digits)}'
        : v.toStringAsFixed(digits).replaceFirst('-', '−');
    return unit == '%' || unit.startsWith(':') ? '$text$unit' : '$text $unit';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = context.tokens;
    final mornye = context.isMornye;
    final label = _format(value);
    final valueStyle = theme.textTheme.labelLarge?.copyWith(
      color: colors.onSecondaryContainer,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.rowPaddingH + (indented && !mornye ? 24 + tokens.rowIconGap : 0),
        tokens.rowPaddingVCompact,
        tokens.rowPaddingH,
        mornye ? 0 : tokens.gapXs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Mornye rows, like iOS Settings, carry no leading glyphs.
              if (icon != null && !mornye) ...[
                AppIcon.adaptive(
                  icon!,
                  color: colors.onSurfaceVariant,
                  size: 24,
                ),
                SizedBox(width: tokens.rowIconGap),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: tokens.gapSm),
              if (mornye)
                // iOS detail text: the value in secondary label color.
                Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              else
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: colors.secondaryContainer,
                    shape: const StadiumBorder(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Text(label, style: valueStyle),
                  ),
                ),
            ],
          ),
          if (mornye)
            MornyeLevelSlider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              origin: centered ? (min + max) / 2 : null,
              step: step,
              semanticLabel: title,
              semanticFormatterCallback: _format,
              onChanged: (v) => onChanged(_snap(v, step).clamp(min, max)),
            )
          else
            AppSlider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              centered: centered,
              semanticLabel: title,
              semanticFormatterCallback: _format,
              onChanged: (v) => onChanged(_snap(v, step).clamp(min, max)),
            ),
        ],
      ),
    );
    return SettingsSearchTarget(
      label: title,
      child: mornye && !last
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                content,
                Divider(
                  height: 1,
                  indent: tokens.rowPaddingH,
                  endIndent: tokens.rowPaddingH,
                  color: colors.outlineVariant,
                ),
              ],
            )
          : content,
    );
  }
}

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog();

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AppAlertDialog(
    title: Text(context.l10n.equalizerSavePreset),
    content: AppTextField(
      controller: _controller,
      label: context.l10n.equalizerPresetName,
      maxLength: 80,
      autofocus: true,
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      AppDialogAction(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.dialogCancel),
      ),
      AppDialogAction(onPressed: _submit, child: Text(context.l10n.dialogSave)),
    ],
  );
}

double _snap(double value, double step) => (value / step).round() * step;

/// Signed gain with a true minus sign, e.g. `+3.5`, `0.0`, `−2.0`.
String _signed(double value) {
  final text = value.abs().toStringAsFixed(1);
  if (text == '0.0') return text;
  return value > 0 ? '+$text' : '−$text';
}

String _frequency(double hz) => hz >= 1000
    ? '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)}k'
    : hz.toStringAsFixed(0);

class _EqualizerCurve extends CustomPainter {
  _EqualizerCurve({
    required this.settings,
    required this.color,
    required this.grid,
    required this.label,
    required this.labelStyle,
    required this.textScaler,
  });

  final EqualizerSettings settings;
  final Color color, grid, label;
  final TextStyle labelStyle;
  final TextScaler textScaler;

  static const _range = 18.0;
  static const _minHz = 20.0, _maxHz = 20000.0;

  TextPainter _text(String text) => TextPainter(
    text: TextSpan(
      text: text,
      style: labelStyle.copyWith(color: label),
    ),
    textDirection: TextDirection.ltr,
    textScaler: textScaler.clamp(maxScaleFactor: 1.3),
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final freqLabels = [
      for (final hz in const [100.0, 1000.0, 10000.0])
        (hz, _text(_frequency(hz))),
    ];
    final bottom = size.height - freqLabels.first.$2.height - 6;
    final gutter = _text('+12').width + 8;
    final plot = Rect.fromLTRB(gutter, 4, size.width, bottom);
    double x(double hz) =>
        plot.left +
        math.log(hz / _minHz) / math.log(_maxHz / _minHz) * plot.width;
    double y(double gain) =>
        plot.center.dy - gain.clamp(-_range, _range) / _range * plot.height / 2;

    final guide = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final gain in const [12.0, -12.0]) {
      canvas.drawLine(
        Offset(plot.left, y(gain)),
        Offset(plot.right, y(gain)),
        guide,
      );
    }
    for (final (hz, _) in freqLabels) {
      canvas.drawLine(
        Offset(x(hz), plot.top),
        Offset(x(hz), plot.bottom),
        guide,
      );
    }
    // Dashed 0 dB baseline.
    final baseline = Paint()
      ..color = grid
      ..strokeWidth = 1.5;
    for (var dx = plot.left; dx < plot.right; dx += 8) {
      canvas.drawLine(
        Offset(dx, plot.center.dy),
        Offset(math.min(dx + 4, plot.right), plot.center.dy),
        baseline,
      );
    }
    for (final (gain, text) in [(12.0, '+12'), (0.0, '0'), (-12.0, '−12')]) {
      final painter = _text(text);
      painter.paint(
        canvas,
        Offset(gutter - 8 - painter.width, y(gain) - painter.height / 2),
      );
    }
    for (final (hz, painter) in freqLabels) {
      painter.paint(canvas, Offset(x(hz) - painter.width / 2, bottom + 6));
    }

    final curve = settings.copyWith(gains: settings.effectiveGains);
    final points = <Offset>[Offset(plot.left, y(curve.gains.first))];
    for (var i = 0; i < curve.gains.length; i++) {
      final point = Offset(x(settings.frequencies[i]), y(curve.gains[i]));
      if (point.dx > points.last.dx + 0.5 && point.dx < plot.right - 0.5) {
        points.add(point);
      }
    }
    points.add(Offset(plot.right, y(curve.gains.last)));
    final line = _monotoneSpline(points);
    final area = Path.from(line)
      ..lineTo(plot.right, plot.center.dy)
      ..lineTo(plot.left, plot.center.dy)
      ..close();
    canvas.save();
    canvas.clipRect(plot);
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.42),
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.42),
          ],
        ).createShader(plot),
    );
    canvas.restore();
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final dot = Paint()..color = color;
    final effective = curve.gains;
    for (var i = 0; i < effective.length; i++) {
      final hz = settings.frequencies[i];
      if (hz < _minHz || hz > _maxHz) continue;
      canvas.drawCircle(
        Offset(x(hz), y(effective[i])),
        effective.length > 15 ? 2.5 : 4,
        dot,
      );
    }
  }

  /// Smooth curve through [points] that never overshoots between bands
  /// (Fritsch–Carlson monotone cubic interpolation).
  static Path _monotoneSpline(List<Offset> points) {
    final n = points.length;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (n < 3) {
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      return path;
    }
    final slopes = [
      for (var i = 0; i < n - 1; i++)
        (points[i + 1].dy - points[i].dy) / (points[i + 1].dx - points[i].dx),
    ];
    final tangents = [
      slopes.first,
      for (var i = 1; i < n - 1; i++)
        slopes[i - 1] * slopes[i] <= 0 ? 0.0 : (slopes[i - 1] + slopes[i]) / 2,
      slopes.last,
    ];
    for (var i = 0; i < n - 1; i++) {
      if (slopes[i] == 0) {
        tangents[i] = tangents[i + 1] = 0;
        continue;
      }
      final a = tangents[i] / slopes[i], b = tangents[i + 1] / slopes[i];
      final s = a * a + b * b;
      if (s > 9) {
        final t = 3 / math.sqrt(s);
        tangents[i] = t * a * slopes[i];
        tangents[i + 1] = t * b * slopes[i];
      }
    }
    for (var i = 0; i < n - 1; i++) {
      final p0 = points[i], p1 = points[i + 1];
      final h = (p1.dx - p0.dx) / 3;
      path.cubicTo(
        p0.dx + h,
        p0.dy + tangents[i] * h,
        p1.dx - h,
        p1.dy - tangents[i + 1] * h,
        p1.dx,
        p1.dy,
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(_EqualizerCurve oldDelegate) =>
      oldDelegate.settings != settings ||
      oldDelegate.color != color ||
      oldDelegate.grid != grid ||
      oldDelegate.label != label ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.textScaler != textScaler;
}

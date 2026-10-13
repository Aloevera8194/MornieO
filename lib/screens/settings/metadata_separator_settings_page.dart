import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/metadata_separators.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/app_icon.dart';
import 'package:spotiflac_android/widgets/expressive_button.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';

class MetadataSeparatorSettingsPage extends ConsumerWidget {
  const MetadataSeparatorSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final separators = ref.watch(
      settingsProvider.select((s) => s.metadataSeparators),
    );
    final labels = {
      'artist': context.l10n.trackArtist,
      'album_artist': context.l10n.trackAlbumArtist,
      'composer': context.l10n.editMetadataFieldComposer,
      'genre': context.l10n.trackGenre,
    };
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: context.l10n.metadataSeparators),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Text(context.l10n.metadataSeparatorsDescription),
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                for (final field in MetadataSeparators.fields)
                  SettingsItem(
                    icon: field == 'genre'
                        ? Icons.category_outlined
                        : Icons.people_alt_outlined,
                    title: labels[field]!,
                    subtitle: separators.toJson()[field]!.isEmpty
                        ? context.l10n.metadataSeparatorSource
                        : formatMetadataTagValue(
                            '${labels[field]} A, ${labels[field]} B',
                            separators.toJson()[field]!,
                          ),
                    onTap: () async {
                      final value = await showAppModalBottomSheet<String>(
                        context: context,
                        useRootNavigator: true,
                        isScrollControlled: true,
                        builder: (_) => _SeparatorPicker(
                          label: labels[field]!,
                          current: separators.toJson()[field]!,
                        ),
                      );
                      if (value != null && context.mounted) {
                        ref
                            .read(settingsProvider.notifier)
                            .setMetadataSeparator(field, value);
                      }
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeparatorPicker extends StatefulWidget {
  const _SeparatorPicker({required this.label, required this.current});
  final String label;
  final String current;

  @override
  State<_SeparatorPicker> createState() => _SeparatorPickerState();
}

class _SeparatorPickerState extends State<_SeparatorPicker> {
  static const _presets = ['', ', ', '; ', ' / '];
  late String? _selected = _presets.contains(widget.current)
      ? widget.current
      : null;
  late final _custom = TextEditingController(
    text: _selected == null ? widget.current : '',
  );

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.l10n.metadataSeparatorSource,
      context.l10n.metadataSeparatorComma,
      context.l10n.metadataSeparatorSemicolon,
      context.l10n.metadataSeparatorSlash,
      context.l10n.metadataSeparatorCustom,
    ];
    final separator = _selected ?? _custom.text;
    final valid =
        _selected != null ||
        (separator.isNotEmpty &&
            MetadataSeparators.validSeparator(separator) == separator);
    final example = '${widget.label} A, ${widget.label} B';
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (var i = 0; i < labels.length; i++)
                AppSheetOption(
                  title: Text(labels[i]),
                  trailing:
                      (_selected == (i < _presets.length ? _presets[i] : null))
                      ? const AppIcon(Icons.check)
                      : null,
                  onTap: () => setState(() {
                    _selected = i < _presets.length ? _presets[i] : null;
                  }),
                ),
              if (_selected == null)
                TextField(
                  controller: _custom,
                  maxLength: 16,
                  decoration: InputDecoration(
                    labelText: context.l10n.metadataSeparatorCustom,
                    errorText: valid || separator.isEmpty
                        ? null
                        : context.l10n.metadataSeparatorInvalid,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              const SizedBox(height: 16),
              Text(
                context.l10n.metadataSeparatorPreview,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(formatMetadataTagValue(example, valid ? separator : '')),
              const SizedBox(height: 24),
              ExpressiveButton(
                onPressed: valid
                    ? () => Navigator.of(context).pop(separator)
                    : null,
                child: Text(context.l10n.dialogSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

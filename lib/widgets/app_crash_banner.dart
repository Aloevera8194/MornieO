import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/app_crash_report.dart';
import 'package:spotiflac_android/providers/app_crash_provider.dart';
import 'package:spotiflac_android/widgets/app_content_card.dart';
import 'package:spotiflac_android/widgets/expressive_button.dart';

class AppCrashBanner extends ConsumerWidget {
  const AppCrashBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crash = ref.watch(appCrashProvider).value;
    if (crash == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: AppContentCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.appCrashTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(l10n.appCrashMessage),
              const SizedBox(height: 8),
              Text(
                crash.description.isEmpty ? crash.reason : crash.description,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(l10n.appCrashDetails),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      child: SelectableText(crash.report),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ExpressiveButton(
                    tonal: true,
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => _copy(context, crash),
                    child: Text(l10n.appCrashCopy),
                  ),
                  ExpressiveButton(
                    text: true,
                    onPressed: () async {
                      try {
                        await ref
                            .read(appCrashProvider.notifier)
                            .dismiss(crash.id);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.appCrashDismissFailed)),
                          );
                        }
                      }
                    },
                    child: Text(l10n.appCrashDismiss),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, AppCrashReport crash) async {
    final l10n = context.l10n;
    try {
      await Clipboard.setData(ClipboardData(text: crash.report));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.logCopied)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.appCrashCopyFailed)));
      }
    }
  }
}

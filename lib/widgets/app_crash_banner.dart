import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/app_crash_report.dart';
import 'package:spotiflac_android/providers/app_crash_provider.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/app_content_card.dart';
import 'package:spotiflac_android/widgets/expressive_button.dart';

/// Home notice for a crash saved by the previous session. Styled like
/// `ErrorCard`; the full report opens in a sheet instead of expanding inline,
/// so Home never nests a second scroll area.
class AppCrashBanner extends ConsumerWidget {
  const AppCrashBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crash = ref.watch(appCrashProvider).value;
    if (crash == null) return const SizedBox.shrink();
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final inset = 16 + wideListInset(context);
    return Padding(
      // Aligned with the Home search bar, including the tablet inset.
      padding: EdgeInsets.fromLTRB(inset, 8, inset, 16),
      child: AppContentCard(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colorScheme.errorContainer.withValues(alpha: 0.5),
        mornyeSurface: false,
        shape: RoundedRectangleBorder(borderRadius: tokens.borderRadiusCard),
        child: Padding(
          padding: EdgeInsets.all(tokens.gapLg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: colorScheme.error),
              SizedBox(width: tokens.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.appCrashTitle,
                      style: TextStyle(
                        color: colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: tokens.gapXs),
                    Text(
                      l10n.appCrashMessage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                    SizedBox(height: tokens.gapSm),
                    Text(
                      crash.description.isEmpty
                          ? crash.reason
                          : crash.description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
                    ),
                    SizedBox(height: tokens.gapMd),
                    Wrap(
                      spacing: tokens.gapSm,
                      runSpacing: tokens.gapSm,
                      children: [
                        ExpressiveButton(
                          tonal: true,
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => _copy(context, crash),
                          child: Text(l10n.appCrashCopy),
                        ),
                        ExpressiveButton(
                          text: true,
                          onPressed: () => _showReport(context, crash),
                          child: Text(l10n.appCrashDetails),
                        ),
                        ExpressiveButton(
                          text: true,
                          onPressed: () => _dismiss(context, ref, crash),
                          child: Text(l10n.appCrashDismiss),
                        ),
                      ],
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

  void _showReport(BuildContext context, AppCrashReport crash) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    showAppScrollableBottomSheet<void>(
      context: context,
      title: context.l10n.appCrashDetails,
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          tokens.gapXl,
          tokens.gapSm,
          tokens.gapXl,
          tokens.gapXl,
        ),
        // Same monospace treatment as the log viewer.
        child: SelectableText(
          crash.report,
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            color: colorScheme.onSurface,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Future<void> _dismiss(
    BuildContext context,
    WidgetRef ref,
    AppCrashReport crash,
  ) async {
    try {
      await ref.read(appCrashProvider.notifier).dismiss(crash.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.appCrashDismissFailed)),
        );
      }
    }
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

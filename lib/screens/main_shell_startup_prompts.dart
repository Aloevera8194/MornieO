part of 'main_shell.dart';

extension _MainShellStartupPrompts on _MainShellState {
  Future<void> _repairSafAccessIfNeeded({bool knownLost = false}) async {
    if (!Platform.isAndroid || _safRepairDialogVisible) return;

    var accessLost = knownLost;
    if (!accessLost) {
      final settings = ref.read(settingsProvider);
      if (settings.storageMode != 'saf' || settings.downloadTreeUri.isEmpty) {
        return;
      }
      accessLost = !await PlatformBridge.isSafTreeAccessible(
        settings.downloadTreeUri,
      );
    }
    if (!accessLost || !mounted) return;

    _safRepairDialogVisible = true;
    try {
      await showAppDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var isPickingFolder = false;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return PopScope(
                canPop: false,
                child: AppAlertDialog(
                  icon: AppIcon(
                    Icons.folder_off_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(context.l10n.downloadFolderAccessLostTitle),
                  content: Text(context.l10n.downloadFolderAccessLostSubtitle),
                  actions: [
                    AppDialogAction(
                      onPressed: isPickingFolder
                          ? null
                          : () {
                              final notifier = ref.read(
                                settingsProvider.notifier,
                              );
                              notifier.setStorageMode('app');
                              notifier.setDownloadTreeUri('');
                              notifier.setDownloadDirectory('');
                              Navigator.of(dialogContext).pop();
                            },
                      child: Text(context.l10n.storageAutomaticFolder),
                    ),
                    AppDialogAction(
                      filled: true,
                      onPressed: isPickingFolder
                          ? null
                          : () async {
                              setDialogState(() => isPickingFolder = true);
                              try {
                                final result =
                                    await PlatformBridge.pickSafTree();
                                if (result == null) return;
                                final treeUri =
                                    result['tree_uri'] as String? ?? '';
                                final displayName =
                                    result['display_name'] as String? ?? '';
                                if (treeUri.isEmpty) return;

                                final notifier = ref.read(
                                  settingsProvider.notifier,
                                );
                                notifier.setStorageMode('saf');
                                notifier.setDownloadTreeUri(
                                  treeUri,
                                  displayName: displayName.isNotEmpty
                                      ? displayName
                                      : treeUri,
                                );
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                              } catch (e) {
                                _log.w(
                                  'Failed to repair SAF access from startup: $e',
                                );
                                if (context.mounted) {
                                  showCannotOpenFileSnackBar(context, e);
                                }
                              } finally {
                                if (dialogContext.mounted) {
                                  setDialogState(() => isPickingFolder = false);
                                }
                              }
                            },
                      child: isPickingFolder
                          ? const AppLoadingIndicator(size: 18, strokeWidth: 2)
                          : Text(context.l10n.downloadFolderReselect),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      _safRepairDialogVisible = false;
    }
  }

  Future<void> _checkUpgradeIntro() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      final existingInstallation = !ref
          .read(initialSettingsProvider)
          .isFirstLaunch;
      if (UpgradeIntroService.shouldShow(
        preferences,
        version: AppInfo.version,
        existingInstallation: existingInstallation,
      )) {
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute(
            builder: (_) => const UpgradeIntroScreen(),
            fullscreenDialog: true,
          ),
        );
        await UpgradeIntroService.markSeen(preferences);
      } else if (!existingInstallation) {
        // Fresh installs already have their own setup tutorial.
        await UpgradeIntroService.markSeen(preferences);
      }
    } catch (error) {
      _log.w('Could not present upgrade introduction: $error');
    }
  }

  Future<bool> _checkForUpdates() async {
    if (_hasCheckedUpdate) return false;
    _hasCheckedUpdate = true;

    final settings = ref.read(settingsProvider);

    // The check runs even when the user disabled update prompts: versions
    // that fall forceUpdateThreshold stable releases behind must update, and
    // that enforcement cannot be opted out of.
    final updateInfo = await UpdateChecker().checkForUpdate(
      channel: settings.updateChannel,
    );
    if (updateInfo == null || !mounted) return false;

    final forced =
        updateInfo.releasesBehind >= UpdateChecker.forceUpdateThreshold;
    if (!forced && !settings.checkForUpdates) return false;

    showUpdateDialog(
      context,
      updateInfo: updateInfo,
      forced: forced,
      onDisableUpdates: () {
        ref.read(settingsProvider.notifier).setCheckForUpdates(false);
      },
    );
    return true;
  }

  Future<void> _checkAppAnnouncement() async {
    if (_hasCheckedAppAnnouncement) return;
    _hasCheckedAppAnnouncement = true;

    final locale = Localizations.localeOf(context).toLanguageTag();
    final remoteConfigService = AppRemoteConfigService();
    final announcement = await remoteConfigService.fetchActiveAnnouncement(
      locale: locale,
    );
    if (announcement == null || !mounted) return;

    showAppAnnouncementDialog(
      context,
      announcement: announcement,
      onDismiss: () {
        remoteConfigService.markAnnouncementDismissed(announcement.id);
      },
    );
  }

  static const _safMigrationShownKey = 'saf_migration_prompt_shown';

  Future<void> _checkSafMigration() async {
    if (!Platform.isAndroid) return;

    final settings = ref.read(settingsProvider);
    if (settings.storageMode == 'saf') return;
    if (settings.downloadDirectory.isEmpty) return;

    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    if (androidInfo.version.sdkInt < 29) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_safMigrationShownKey) == true) return;
    await prefs.setBool(_safMigrationShownKey, true);

    if (!mounted) return;

    final colorScheme = Theme.of(context).colorScheme;

    showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppAlertDialog(
        icon: AppIcon(
          Icons.folder_special_outlined,
          size: 32,
          color: colorScheme.primary,
        ),
        title: Text(context.l10n.safMigrationTitle),
        content: ConstrainedBox(
          // Keeps the text column readable on tablets/landscape.
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.safMigrationMessage1),
              const SizedBox(height: 12),
              Text(context.l10n.safMigrationMessage2),
            ],
          ),
        ),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.updateLater),
          ),
          AppDialogAction(
            filled: true,
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await PlatformBridge.pickSafTree();
              if (result != null) {
                final treeUri = result['tree_uri'] as String? ?? '';
                final displayName = result['display_name'] as String? ?? '';
                if (treeUri.isNotEmpty) {
                  ref
                      .read(settingsProvider.notifier)
                      .setDownloadTreeUri(
                        treeUri,
                        displayName: displayName.isNotEmpty
                            ? displayName
                            : treeUri,
                      );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.safMigrationSuccess)),
                    );
                  }
                }
              }
            },
            child: Text(context.l10n.setupSelectFolder),
          ),
        ],
      ),
    );
  }
}

part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;
  CancelToken? _updateCancelToken;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
    if (running && ref.read(coreStatusProvider) == CoreStatus.disconnected) {
      ref.read(setupActionProvider.notifier).resumeOnRestart();
      unawaited(
        globalState.safeRun(ref.read(coreActionProvider.notifier).restartCore),
      );
      return;
    }
    unawaited(
      globalState.safeRun(
        () => ref
            .read(setupActionProvider.notifier)
            .setRunning(
              running,
              initialize: running && !ref.read(initProvider),
            ),
      ),
    );
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMonochromeTrayIcon() {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(monochromeTrayIcon: !state.monochromeTrayIcon),
        );
  }

  void updateMode() {
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  Future<void> updateTraffic() async {
    if (_isUpdatingTraffic) {
      return;
    }
    _isUpdatingTraffic = true;
    try {
      final onlyStatisticsProxy = ref.read(
        appSettingProvider.select((state) => state.onlyStatisticsProxy),
      );
      final [traffic, totalTraffic] = await Future.wait([
        _readTraffic(() => _core.getTraffic(onlyStatisticsProxy)),
        _readTraffic(() => _core.getTotalTraffic(onlyStatisticsProxy)),
      ]);
      if (traffic != null) {
        ref.read(trafficsProvider.notifier).addTraffic(traffic);
      }
      if (totalTraffic != null) {
        ref.read(totalTrafficProvider.notifier).value = totalTraffic;
      }
    } finally {
      _isUpdatingTraffic = false;
    }
  }

  Future<Traffic?> _readTraffic(Future<Traffic> Function() request) async {
    try {
      return await request();
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  Future<bool> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return false;
    final Map<String, dynamic>? res;
    try {
      res = await request.checkForUpdate();
    } catch (error) {
      commonPrint.log(
        'checkForUpdate failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
    await checkUpdateResultHandle(data: res);
    return res != null;
  }

  /// NekoVPN's signed remote settings (lib/neko/remote_settings.dart): keeps
  /// a newer document, then asks for an update or shows the message.
  Future<void> checkNekoSettings() async {
    final kept = await NekoSettingsStore.current();
    if (kept != null) await applyNekoBypass(kept.bypassApps);
    final settings = await nekoRefreshSettings(
      get: (url) => nekoGetJson(request.dio, url),
    );
    if (settings == null) return;
    if (settings.version != kept?.version) {
      await applyNekoBypass(settings.bypassApps);
    }
    final installed = globalState.packageInfo.version;
    if (nekoUpdateRequired(settings, installed: installed)) {
      final update = await dialogs.showMessage(
        title: nekoUpdateTitle,
        message: TextSpan(text: nekoUpdateText),
        confirmText: currentAppLocalizations.goDownload,
      );
      if (update == true) unawaited(launchUrl(Uri.parse(nekoReleasesUrl)));
    }
    final message = await nekoMessageToShow(settings);
    if (message == null) return;
    final url = message.url;
    if (url == null) {
      await dialogs.showAlert(
        title: appName,
        message: TextSpan(text: message.text),
      );
    } else {
      final open = await dialogs.showMessage(
        title: appName,
        message: TextSpan(text: message.text),
        confirmText: nekoOpenLink,
      );
      if (open == true) unawaited(launchUrl(Uri.parse(url)));
    }
    await NekoSettingsStore.markShown(message.id);
  }

  /// NekoVPN locks the local proxy against other apps, once per install
  /// (lib/neko/secure_proxy.dart).
  Future<void> secureNekoProxy() async {
    await nekoApplySecureProxy(
      android: system.isAndroid,
      read: () => (
        vpn: ref.read(vpnSettingProvider),
        network: ref.read(networkSettingProvider),
      ),
      write: (settings) {
        ref.read(vpnSettingProvider.notifier).value = settings.vpn;
        ref.read(networkSettingProvider.notifier).value = settings.network;
      },
    );
  }

  Future<void> applyNekoBypass(List<String> list) async {
    if (!system.isAndroid) return;
    await nekoApplyBypass(
      list: list,
      read: () => ref.read(vpnSettingProvider).accessControlProps,
      write: (access) => ref
          .read(vpnSettingProvider.notifier)
          .update((state) => state.copyWith(accessControlProps: access)),
    );
  }

  TextSpan _releaseSpan(BuildContext context, String tagName, String? body) {
    final version = parseReleaseChangelog(body);
    return TextSpan(
      text: '$tagName \n',
      style: AppTextStyle.title2.of(context),
      children: version == null
          ? [
              TextSpan(text: '\n', style: AppTextStyle.subheadline.of(context)),
              for (final submit in parseReleaseBody(body))
                TextSpan(
                  text: '- $submit \n',
                  style: AppTextStyle.subheadline.of(context),
                ),
            ]
          : _changelogSpans(context, version),
    );
  }

  List<TextSpan> _changelogSpans(
    BuildContext context,
    ChangelogVersion version,
  ) {
    return [
      for (final group in version.visibleGroups) ...[
        TextSpan(
          text:
              '\n${changelogGroupTitle(currentAppLocalizations, group.type)}\n',
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(
                color: group.type == ChangelogType.breaking
                    ? context.colorScheme.error
                    : context.colorScheme.primary,
              ),
        ),
        for (final entry in group.entries)
          TextSpan(
            text: '• ${entry.text}\n',
            style: AppTextStyle.subheadline.of(context),
          ),
      ],
    ];
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (data != null) {
      final context = globalState.navigatorKey.currentContext!;
      final tag = data['tag_name'] as String;
      final asset = selfUpdateAsset;
      final res = await dialogs.showMessage(
        title: currentAppLocalizations.discoverNewVersion,
        message: _releaseSpan(context, tag, data['body'] as String?),
        confirmText: asset == null
            ? currentAppLocalizations.goDownload
            : currentAppLocalizations.update,
        cancelText: isUser ? null : currentAppLocalizations.noLongerRemind,
      );
      if (res == true) {
        if (asset == null) {
          unawaited(launchUrl(Uri.parse(nekoReleasePageUrl(data))));
        } else {
          unawaited(_downloadUpdate(tag, updateAssetName(tag, asset)));
        }
      } else if (!isUser && res == false) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: false));
      }
    } else if (isUser) {
      unawaited(
        dialogs.showAlert(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(text: currentAppLocalizations.checkUpdateError),
        ),
      );
    }
  }

  void _openReleasePage() {
    // NekoVPN: /releases/latest never shows a test build.
    unawaited(launchUrl(Uri.parse(nekoReleasesUrl)));
  }

  /// Downloads the latest release for this build even when it is not newer.
  Future<void> testUpdateDownload() async {
    final asset = selfUpdateAsset;
    if (asset == null || ref.read(updateDownloadStateProvider) != null) {
      return;
    }
    final release = await globalState.loadingRun(
      request.latestRelease,
      title: currentAppLocalizations.updateDownloadTest,
      tag: LoadingTag.checkUpdate,
    );
    if (release == null) return;
    final tag = release['tag_name'] as String;
    await _downloadUpdate(tag, updateAssetName(tag, asset));
  }

  Future<void> _downloadUpdate(String tag, String name) async {
    final download = ref.read(updateDownloadStateProvider.notifier);
    if (download.value != null) return;
    final cancelToken = CancelToken();
    _updateCancelToken = cancelToken;
    download.value = UpdateDownloading(tag);
    dialogs.showBanner(currentAppLocalizations.updateDownloadStarted);
    try {
      final directory = await appPath.updateDirPath;
      await clearUpdateDownloads();
      await Directory(directory).create(recursive: true);
      var shown = 0;
      final path = await request.downloadVerifiedRelease(
        tag: tag,
        name: name,
        directory: directory,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          // Every chunk would otherwise rebuild the status on its own frame.
          final step = total > 0 ? total / 100 : 1 << 20;
          if (received - shown < step && received != total) return;
          shown = received;
          download.value = UpdateDownloading(
            tag,
            received: received,
            total: total,
          );
        },
      );
      download.value = UpdateReady(tag, path);
      dialogs.showBanner(
        currentAppLocalizations.updateReadyTip,
        level: BannerLevel.success,
        onTap: () => unawaited(installUpdate()),
      );
    } catch (error) {
      download.value = null;
      await clearUpdateDownloads();
      if (error is DioException && CancelToken.isCancel(error)) {
        return;
      }
      commonPrint.log(
        'Update download failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      await _showUpdateFailure(
        userFacingErrorMessage(error, currentAppLocalizations),
      );
    } finally {
      if (identical(_updateCancelToken, cancelToken)) {
        _updateCancelToken = null;
      }
    }
  }

  void cancelUpdateDownload() {
    _updateCancelToken?.cancel();
  }

  Future<void> discardUpdate() async {
    if (ref.read(updateDownloadStateProvider) is! UpdateReady) return;
    ref.read(updateDownloadStateProvider.notifier).value = null;
    await clearUpdateDownloads();
  }

  Future<void> installUpdate() async {
    final download = ref.read(updateDownloadStateProvider);
    if (download is! UpdateReady) return;
    if (system.isAndroid) {
      ref.read(updateDownloadStateProvider.notifier).value = null;
      final status = await app?.installPackage(download.path);
      await clearUpdateDownloads();
      if (status != null && packageInstallFailed(status)) {
        await _showUpdateFailure(currentAppLocalizations.updateInstallFailed);
      }
      return;
    }
    final started = windows?.runas(download.path, windowsUpdateArguments(pid));
    if (started == true) {
      await ref.read(systemActionProvider.notifier).handleExit();
    } else if (started == false) {
      await _showUpdateFailure(currentAppLocalizations.updateInstallFailed);
    }
  }

  Future<void> _showUpdateFailure(String message) async {
    final res = await dialogs.showMessage(
      title: currentAppLocalizations.updateFailed,
      message: TextSpan(text: message),
      confirmText: currentAppLocalizations.goDownload,
    );
    if (res == true) {
      _openReleasePage();
    }
  }
}

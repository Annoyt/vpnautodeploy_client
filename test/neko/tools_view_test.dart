import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/tools_view.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/navigation.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/app_paths.dart';
import 'neko_ui.dart';

void _expectTexts(List<String> texts, Matcher matcher) {
  for (final text in texts) {
    expect(find.text(text), matcher, reason: text);
  }
}

void main() {
  setUpAll(() async {
    final home = await Directory.systemTemp.createTemp('neko_settings_view');
    addTearDown(() => home.deleteSync(recursive: true));
    await useAppPaths(home);
  });

  setUp(() {
    navigationPort = navigation;
    addTearDown(() => navigationPort = null);
  });

  testWidgets('simple Settings: the basics, help and the switch', (
    tester,
  ) async {
    useNekoLayout();
    final app = NekoTestApp();
    await app.pump(tester, const ToolsView());
    final l10n = currentAppLocalizations;
    expect(find.text(nekoSettingsTitle), findsWidgets);
    expect(find.byType(NekoBypassAppsItem), findsOneWidget);
    expect(find.byType(NekoAboutItem), findsOneWidget);
    expect(find.byType(NekoAdvancedModeItem), findsOneWidget);
    _expectTexts([
      nekoBasicSection,
      l10n.language,
      l10n.theme,
      nekoBypassApps,
      nekoBypassAppsSubtitle,
      l10n.autoRun,
      l10n.autoCheckUpdate,
      l10n.showNotificationStopAction,
      nekoHelpSection,
      l10n.about,
      nekoAboutSubtitle,
      nekoExpertSection,
      nekoAdvancedMode,
    ], findsOneWidget);
    _expectTexts([
      nekoNetstatSection,
      nekoSosTitle,
      nekoNetworkMemoryTitle,
      l10n.general,
      l10n.backupAndRestore,
      l10n.accessControl,
      l10n.disclaimer,
    ], findsNothing);
  });

  testWidgets('advanced Settings: everything FlClash has comes back', (
    tester,
  ) async {
    useNekoLayout();
    final app = NekoTestApp(advanced: true);
    await app.pump(tester, const ToolsView(), size: const Size(400, 3600));
    final l10n = currentAppLocalizations;
    _expectTexts([
      nekoNetstatSection,
      nekoNetstatTitle,
      nekoAdvancedMode,
      nekoNetworkMemoryTitle,
      nekoMultipathTitle,
      nekoGatewayTitle,
      l10n.general,
      l10n.advancedConfig,
      l10n.customProfileResources,
      l10n.backupAndRestore,
      PageLabel.requests.label,
      PageLabel.connections.label,
      l10n.disclaimer,
    ], findsOneWidget);
    _expectTexts([nekoSosTitle, l10n.accessControl], findsNothing);
  });

  testWidgets('the switch keeps the view and brings back the tabs', (
    tester,
  ) async {
    useNekoLayout();
    final app = NekoTestApp(
      profiles: [Profile.normal(url: 'https://neko.example/sub')],
    );
    await app.pump(tester, const ToolsView(), size: const Size(400, 2800));
    List<PageLabel> tabs() => [
      for (final item
          in app.container.read(currentNavigationItemsStateProvider).value)
        item.label,
    ];
    final l10n = currentAppLocalizations;
    expect(tabs(), [PageLabel.dashboard, PageLabel.tools]);
    expect(find.text(l10n.general), findsNothing);

    await tester.tap(find.text(nekoAdvancedMode));
    await tester.pumpAndSettle();
    expect(app.saved, [true]);
    expect(tabs(), [
      PageLabel.dashboard,
      PageLabel.proxies,
      PageLabel.profiles,
      PageLabel.tools,
    ]);
    expect(find.text(l10n.general), findsOneWidget);

    await tester.tap(find.text(nekoAdvancedMode));
    await tester.pumpAndSettle();
    expect(app.saved, [true, false]);
    expect(tabs(), [PageLabel.dashboard, PageLabel.tools]);
  });
}

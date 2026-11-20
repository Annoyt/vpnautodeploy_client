import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/layout.dart';
import 'package:fl_clash/neko/view_mode.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_profiles.dart';
import 'neko_ui.dart';

NavigationItem _item(PageLabel label) => NavigationItem(
  glyph: AppGlyphs.dashboard,
  label: label,
  builder: (_) => const SizedBox.shrink(),
);

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('neko_view');
    await useAppPaths(home);
  });

  tearDown(() => home.delete(recursive: true));

  group('the stored view', () {
    test('simple until switched, and the switch is kept', () async {
      expect(await NekoViewStore.advanced(), isFalse);
      await NekoViewStore.setAdvanced(true);
      expect(await NekoViewStore.advanced(), isTrue);
      await NekoViewStore.setAdvanced(false);
      expect(await NekoViewStore.advanced(), isFalse);
    });

    test('a broken file is the simple view', () async {
      await File(join(home.path, nekoViewFile)).writeAsString('{not json');
      expect(await NekoViewStore.advanced(), isFalse);
      await File(join(home.path, nekoViewFile)).writeAsString('[true]');
      expect(await NekoViewStore.advanced(), isFalse);
    });

    test('a write that fails only logs', () async {
      await Directory(join(home.path, nekoViewFile)).create();
      await NekoViewStore.setAdvanced(true);
      expect(await NekoViewStore.advanced(), isFalse);
    });

    test('the switch writes the file by default', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(nekoAdvancedProvider), isFalse);
      await container.read(nekoAdvancedProvider.notifier).set(true);
      expect(container.read(nekoAdvancedProvider), isTrue);
      expect(await NekoViewStore.advanced(), isTrue);
    });
  });

  group('the view', () {
    test('FlClash keeps its own view off NekoVPN layout', () {
      debugNekoLayout = false;
      addTearDown(() => debugNekoLayout = null);
      final container = ProviderContainer(
        overrides: [nekoAdvancedProvider.overrideWithBuild((_, _) => true)],
      );
      addTearDown(container.dispose);
      expect(container.read(nekoViewProvider), NekoView.flclash);
      expect(nekoPageLabel(PageLabel.dashboard), isNull);
    });

    test('NekoVPN layout: simple, then advanced', () async {
      useNekoLayout();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(nekoViewProvider), NekoView.simple);
      await container.read(nekoAdvancedProvider.notifier).set(true);
      expect(container.read(nekoViewProvider), NekoView.advanced);
    });

    test('the tabs are named Home and Settings', () {
      useNekoLayout();
      Intl.withLocale('ru', () {
        expect(nekoPageLabel(PageLabel.dashboard), 'Главная');
        expect(nekoPageLabel(PageLabel.tools), 'Настройки');
        expect(PageLabel.tools.label, 'Настройки');
      });
      expect(nekoPageLabel(PageLabel.profiles), isNull);
    });

    test('the simple view keeps Home and Settings only', () {
      final items = [
        for (final label in [
          PageLabel.dashboard,
          PageLabel.proxies,
          PageLabel.profiles,
          PageLabel.logs,
          PageLabel.tools,
        ])
          _item(label),
      ];
      List<PageLabel> labels(NekoView view) => [
        for (final item in nekoNavigationItems(items, view)) item.label,
      ];
      expect(labels(NekoView.simple), [PageLabel.dashboard, PageLabel.tools]);
      expect(labels(NekoView.advanced), hasLength(5));
      expect(labels(NekoView.flclash), hasLength(5));
    });
  });

  test('the app tabs follow the switch', () async {
    useNekoLayout();
    navigationPort = navigation;
    addTearDown(() => navigationPort = null);
    final saved = <bool>[];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(
          () => TestProfiles([Profile.normal(url: 'https://neko.example/sub')]),
        ),
        nekoAdvancedProvider.overrideWith(
          () => NekoAdvancedMode(save: (advanced) async => saved.add(advanced)),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(viewSizeProvider.notifier).value = const Size(400, 800);
    List<PageLabel> tabs() => [
      for (final item
          in container.read(currentNavigationItemsStateProvider).value)
        item.label,
    ];
    expect(tabs(), [PageLabel.dashboard, PageLabel.tools]);
    await container.read(nekoAdvancedProvider.notifier).set(true);
    expect(tabs(), [
      PageLabel.dashboard,
      PageLabel.proxies,
      PageLabel.profiles,
      PageLabel.tools,
    ]);
    expect(saved, [true]);
  });
}

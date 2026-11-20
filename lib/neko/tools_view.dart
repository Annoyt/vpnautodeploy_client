import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/about.dart';
import 'package:fl_clash/views/access.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'gateway_view.dart';
import 'multipath.dart';
import 'netstat_view.dart';
import 'network_memory_manager.dart';
import 'view_mode.dart';

/// Settings on NekoVPN's layout: the basics and help, then for experts the
/// switch to the advanced view, which brings back [expert], all of FlClash's.
List<Widget> nekoSettingsSections({
  required bool advanced,
  required List<Widget> basic,
  required List<Widget> expert,
}) {
  return [
    if (advanced)
      generateSection(
        title: nekoNetstatSection,
        items: const [NekoNetstatItem()],
        footer: nekoNetstatFooter,
      ),
    generateSection(
      title: nekoBasicSection,
      items: [...basic, const NekoBypassAppsItem(), ..._startupItems()],
    ),
    generateSection(title: nekoHelpSection, items: const [NekoAboutItem()]),
    generateSection(
      title: nekoExpertSection,
      items: const [NekoAdvancedModeItem()],
    ),
    if (advanced) ...[
      generateSection(
        items: const [
          NekoNetworkMemoryItem(),
          NekoMultipathItem(),
          NekoGatewayItem(),
        ],
        footer: nekoMultipathFooter,
      ),
      ...expert,
    ],
  ];
}

ConfigToggleItem _appToggle({
  required ConfigLabel title,
  required bool Function(AppSettingProps state) select,
  required AppSettingProps Function(AppSettingProps state, bool value) update,
}) {
  return ConfigToggleItem(
    title: title,
    selector: appSettingProvider.select(select),
    onChanged: (ref, value) => ref
        .read(appSettingProvider.notifier)
        .update((state) => update(state, value)),
  );
}

List<Widget> _startupItems() => [
  _appToggle(
    title: (l) => l.autoRun,
    select: (state) => state.autoRun,
    update: (state, value) => state.copyWith(autoRun: value),
  ),
  _appToggle(
    title: (l) => l.autoCheckUpdate,
    select: (state) => state.autoCheckUpdate,
    update: (state, value) => state.copyWith(autoCheckUpdate: value),
  ),
  _appToggle(
    title: (l) => l.showNotificationStopAction,
    select: (state) => state.showNotificationStopAction,
    update: (state, value) => state.copyWith(showNotificationStopAction: value),
  ),
];

/// Upstream's access control, named for what NekoVPN keeps there: the apps
/// of the white lists, which go around the VPN.
class NekoBypassAppsItem extends StatelessWidget {
  const NekoBypassAppsItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.appsList),
      title: Text(nekoBypassApps),
      subtitle: Text(nekoBypassAppsSubtitle),
      widget: const AccessView(),
    );
  }
}

class NekoAboutItem extends StatelessWidget {
  const NekoAboutItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.info),
      title: Text(context.appLocalizations.about),
      subtitle: Text(nekoAboutSubtitle),
      widget: const AboutView(),
    );
  }
}

class NekoAdvancedModeItem extends ConsumerWidget {
  const NekoAdvancedModeItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListItem.toggle(
      leading: const GlyphIcon(AppGlyphs.sliders),
      title: Text(nekoAdvancedMode),
      subtitle: Text(nekoAdvancedModeSubtitle),
      value: ref.watch(nekoAdvancedProvider),
      onChanged: (advanced) {
        unawaited(ref.read(nekoAdvancedProvider.notifier).set(advanced));
      },
    );
  }
}

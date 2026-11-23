import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'brand.dart';
import 'view_mode.dart';
import 'zones.dart';

/// Over the servers on NekoVPN's layout, once they are in several countries:
/// a country to go out in, or «Авто». FlClash's view gets [child] alone.
class NekoExitZoneHeader extends ConsumerWidget {
  const NekoExitZoneHeader({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled || ref.watch(nekoViewProvider) == NekoView.flclash) {
      return child;
    }
    final selection = nekoSelectionOf(
      shown: ref.watch(currentGroupsStateProvider).value,
      groups: ref.watch(groupsProvider),
      selectedMap: ref.watch(selectedMapProvider),
    );
    if (selection == null || selection.zones.length < 2) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ).copyWith(top: context.contentTopPadding),
          child: NekoExitZones(selection: selection),
        ),
        Expanded(child: TopInsetScope(inset: 16, child: child)),
      ],
    );
  }
}

/// The zone row: «Авто» picks the group that chooses by itself, a country
/// its fastest server.
class NekoExitZones extends ConsumerWidget {
  const NekoExitZones({super.key, required this.selection});

  static const _auto = '';
  static const _segmentsMax = 3;

  final NekoSelection selection;

  void _pick(WidgetRef ref, String zone) {
    final members = selection.zones[zone];
    final member = members == null
        ? selection.autoMember
        : nekoZonePick(members, ref.read(delayDataSourceProvider));
    if (member == null) return;
    ref
        .read(proxiesActionProvider.notifier)
        .changeProxyDebounce(selection.group.name, member);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = [
      if (selection.autoMember != null) _auto,
      ...selection.zones.keys,
    ];
    final value = selection.auto
        ? _auto
        : nekoCountryOf(selection.member) ?? selection.member;
    String label(String zone) => switch (zone) {
      _auto => nekoAuto,
      _ when selection.zones.containsKey(zone) => nekoCountryName(zone),
      _ => zone,
    };
    if (options.length > _segmentsMax) {
      return generateGroup([
        ListItem<String>.options(
          title: Text(nekoExitZone),
          options: options,
          value: value,
          textBuilder: label,
          onChanged: (zone) => _pick(ref, zone),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(
          nekoExitZone,
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
        SegmentedControl<String>(
          segments: [for (final zone in options) (zone, label(zone))],
          value: value,
          onChanged: (zone) => _pick(ref, zone),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:fl_clash/views/dashboard/widgets/profile_detail.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'links.dart';
import 'quota.dart';
import 'quota_view.dart';
import 'sos_view.dart';
import 'speed.dart';
import 'subscribe.dart';
import 'view_mode.dart';
import 'zones.dart';

/// The plan the bot named with the current profile's last download; null
/// for a profile that is not ours.
final nekoCurrentPlanProvider = FutureProvider.autoDispose<NekoPlan?>((
  ref,
) async {
  // Read again after each download: the plan comes with it.
  final (profileId, _) = ref.watch(
    currentProfileProvider.select(
      (profile) => (profile?.id, profile?.lastUpdateDate),
    ),
  );
  if (profileId == null) return null;
  return NekoPlanStore.of(profileId);
});

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.${date.year}';

/// What the connect card says of a subscription: the end date, the month's
/// traffic, and for our own plan a warning and the way to pay.
class NekoPlanSummary {
  const NekoPlanSummary({
    this.date,
    this.ended = false,
    this.used,
    this.total,
    this.warning,
    this.buy,
  });

  final String? date;
  final bool ended;
  final int? used;
  final int? total;
  final String? warning;
  final String? buy;

  double get share {
    final total = this.total;
    return total == null ? 0 : (used ?? 0) / total;
  }

  bool get warn => ended || share >= NekoQuota.highShare;
}

NekoPlanSummary nekoPlanSummary({
  SubscriptionInfo? info,
  NekoPlan? plan,
  required DateTime now,
}) {
  final seconds = info?.expire ?? 0;
  final expire = seconds > 0
      ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
      : null;
  final ended = expire != null && expire.isBefore(now);
  final total = info?.total ?? 0;
  final used = (info?.upload ?? 0) + (info?.download ?? 0);
  final quota = plan == null || total <= 0
      ? null
      : NekoQuota(plan: plan, used: used, total: total, expire: expire);
  final level = quota?.level;
  return NekoPlanSummary(
    date: switch (expire) {
      final end? when ended => nekoEndedOn(_date(end)),
      final end? => nekoValidUntil(_date(end)),
      null when plan?.paid == false => nekoDemo,
      null => null,
    },
    ended: ended,
    used: total > 0 ? used : null,
    total: total > 0 ? total : null,
    warning: switch (level) {
      NekoQuotaLevel.out => nekoQuotaOut,
      NekoQuotaLevel.high => nekoQuotaHigh((quota!.share * 100).floor()),
      _ => null,
    },
    buy: switch (plan) {
      NekoPlan(paid: true) when ended => nekoQuotaRenew,
      NekoPlan(paid: false) when level == NekoQuotaLevel.out => nekoQuotaBuy,
      _ => null,
    },
  );
}

/// Home in the simple view.
class NekoHomeView extends ConsumerWidget {
  const NekoHomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gap = cardSpacingOf(context, ref.watch(viewModeProvider));
    return CommonScaffold(
      backgroundColor: DashboardColors.of(context).page,
      title: PageLabel.dashboard.label,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final side = dashboardMobileSideOf(constraints.maxWidth);
          return ListView(
            padding: EdgeInsets.fromLTRB(
              side,
              context.contentTopPadding,
              side,
              16 + context.bottomInset,
            ),
            children: [
              NekoHomeHead(gap: gap),
              const NekoHomeFoot(gap: 0),
            ],
          );
        },
      ),
    );
  }
}

/// Above the dashboard's cards: the connect card, then the server card, or
/// with no subscription the ways to add one. FlClash's view keeps the quota
/// card there.
class NekoHomeHead extends ConsumerWidget {
  const NekoHomeHead({super.key, required this.gap});

  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(nekoViewProvider) == NekoView.flclash) {
      return NekoQuotaBanner(gap: gap);
    }
    final hasProfile = ref.watch(
      profilesProvider.select((profiles) => profiles.isNotEmpty),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NekoConnectCard(),
        SizedBox(height: gap),
        if (hasProfile) const NekoExitCard() else const NekoAddCard(),
        SizedBox(height: gap),
      ],
    );
  }
}

/// Under the dashboard's cards: help when it does not connect, and the
/// subscription, which opens the list of them.
class NekoHomeFoot extends ConsumerWidget {
  const NekoHomeFoot({super.key, required this.gap});

  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(nekoViewProvider) == NekoView.flclash) {
      return const SizedBox.shrink();
    }
    final profile = ref.watch(currentProfileProvider);
    return Padding(
      padding: EdgeInsets.only(top: gap),
      child: generateGroup([
        ListItem.open(
          leading: const GlyphIcon(AppGlyphs.warning),
          title: Text(nekoCannotConnect),
          subtitle: Text(nekoCannotConnectSubtitle),
          widget: const NekoSosView(),
        ),
        if (profile != null)
          ListItem.open(
            leading: const GlyphIcon(AppGlyphs.profiles),
            title: Text(nekoSubscriptionRow(profile.realLabel)),
            subtitle: Text(nekoSubscriptionRowSubtitle),
            widget: const ProfilesView(),
          ),
      ]),
    );
  }
}

/// The subscription on the left, the connect button on the right; without
/// a subscription the button is grey and asks for one.
class NekoConnectCard extends ConsumerWidget {
  const NekoConnectCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(
      profilesProvider.select((profiles) => profiles.isNotEmpty),
    );
    final profile = ref.watch(currentProfileProvider);
    final plan = profile == null
        ? null
        : ref.watch(nekoCurrentPlanProvider).value;
    final summary = nekoPlanSummary(
      info: profile?.subscriptionInfo,
      plan: plan,
      now: DateTime.now(),
    );
    final buy = summary.buy;
    return DashboardCard(
      semanticLabel: hasProfile ? nekoRefreshSubscription : nekoNoSubscription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (profile != null && profile.type == ProfileType.url) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _RefreshButton(profile: profile),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: hasProfile
                    ? _PlanSide(summary: summary)
                    : Text(
                        nekoNoSubscription,
                        style: AppTextStyle.headline.of(
                          context,
                          emphasized: true,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              _ConnectSide(hasProfile: hasProfile),
            ],
          ),
          if (buy != null) ...[
            const SizedBox(height: 16),
            TonalButton(
              size: TonalButtonSize.bar,
              glyph: AppGlyphs.openExternal,
              label: buy,
              onPressed: () => nekoOpen(ref, Uri.parse(nekoBuyUrl)),
            ),
          ],
        ],
      ),
    );
  }
}

class _RefreshButton extends ConsumerWidget {
  const _RefreshButton({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updating = ref.watch(isUpdatingProvider(profile.updatingKey));
    return TonalButton(
      size: TonalButtonSize.compact,
      glyph: AppGlyphs.sync,
      label: nekoRefreshSubscription,
      onPressed: updating ? null : () => syncProfile(ref, profile),
    );
  }
}

class _PlanSide extends StatelessWidget {
  const _PlanSide({required this.summary});

  final NekoPlanSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    final date = summary.date;
    final used = summary.used;
    final total = summary.total;
    final warning = summary.warning;
    final note = AppTextStyle.footnote.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (date != null)
          Text(
            date,
            style: AppTextStyle.subheadline
                .of(context, emphasized: true)
                .copyWith(color: summary.ended ? colors.warn : null),
          ),
        if (used != null && total != null) ...[
          const SizedBox(height: 6),
          Text(
            nekoUsedOf(dashboardTraffic(used), dashboardTraffic(total)),
            style: DashboardText.figure(context, AppTextStyle.headline),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: summary.share.clamp(0.0, 1.0),
            color: summary.warn ? colors.warn : context.colorScheme.primary,
            backgroundColor: colors.tone2,
          ),
        ],
        if (warning != null) ...[
          const SizedBox(height: 6),
          Text(warning, style: note.copyWith(color: colors.warn)),
        ],
      ],
    );
  }
}

class _ConnectSide extends ConsumerWidget {
  const _ConnectSide({required this.hasProfile});

  final bool hasProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(isStartProvider);
    final suspended = running && ref.watch(suspendProvider);
    final appLocalizations = context.appLocalizations;
    final status = !hasProfile
        ? Text(
            nekoAddSubscription,
            textAlign: TextAlign.center,
            style: DashboardText.label(context),
          )
        : DashboardChip(
            label: suspended
                ? appLocalizations.suspended
                : running
                ? appLocalizations.running
                : appLocalizations.notRunning,
            tone: suspended
                ? DashboardChipTone.warn
                : running
                ? DashboardChipTone.ok
                : DashboardChipTone.idle,
            dot: running && !suspended,
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ConnectButton(
          hasProfile: hasProfile,
          running: running,
          suspended: suspended,
        ),
        const SizedBox(height: 10),
        status,
        if (running) ...[const SizedBox(height: 4), const _RunTime()],
      ],
    );
  }
}

class _RunTime extends ConsumerWidget {
  const _RunTime();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Text(
      getTimeText(ref.watch(runTimeProvider)),
      style: DashboardText.label(context),
    );
  }
}

const _morphDuration = Duration(milliseconds: 450);

class _ConnectButton extends ConsumerWidget {
  const _ConnectButton({
    required this.hasProfile,
    required this.running,
    required this.suspended,
  });

  static const _size = 88.0;

  final bool hasProfile;
  final bool running;
  final bool suspended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    final fill = hasProfile
        ? colorScheme.primary
        : DashboardColors.of(context).tone2;
    final ink = hasProfile
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;
    final label = !hasProfile
        ? nekoAddSubscription
        : suspended
        ? appLocalizations.suspended
        : running
        ? appLocalizations.stop
        : appLocalizations.start;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: ElasticPress(
          child: Material(
            color: fill,
            shape: AppShape.full,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: AppShape.full,
              onTap: () {
                if (hasProfile) {
                  ref.read(commonActionProvider.notifier).toggleRunning();
                } else {
                  unawaited(showNekoNeedSubscription(context));
                }
              },
              child: SizedBox.square(
                dimension: _size,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: running ? 1 : 0),
                    duration: context.motionDuration(_morphDuration),
                    curve: Curves.easeOutBack,
                    builder: (_, progress, _) => GlyphIcon(
                      AppGlyphs.playPause(progress),
                      size: _size * 0.34,
                      color: ink,
                      fill: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the traffic goes out: the country, smaller, the server picked, and
/// the session's top speeds. A tap opens the server choice.
class NekoExitCard extends ConsumerStatefulWidget {
  const NekoExitCard({super.key});

  @override
  ConsumerState<NekoExitCard> createState() => _NekoExitCardState();
}

class _NekoExitCardState extends ConsumerState<NekoExitCard> {
  late final OutboundIpProbe _probe;
  var _watching = false;

  @override
  void initState() {
    super.initState();
    _probe = ref.read(outboundIpProbeProvider.notifier);
    // Only a running tunnel's exit is looked up: the lookup then goes
    // through it and never shows the phone's own address to the service.
    ref.listenManual(
      isStartProvider,
      (_, running) => _follow(running),
      fireImmediately: true,
    );
  }

  void _follow(bool running) {
    if (running == _watching) return;
    _watching = running;
    if (running) {
      _probe.watch(routedOutbound);
    } else {
      _probe.unwatch(routedOutbound);
    }
  }

  @override
  void dispose() {
    _follow(false);
    super.dispose();
  }

  void _open() {
    ref.read(proxiesActionProvider.notifier).updateGroupsDebounce();
    unawaited(BaseNavigator.push<void>(context, const ProxiesView()));
  }

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(isStartProvider);
    final exit = running
        ? ref.watch(
            outboundIpProbeProvider.select(
              (state) => state.valueOf(routedOutbound)?.countryCode,
            ),
          )
        : null;
    final selection = nekoSelectionOf(
      shown: ref.watch(currentGroupsStateProvider).value,
      groups: ref.watch(groupsProvider),
      selectedMap: ref.watch(selectedMapProvider),
    );
    final speed = ref.watch(nekoTopSpeedProvider);
    final lines = nekoExitLines(exit: exit, selection: selection);
    final colorScheme = context.colorScheme;
    final subtitle = lines.subtitle;
    return DashboardCard(
      onTap: _open,
      semanticLabel: lines.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  lines.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.headline.of(context, emphasized: true),
                ),
              ),
              GlyphIcon(
                AppGlyphs.chevronForward,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          if (subtitle != null)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 12),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: Text(
                  nekoTopSpeed,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
              ),
              _Speed(glyph: AppGlyphs.arrowDown, bytes: speed.down),
              _Speed(glyph: AppGlyphs.arrowUp, bytes: speed.up),
            ],
          ),
        ],
      ),
    );
  }
}

/// The exit card's two lines: the country when it is known, then the
/// server; the server alone otherwise.
({String title, String? subtitle}) nekoExitLines({
  required String? exit,
  required NekoSelection? selection,
}) {
  final pick = switch (selection) {
    null => null,
    NekoSelection(auto: true) => nekoServer(nekoAuto),
    NekoSelection(:final member) when member.isNotEmpty => nekoServer(member),
    _ => null,
  };
  final server = selection?.server ?? '';
  final country = exit ?? nekoCountryOf(server);
  if (country != null) {
    return (title: nekoCountryName(country), subtitle: pick);
  }
  final auto = selection?.auto ?? false;
  return (
    title: pick ?? nekoServer('—'),
    subtitle: auto && server.isNotEmpty ? server : null,
  );
}

class _Speed extends StatelessWidget {
  const _Speed({required this.glyph, required this.bytes});

  final Glyph glyph;
  final num bytes;

  @override
  Widget build(BuildContext context) {
    final style = DashboardText.figure(context, AppTextStyle.subheadline);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        GlyphIcon(glyph, size: 16, color: context.colorScheme.onSurfaceVariant),
        Text(bytes > 0 ? '${dashboardTraffic(bytes)}/s' : '—', style: style),
      ],
    );
  }
}

/// Shown while there is no subscription: paste the link, scan its code, or
/// ask the bot for one.
class NekoAddCard extends ConsumerWidget {
  const NekoAddCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DashboardCard(
      semanticLabel: nekoAddCardTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.addCircle,
            title: nekoAddCardTitle,
          ),
          Text(
            nekoAddCardText,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          TonalButton(
            size: TonalButtonSize.bar,
            glyph: AppGlyphs.paste,
            label: nekoPasteLink,
            onPressed: () => nekoPasteSubscription(context, ref),
          ),
          TonalButton(
            size: TonalButtonSize.bar,
            glyph: AppGlyphs.qrCode,
            label: nekoScanQr,
            onPressed: () => AddProfileMenu.scan(context, ref),
          ),
          TonalButton(
            size: TonalButtonSize.bar,
            glyph: AppGlyphs.send,
            label: nekoOpenBot,
            onPressed: () => nekoOpen(ref, Uri.parse(nekoBotAppUrl)),
          ),
          Text(nekoVpnPromptNote, style: DashboardText.label(context)),
        ],
      ),
    );
  }
}

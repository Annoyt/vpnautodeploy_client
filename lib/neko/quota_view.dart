import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'quota.dart';

/// Where «Купить подписку» leads: the bot's plan menu (/start buy).
const nekoBuyUrl = '$nekoBotUrl?start=buy';

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.${date.year}';

/// The month of a NekoVPN key: used and total, what the allowance is, what
/// counts, and what to do when it runs out.
class NekoQuotaCard extends StatelessWidget {
  const NekoQuotaCard({
    super.key,
    required this.quota,
    required this.now,
    this.onBuy,
  });

  final NekoQuota quota;
  final DateTime now;

  /// Replaced in tests; opens the bot's plan menu by default.
  final void Function()? onBuy;

  void _buy() {
    final onBuy = this.onBuy;
    if (onBuy != null) {
      onBuy();
    } else {
      unawaited(dialogs.openUrl(nekoBuyUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = quota.plan;
    final colors = DashboardColors.of(context);
    final expired = quota.expiredAt(now);
    final level = quota.level;
    final warn = expired || level != NekoQuotaLevel.normal;
    final note = AppTextStyle.footnote.of(context);
    final warning = switch (level) {
      _ when expired => nekoQuotaExpired(_date(quota.expire!)),
      NekoQuotaLevel.out => nekoQuotaOut,
      NekoQuotaLevel.high => nekoQuotaHigh((quota.share * 100).floor()),
      NekoQuotaLevel.normal => null,
    };
    final planText = switch (plan) {
      NekoPlan(paid: true) when quota.expire != null && !expired =>
        nekoQuotaPaid(_date(quota.expire!)),
      NekoPlan(paid: false, :final appGb?, :final otherGb?) => nekoQuotaDemo(
        appGb,
        otherGb,
      ),
      _ => null,
    };
    final buy = switch (plan.paid) {
      true when expired => nekoQuotaRenew,
      false when level == NekoQuotaLevel.out => nekoQuotaBuy,
      _ => null,
    };
    return DashboardCard(
      semanticLabel: nekoQuotaTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dataUsage,
            title: nekoQuotaTitle,
          ),
          const SizedBox(height: 12),
          Text(
            '${dashboardTraffic(quota.used)} / ${dashboardTraffic(quota.total)}',
            style: AppTextStyle.title3.of(context, emphasized: true),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: quota.share.clamp(0.0, 1.0),
            color: warn ? colors.warn : context.colorScheme.primary,
            backgroundColor: colors.tone2,
          ),
          if (warning != null) ...[
            const SizedBox(height: 8),
            Text(warning, style: note.copyWith(color: colors.warn)),
          ],
          const SizedBox(height: 8),
          if (planText != null) Text(planText, style: note),
          if (quota.belowAppAllowance)
            Text(nekoQuotaGrowing(plan.appGb!), style: note),
          Text(nekoQuotaRule, style: note),
          Text(nekoQuotaReset, style: note),
          if (buy != null) ...[
            const SizedBox(height: 12),
            TonalButton(
              size: TonalButtonSize.bar,
              glyph: AppGlyphs.openExternal,
              label: buy,
              onPressed: _buy,
            ),
          ],
        ],
      ),
    );
  }
}

/// Above the dashboard: [NekoQuotaCard] for the current profile when it is
/// ours (the bot named its plan) and carries a quota; nothing otherwise.
class NekoQuotaBanner extends ConsumerStatefulWidget {
  const NekoQuotaBanner({super.key, required this.gap, this.plan});

  /// The space under the card, the dashboard's gap between cards.
  final double gap;

  /// Replaced in tests; the plan store by default.
  final Future<NekoPlan?> Function(int profileId)? plan;

  @override
  ConsumerState<NekoQuotaBanner> createState() => _NekoQuotaBannerState();
}

class _NekoQuotaBannerState extends ConsumerState<NekoQuotaBanner> {
  Object? _loadedFor;
  Future<NekoPlan?>? _plan;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final info = profile?.subscriptionInfo;
    if (profile == null ||
        profile.type != ProfileType.url ||
        info == null ||
        info.total <= 0) {
      return const SizedBox.shrink();
    }
    // Read again after each profile update: the plan comes with it.
    final key = (profile.id, profile.lastUpdateDate);
    if (key != _loadedFor) {
      _loadedFor = key;
      _plan = (widget.plan ?? NekoPlanStore.of)(profile.id);
    }
    return FutureBuilder<NekoPlan?>(
      future: _plan,
      builder: (context, snapshot) {
        final plan = snapshot.data;
        if (plan == null) return const SizedBox.shrink();
        final quota = NekoQuota(
          plan: plan,
          used: info.upload + info.download,
          total: info.total,
          expire: info.expire > 0
              ? DateTime.fromMillisecondsSinceEpoch(info.expire * 1000)
              : null,
        );
        return Padding(
          padding: EdgeInsets.only(bottom: widget.gap),
          child: NekoQuotaCard(quota: quota, now: DateTime.now()),
        );
      },
    );
  }
}

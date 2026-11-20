import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart' show routedOutbound;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/home.dart';
import 'package:fl_clash/neko/links.dart';
import 'package:fl_clash/neko/quota.dart';
import 'package:fl_clash/neko/quota_view.dart';
import 'package:fl_clash/neko/sos_view.dart';
import 'package:fl_clash/neko/subscribe.dart';
import 'package:fl_clash/neko/zones.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/views/dashboard/dashboard.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/app_paths.dart';
import 'neko_ui.dart';

const _gb = 1024 * 1024 * 1024;
const _mb = 1024 * 1024;
const _demo = NekoPlan(paid: false, appGb: 10, otherGb: 5);
const _paid = NekoPlan(paid: true);

Profile _ours({int used = 3 * _gb, int total = 10 * _gb, DateTime? expire}) {
  return Profile.normal(
    label: 'NekoVPN',
    url: 'https://neko.example/sub/t',
  ).copyWith(
    subscriptionInfo: SubscriptionInfo(
      download: used,
      total: total,
      expire: expire == null ? 0 : expire.millisecondsSinceEpoch ~/ 1000,
    ),
  );
}

Group _group(String name, GroupType type, List<String> all, String now) {
  return Group(
    name: name,
    type: type,
    now: now,
    hidden: false,
    all: [for (final proxy in all) Proxy(name: proxy, type: 'Vless')],
  );
}

const _exitInGermany = RoutedProbeState({
  routedOutbound: ProbeEntry(
    phase: ProbePhase.fresh,
    value: IpInfo(ip: '203.0.113.7', countryCode: 'DE'),
  ),
});

final _groups = [
  _group('VPN', GroupType.Selector, ['Cascade', 'u1-reality'], 'Cascade'),
  _group('Cascade', GroupType.Fallback, ['u1-reality'], 'u1-reality'),
];

void main() {
  group('the current plan', () {
    late Directory home;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('neko_plan');
      await useAppPaths(home);
    });

    tearDown(() => home.delete(recursive: true));

    Future<NekoPlan?> planOf(Profile? profile) async {
      final container = ProviderContainer(
        overrides: [currentProfileProvider.overrideWithValue(profile)],
      );
      addTearDown(container.dispose);
      container.listen(nekoCurrentPlanProvider, (_, _) {});
      return container.read(nekoCurrentPlanProvider.future);
    }

    test('is the one the bot named for the current profile', () async {
      final profile = _ours();
      await NekoPlanStore.put(profile.id, _demo);
      expect((await planOf(profile))?.appGb, 10);
      expect(await planOf(null), isNull);
    });
  });

  testWidgets('no subscription: a grey button and the ways to add one', (
    tester,
  ) async {
    useNekoLayout();
    final app = NekoTestApp();
    await app.pump(tester, const DashboardView());
    expect(find.byType(NekoHomeView), findsOneWidget);
    expect(find.text(nekoHomeTitle), findsWidgets);
    expect(find.text(nekoNoSubscription), findsOneWidget);
    expect(find.text(nekoRefreshSubscription), findsNothing);
    expect(find.byType(NekoAddCard), findsOneWidget);
    expect(find.text(nekoVpnPromptNote), findsOneWidget);
    expect(find.byType(NekoExitCard), findsNothing);
    expect(find.text(nekoCannotConnect), findsOneWidget);
    expect(find.textContaining(nekoSubscriptionRow('')), findsNothing);

    await tester.tap(find.text(nekoOpenBot));
    await tester.pumpAndSettle();
    expect(app.launches.opened, [nekoBotAppUrl]);
  });

  testWidgets('the grey button asks for one: add, Telegram, a letter', (
    tester,
  ) async {
    useNekoLayout();
    final app = NekoTestApp(mail: nekoTestMail);
    await app.pump(tester, const NekoHomeView());
    await tester.tap(find.byTooltip(nekoAddSubscription));
    await tester.pumpAndSettle();
    final sheet = find.byType(NekoNeedSubscriptionSheet);
    expect(sheet, findsOneWidget);
    expect(find.text(nekoNeedSubscriptionText), findsOneWidget);

    await tester.tap(find.text(nekoRequestTelegram));
    await tester.pumpAndSettle();
    await tester.tap(find.text(nekoRequestMail));
    await tester.pumpAndSettle();
    expect(app.launches.opened, [
      nekoBotAppUrl,
      nekoMailto(nekoTestMail, nekoMailRequestSubject).toString(),
    ]);

    await tester.tap(
      find.descendant(of: sheet, matching: find.text(nekoAddSubscription)),
    );
    await tester.pumpAndSettle();
    final l10n = currentAppLocalizations;
    expect(find.text(l10n.qrcode), findsOneWidget);
    await tester.tap(find.text(l10n.link));
    await tester.pumpAndSettle();
    expect(find.byType(NamedUrlForm), findsOneWidget);
  });

  testWidgets('without the service mailbox the sheet offers no letter', (
    tester,
  ) async {
    useNekoLayout();
    final app = NekoTestApp();
    await app.pump(tester, const NekoHomeView());
    await tester.tap(find.byTooltip(nekoAddSubscription));
    await tester.pumpAndSettle();
    expect(find.text(nekoRequestTelegram), findsOneWidget);
    expect(find.text(nekoRequestMail), findsNothing);
  });

  testWidgets('a subscription: its month, refresh, connect, the server', (
    tester,
  ) async {
    useNekoLayout();
    final profile = _ours();
    final app = NekoTestApp(profiles: [profile], plan: _demo);
    await app.pump(tester, const NekoHomeView());
    final l10n = currentAppLocalizations;
    expect(find.text(nekoDemo), findsOneWidget);
    expect(
      find.text(
        nekoUsedOf(dashboardTraffic(3 * _gb), dashboardTraffic(10 * _gb)),
      ),
      findsOneWidget,
    );
    expect(find.text(nekoQuotaBuy), findsNothing);
    expect(find.text(l10n.notRunning), findsOneWidget);
    expect(find.byType(NekoAddCard), findsNothing);
    expect(find.text(nekoServer('—')), findsOneWidget);
    expect(find.text(nekoTopSpeed), findsOneWidget);
    expect(find.text(nekoSubscriptionRow('NekoVPN')), findsOneWidget);

    await tester.tap(find.text(nekoRefreshSubscription));
    await tester.pumpAndSettle();
    expect(app.profilesAction.updated, [profile.id]);

    await tester.tap(find.byTooltip(l10n.start));
    await tester.pumpAndSettle();
    expect(app.commonAction.toggles, 1);
  });

  testWidgets('running: the country, the time and the top speeds', (
    tester,
  ) async {
    useNekoLayout();
    final app = NekoTestApp(
      profiles: [_ours()],
      plan: _demo,
      overrides: [
        runTimeProvider.overrideWithBuild((_, _) => 3723000),
        groupsProvider.overrideWithValue(_groups),
        outboundIpProbeProvider.overrideWithBuild((_, _) => _exitInGermany),
      ],
    );
    await app.pump(tester, const NekoHomeView());
    final l10n = currentAppLocalizations;
    expect(find.text(l10n.running), findsOneWidget);
    expect(find.text(getTimeText(3723000)), findsOneWidget);
    expect(find.byTooltip(l10n.stop), findsOneWidget);
    expect(find.text(nekoCountryName('DE')), findsOneWidget);
    expect(find.text(nekoServer(nekoAuto)), findsOneWidget);

    app.container
        .read(trafficsProvider.notifier)
        .addTraffic(const Traffic(up: 2 * _mb, down: 8 * _mb));
    await tester.pump();
    expect(find.text('${dashboardTraffic(8 * _mb)}/s'), findsOneWidget);
    expect(find.text('${dashboardTraffic(2 * _mb)}/s'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('paused on a network that needs no VPN', (tester) async {
    useNekoLayout();
    final app = NekoTestApp(
      profiles: [_ours()],
      plan: _demo,
      overrides: [
        runTimeProvider.overrideWithBuild((_, _) => 1000),
        suspendProvider.overrideWithValue(true),
        outboundIpProbeProvider.overrideWithBuild((_, _) => _exitInGermany),
      ],
    );
    await app.pump(tester, const NekoHomeView());
    final l10n = currentAppLocalizations;
    expect(find.text(l10n.suspended), findsOneWidget);
    expect(find.byTooltip(l10n.suspended), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a demo out of traffic offers the plans', (tester) async {
    useNekoLayout();
    final app = NekoTestApp(
      profiles: [_ours(used: 10 * _gb)],
      plan: _demo,
    );
    await app.pump(tester, const NekoHomeView());
    expect(find.text(nekoQuotaOut), findsOneWidget);
    await tester.tap(find.text(nekoQuotaBuy));
    await tester.pumpAndSettle();
    expect(app.launches.opened, [nekoBuyUrl]);
  });

  testWidgets('from 80 percent a warning, no offer yet', (tester) async {
    useNekoLayout();
    final app = NekoTestApp(
      profiles: [_ours(used: 9 * _gb)],
      plan: _demo,
    );
    await app.pump(tester, const NekoHomeView());
    expect(find.text(nekoQuotaHigh(90)), findsOneWidget);
    expect(find.text(nekoQuotaBuy), findsNothing);
  });

  testWidgets('an ended paid month offers renewal', (tester) async {
    useNekoLayout();
    final app = NekoTestApp(
      profiles: [_ours(expire: DateTime(2020))],
      plan: _paid,
    );
    await app.pump(tester, const NekoHomeView());
    expect(find.text(nekoEndedOn('01.01.2020')), findsOneWidget);
    expect(find.text(nekoQuotaRenew), findsOneWidget);
  });

  testWidgets('a paid month shows its end', (tester) async {
    useNekoLayout();
    final app = NekoTestApp(
      profiles: [_ours(expire: DateTime(2100))],
      plan: _paid,
    );
    await app.pump(tester, const NekoHomeView());
    expect(find.text(nekoValidUntil('01.01.2100')), findsOneWidget);
    expect(find.text(nekoQuotaRenew), findsNothing);
  });

  testWidgets('the exit card opens the servers', (tester) async {
    useNekoLayout();
    final app = NekoTestApp(profiles: [_ours()], plan: _demo);
    await app.pump(tester, const NekoHomeView());
    await tester.tap(find.byType(NekoExitCard));
    await tester.pumpAndSettle();
    expect(app.proxiesAction.refreshes, 1);
    expect(find.byType(ProxiesView), findsOneWidget);
  });

  testWidgets('«Cannot connect?» opens SOS', (tester) async {
    useNekoLayout();
    final app = NekoTestApp(profiles: [_ours()], plan: _demo);
    await app.pump(tester, const NekoHomeView());
    await tester.tap(find.text(nekoCannotConnect));
    await tester.pumpAndSettle();
    expect(find.byType(NekoSosView), findsOneWidget);
  });

  testWidgets('the subscription row opens the subscriptions', (tester) async {
    useNekoLayout();
    final app = NekoTestApp(
      profiles: [_ours()],
      plan: _demo,
      mail: nekoTestMail,
    );
    await app.pump(tester, const NekoHomeView());
    await tester.tap(find.text(nekoSubscriptionRow('NekoVPN')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilesView), findsOneWidget);
    expect(find.text(nekoPasteFromClipboard), findsOneWidget);
    expect(find.text(nekoAskMail), findsOneWidget);
  });

  testWidgets('a link in the clipboard is added; without one, the form', (
    tester,
  ) async {
    useNekoLayout();
    final app = NekoTestApp();
    await app.pump(tester, const NekoHomeView());
    mockClipboard(tester, 'Ваша подписка: https://neko.example/sub/abc');
    await tester.tap(find.text(nekoPasteLink));
    await tester.pumpAndSettle();
    expect(app.profilesAction.added, ['https://neko.example/sub/abc']);

    mockClipboard(tester, null);
    await tester.tap(find.text(nekoPasteLink));
    await tester.pumpAndSettle();
    expect(find.byType(NamedUrlForm), findsOneWidget);
  });

  testWidgets('a clipboard the system refuses opens the form', (tester) async {
    useNekoLayout();
    final app = NekoTestApp();
    await app.pump(tester, const NekoHomeView());
    mockClipboard(tester, null, fails: true);
    await tester.tap(find.text(nekoPasteLink));
    await tester.pumpAndSettle();
    expect(find.byType(NamedUrlForm), findsOneWidget);
    expect(app.profilesAction.added, isEmpty);
  });

  testWidgets('a link no app takes is reported, not thrown', (tester) async {
    useNekoLayout();
    final app = NekoTestApp();
    await app.pump(tester, const NekoHomeView());
    app.launches.answer = false;
    await tester.tap(find.text(nekoOpenBot));
    await tester.pumpAndSettle();
    app.launches.fails = true;
    await tester.tap(find.text(nekoOpenBot));
    await tester.pumpAndSettle();
    expect(app.launches.opened, [nekoBotAppUrl, nekoBotAppUrl]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the advanced Home keeps the dashboard cards between', (
    tester,
  ) async {
    useNekoLayout();
    final app = NekoTestApp(profiles: [_ours()], plan: _demo, advanced: true);
    await app.pump(
      tester,
      const DashboardView(platform: SupportPlatform.Android),
      settle: false,
    );
    expect(find.byType(NekoHomeView), findsNothing);
    expect(find.byType(NekoConnectCard), findsOneWidget);
    expect(find.byType(NekoExitCard), findsOneWidget);
    expect(find.byType(NekoHomeFoot), findsOneWidget);
    expect(find.text(nekoHomeTitle), findsWidgets);
    expect(find.text(nekoCannotConnect), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}

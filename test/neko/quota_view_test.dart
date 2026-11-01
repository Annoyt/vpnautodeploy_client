import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/quota.dart';
import 'package:fl_clash/neko/quota_view.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

const _gb = 1024 * 1024 * 1024;
const _demo = NekoPlan(paid: false, appGb: 10, otherGb: 5);
const _paid = NekoPlan(paid: true);
final _now = DateTime(2026, 11, 1);

Future<int> _pump(WidgetTester tester, NekoQuota quota) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var bought = 0;
  await tester.pumpWidget(
    TestApp(
      wrapInProviderScope: true,
      child: Scaffold(
        body: SingleChildScrollView(
          child: NekoQuotaCard(quota: quota, now: _now, onBuy: () => bought++),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final button = find.text(nekoQuotaBuy).evaluate().isNotEmpty
      ? find.text(nekoQuotaBuy)
      : find.text(nekoQuotaRenew);
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button);
    await tester.pumpAndSettle();
  }
  return bought;
}

void main() {
  testWidgets('a demo month: the allowance and what counts', (tester) async {
    final bought = await _pump(
      tester,
      const NekoQuota(plan: _demo, used: 3 * _gb, total: 10 * _gb),
    );
    expect(find.text(nekoQuotaDemo(10, 5)), findsOneWidget);
    expect(find.text(nekoQuotaRule), findsOneWidget);
    expect(find.text(nekoQuotaReset), findsOneWidget);
    expect(find.text(nekoQuotaOut), findsNothing);
    expect(find.text(nekoQuotaGrowing(10)), findsNothing);
    expect(bought, 0);
  });

  testWidgets('from 80 percent a warning', (tester) async {
    await _pump(
      tester,
      const NekoQuota(plan: _demo, used: 85 * _gb ~/ 10, total: 10 * _gb),
    );
    expect(find.text(nekoQuotaHigh(85)), findsOneWidget);
    expect(find.text(nekoQuotaBuy), findsNothing);
  });

  testWidgets('a demo key that ran out offers the plans', (tester) async {
    final bought = await _pump(
      tester,
      const NekoQuota(plan: _demo, used: 10 * _gb, total: 10 * _gb),
    );
    expect(find.text(nekoQuotaOut), findsOneWidget);
    expect(bought, 1);
  });

  testWidgets('a demo key on the smaller allowance is told it grows', (
    tester,
  ) async {
    await _pump(
      tester,
      const NekoQuota(plan: _demo, used: _gb, total: 5 * _gb),
    );
    expect(find.text(nekoQuotaGrowing(10)), findsOneWidget);
  });

  testWidgets('a paid month shows the date; an ended one offers renewal', (
    tester,
  ) async {
    await _pump(
      tester,
      NekoQuota(
        plan: _paid,
        used: _gb,
        total: 100 * _gb,
        expire: DateTime(2026, 12, 31),
      ),
    );
    expect(find.text(nekoQuotaPaid('31.12.2026')), findsOneWidget);
    expect(find.text(nekoQuotaRenew), findsNothing);

    final bought = await _pump(
      tester,
      NekoQuota(
        plan: _paid,
        used: _gb,
        total: 100 * _gb,
        expire: DateTime(2026, 10, 31),
      ),
    );
    expect(find.text(nekoQuotaExpired('31.10.2026')), findsOneWidget);
    expect(bought, 1);
  });

  testWidgets('a paid key that ran out waits for the 1st, no offer', (
    tester,
  ) async {
    final bought = await _pump(
      tester,
      NekoQuota(
        plan: _paid,
        used: 100 * _gb,
        total: 100 * _gb,
        expire: DateTime(2026, 12, 31),
      ),
    );
    expect(find.text(nekoQuotaOut), findsOneWidget);
    expect(bought, 0);
  });

  group('the banner', () {
    Future<void> pumpBanner(
      WidgetTester tester,
      Profile? profile,
      NekoPlan? plan,
    ) async {
      await tester.pumpWidget(
        TestApp(
          wrapInProviderScope: true,
          overrides: [currentProfileProvider.overrideWithValue(profile)],
          child: Scaffold(
            body: SingleChildScrollView(
              child: NekoQuotaBanner(gap: 8, plan: (_) async => plan),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Profile ours({int total = 10 * _gb}) =>
        Profile.normal(url: 'https://main.example/sub/t?format=clash').copyWith(
          subscriptionInfo: SubscriptionInfo(download: _gb, total: total),
        );

    testWidgets('shows our profile with a plan', (tester) async {
      await pumpBanner(tester, ours(), _demo);
      expect(find.byType(NekoQuotaCard), findsOneWidget);
    });

    testWidgets('nothing without a plan', (tester) async {
      await pumpBanner(tester, ours(), null);
      expect(find.byType(NekoQuotaCard), findsNothing);
    });

    testWidgets('nothing without a quota', (tester) async {
      await pumpBanner(tester, ours(total: 0), _demo);
      expect(find.byType(NekoQuotaCard), findsNothing);
    });

    testWidgets('nothing without a profile', (tester) async {
      await pumpBanner(tester, null, _demo);
      expect(find.byType(NekoQuotaCard), findsNothing);
    });

    testWidgets('nothing for a file profile', (tester) async {
      await pumpBanner(tester, Profile.normal(), _demo);
      expect(find.byType(NekoQuotaCard), findsNothing);
    });
  });
}

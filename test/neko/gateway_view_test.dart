import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/gateway.dart';
import 'package:fl_clash/neko/gateway_view.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

const _share = NekoGatewayShare(port: 7891, username: 'u', password: 'p');

class _Fixture {
  _Fixture({NekoGateway? stored, this.hosts = const ['192.168.43.1']})
    : stored = stored ?? const NekoGateway();

  NekoGateway stored;
  final List<String> hosts;
  final written = <NekoGateway>[];
  int applied = 0;
  String? scanned;

  NekoGatewayView view() => NekoGatewayView(
    read: () async => stored,
    write: (gateway) async {
      written.add(gateway);
      stored = gateway;
    },
    apply: () => applied++,
    hosts: () async => hosts,
    scan: (_) async => scanned,
  );
}

Future<void> _pump(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TestApp(wrapInProviderScope: true, child: fixture.view()),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sharing shows the code and loads the profile again', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _pump(tester, fixture);
    expect(find.byType(QrCodeView), findsNothing);

    await tester.tap(find.text(nekoGatewayShare));
    await tester.pumpAndSettle();

    final share = fixture.written.single.share!;
    expect(fixture.written.single.join, isNull);
    expect(share.port, nekoGatewayPort);
    expect(fixture.applied, 1);
    final code = tester.widget<QrCodeView>(find.byType(QrCodeView));
    expect(nekoGatewayFromLink(code.data)?.password, share.password);
    expect(find.text('192.168.43.1'), findsOneWidget);

    await tester.tap(find.text(nekoGatewayShare));
    await tester.pumpAndSettle();
    expect(fixture.written.last.share, isNull);
    expect(fixture.applied, 2);
    expect(find.byType(QrCodeView), findsNothing);
  });

  testWidgets('without a network to share, says so instead of a code', (
    tester,
  ) async {
    final fixture = _Fixture(
      stored: const NekoGateway(share: _share),
      hosts: const [],
    );
    await _pump(tester, fixture);
    expect(find.text(nekoGatewayNoNetwork), findsOneWidget);
    expect(find.byType(QrCodeView), findsNothing);
  });

  testWidgets('a scanned code joins, and leaving clears it', (tester) async {
    final fixture = _Fixture(stored: const NekoGateway(share: _share))
      ..scanned = nekoGatewayLink(_share, ['10.0.0.1']);
    await _pump(tester, fixture);

    await tester.tap(find.text(nekoGatewayScan));
    await tester.pumpAndSettle();
    final joined = fixture.written.single;
    expect(joined.join?.hosts, ['10.0.0.1']);
    expect(joined.share, isNull);
    expect(find.text('10.0.0.1:7891'), findsOneWidget);
    expect(find.text(nekoGatewayJoined), findsOneWidget);

    await tester.tap(find.text(nekoGatewayLeave));
    await tester.pumpAndSettle();
    expect(fixture.written.last.join, isNull);
    expect(fixture.applied, 2);
    expect(find.text(nekoGatewayScan), findsOneWidget);
  });

  testWidgets('a cancelled or foreign scan changes nothing', (tester) async {
    final fixture = _Fixture()..scanned = 'https://example.com';
    await _pump(tester, fixture);
    await tester.tap(find.text(nekoGatewayScan));
    await tester.pumpAndSettle();
    expect(fixture.written, isEmpty);
    expect(fixture.applied, 0);
  });

  testWidgets('the Tools entry opens the screen', (tester) async {
    await tester.pumpWidget(
      const TestApp(
        wrapInProviderScope: true,
        child: Scaffold(body: NekoGatewayItem()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(nekoGatewayTitle), findsOneWidget);
    expect(find.text(nekoGatewaySubtitle), findsOneWidget);
  });
}

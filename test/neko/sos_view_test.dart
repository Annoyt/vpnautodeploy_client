import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/sos.dart';
import 'package:fl_clash/neko/sos_view.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _token = '0123456789abcdef0123456789abcdef';
const _ours = 'https://autonekovpn.duckdns.org:9443/sub/$_token?format=clash';
const _emergency =
    'https://autonekovpn.duckdns.org:9443/sub/$_token'
    '?format=clash&emergency=1';

typedef _Sent = ({String token, Map<String, Object?> report});

ProviderContainer _container(WidgetTester tester, List<Profile> profiles) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [profilesProvider.overrideWith(() => TestProfiles(profiles))],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  return container;
}

Future<List<_Sent>> _pump(
  WidgetTester tester,
  List<Profile> profiles,
  NekoSosAnswer? answer,
) async {
  final sent = <_Sent>[];
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container(tester, profiles),
      child: TestApp(
        child: NekoSosView(
          network: () async => 'wifi',
          settings: () async => null,
          send: (token, report, origins) async {
            sent.add((token: token, report: report));
            return answer;
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text(nekoSosSend));
  await tester.pumpAndSettle();
  return sent;
}

void main() {
  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'NekoVPN',
      packageName: 'com.nekovpn.client',
      version: '0.9.2-neko.2',
      buildNumber: '1',
    );
  });

  testWidgets('sends what the app sees and shows the answer', (tester) async {
    final sent = await _pump(
      tester,
      [Profile.normal(url: _ours)],
      const NekoSosAnswer(
        status: 'reported',
        lines: ['Reality: works'],
        emergency: _emergency,
      ),
    );
    expect(sent.single.token, _token);
    expect(sent.single.report['network'], 'wifi');
    expect(sent.single.report['app'], '0.9.2-neko.2');
    expect(find.text(nekoSosReported), findsOneWidget);
    expect(find.text('Reality: works'), findsOneWidget);
    expect(find.text(nekoSosEmergency), findsOneWidget);
    expect(find.text(nekoSosBot), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a repeat says so; no link, no emergency item', (tester) async {
    await _pump(tester, [
      Profile.normal(url: _ours),
    ], const NekoSosAnswer(status: 'repeat', lines: ['x']));
    expect(find.text(nekoSosRepeat), findsOneWidget);
    expect(find.text(nekoSosEmergency), findsNothing);
  });

  testWidgets('no answer anywhere: the bot and a copy of the report', (
    tester,
  ) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pump(tester, [Profile.normal(url: _ours)], null);
    expect(find.text(nekoSosFailed), findsOneWidget);
    expect(find.text(nekoSosBot), findsOneWidget);
    await tester.tap(find.text(nekoSosCopy));
    await tester.pumpAndSettle();
    expect(copied, contains('"app":"0.9.2-neko.2"'));
  });

  testWidgets('without our subscription nothing is sent', (tester) async {
    final sent = await _pump(tester, [
      Profile.normal(url: 'https://other.example/sub/$_token'),
    ], const NekoSosAnswer(status: 'reported', lines: []));
    expect(sent, isEmpty);
    expect(find.text(nekoSosNoProfile), findsOneWidget);
    expect(find.text(nekoSosBot), findsOneWidget);
    expect(find.text(nekoSosCopy), findsNothing);
  });

  testWidgets('Tools opens the page', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(tester, const []),
        child: const TestApp(child: Scaffold(body: NekoSosItem())),
      ),
    );
    expect(find.text(nekoSosTitle), findsOneWidget);
    await tester.tap(find.text(nekoSosTitle));
    await tester.pumpAndSettle();
    expect(find.byType(NekoSosView), findsOneWidget);
  });
}

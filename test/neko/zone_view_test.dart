import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/zones.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:flutter_test/flutter_test.dart';

import 'neko_ui.dart';

const _de = '\u{1F1E9}\u{1F1EA}';
const _nl = '\u{1F1F3}\u{1F1F1}';
const _fi = '\u{1F1EB}\u{1F1EE}';
const _se = '\u{1F1F8}\u{1F1EA}';

Group _group(String name, GroupType type, List<String> all, String now) {
  return Group(
    name: name,
    type: type,
    now: now,
    hidden: false,
    all: [for (final proxy in all) Proxy(name: proxy, type: 'Vless')],
  );
}

/// «Proxy» picks among «Best» and the servers, now [now].
List<Group> _groups(List<String> servers, String now) => [
  _group('Proxy', GroupType.Selector, ['Best', ...servers], now),
  _group('Best', GroupType.URLTest, servers, servers.first),
];

void main() {
  testWidgets('servers in two countries: a zone row over them', (tester) async {
    useNekoLayout();
    final app = NekoTestApp(
      overrides: [
        groupsProvider.overrideWithValue(
          _groups([
            '$_de Frankfurt',
            '$_nl Amsterdam',
            '$_nl Rotterdam',
          ], '$_de Frankfurt'),
        ),
        delayDataSourceProvider.overrideWithBuild(
          (_, _) => {
            'https://probe.example': {
              '$_nl Amsterdam': 90,
              '$_nl Rotterdam': 40,
            },
          },
        ),
      ],
    );
    await app.pump(tester, const ProxiesView());
    expect(find.text(nekoExitZone), findsOneWidget);
    expect(find.byType(SegmentedControl<String>), findsOneWidget);

    await tester.tap(find.text(nekoCountryName('NL')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(nekoAuto));
    await tester.pumpAndSettle();
    expect(app.proxiesAction.picks, ['Proxy $_nl Rotterdam', 'Proxy Best']);
  });

  testWidgets('more countries than fit a row: a list to pick from', (
    tester,
  ) async {
    useNekoLayout();
    final app = NekoTestApp(
      overrides: [
        groupsProvider.overrideWithValue(
          _groups(['$_de A', '$_nl B', '$_fi C', '$_se D', 'Plain'], 'Plain'),
        ),
      ],
    );
    await app.pump(tester, const ProxiesView());
    expect(find.byType(SegmentedControl<String>), findsNothing);
    expect(find.text(nekoCountryName('DE')), findsNothing);

    await tester.tap(find.text(nekoExitZone));
    await tester.pumpAndSettle();
    await tester.tap(find.text(nekoCountryName('FI')).last);
    await tester.pumpAndSettle();
    expect(app.proxiesAction.picks, ['Proxy $_fi C']);
  });

  testWidgets('servers in one country: no zone row', (tester) async {
    useNekoLayout();
    final one = NekoTestApp(
      overrides: [
        groupsProvider.overrideWithValue(
          _groups(['$_de A', '$_de B'], '$_de A'),
        ),
      ],
    );
    await one.pump(tester, const ProxiesView());
    expect(find.text(nekoExitZone), findsNothing);
  });

  testWidgets('the picker sheet has no zone row', (tester) async {
    useNekoLayout();
    final app = NekoTestApp(
      overrides: [
        groupsProvider.overrideWithValue(_groups(['$_de A', '$_nl B'], 'Best')),
      ],
    );
    await app.pump(tester, const ProxiesView(picker: true));
    expect(find.text(nekoExitZone), findsNothing);
  });

  testWidgets('FlClash has no zone row', (tester) async {
    final app = NekoTestApp(
      overrides: [
        groupsProvider.overrideWithValue(_groups(['$_de A', '$_nl B'], 'Best')),
      ],
    );
    await app.pump(tester, const ProxiesView());
    expect(find.text(nekoExitZone), findsNothing);
  });
}

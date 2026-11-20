import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/links.dart';
import 'package:fl_clash/neko/subscribe.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
import 'package:flutter_test/flutter_test.dart';

import 'neko_ui.dart';

const _sub = 'https://neko.example/sub/abc';

List<Profile> _profiles() => [
  Profile.normal(label: 'NekoVPN', url: 'https://neko.example/sub/t'),
];

void main() {
  test('the link in what was copied: alone or among words', () {
    expect(nekoSubscriptionLinkIn(_sub), _sub);
    expect(nekoSubscriptionLinkIn('  $_sub\n'), _sub);
    expect(nekoSubscriptionLinkIn('Ваша подписка:\n$_sub спасибо'), _sub);
    expect(
      nekoSubscriptionLinkIn(
        'nekovpn://install-config?url=${Uri.encodeComponent(_sub)}',
      ),
      _sub,
    );
    expect(
      nekoSubscriptionLinkIn('vless://id@host.example:443#x'),
      'vless://id@host.example:443#x',
    );
    expect(nekoSubscriptionLinkIn('просто текст'), isNull);
    expect(nekoSubscriptionLinkIn(null), isNull);
  });

  testWidgets('over the subscriptions: paste, ask the bot, ask by mail', (
    tester,
  ) async {
    useNekoLayout();
    final app = NekoTestApp(profiles: _profiles(), mail: nekoTestMail);
    await app.pump(tester, const ProfilesView());
    mockClipboard(tester, _sub);
    await tester.tap(find.text(nekoPasteFromClipboard));
    await tester.pumpAndSettle();
    expect(app.profilesAction.added, [_sub]);

    await tester.tap(find.text(nekoAskBot));
    await tester.pumpAndSettle();
    await tester.tap(find.text(nekoAskMail));
    await tester.pumpAndSettle();
    expect(app.launches.opened, [
      nekoBotAppUrl,
      nekoMailto(nekoTestMail, nekoMailRequestSubject).toString(),
    ]);
  });

  testWidgets('without the service mailbox, no letter', (tester) async {
    useNekoLayout();
    final app = NekoTestApp(profiles: _profiles());
    await app.pump(tester, const ProfilesView());
    expect(find.text(nekoAskBot), findsOneWidget);
    expect(find.text(nekoAskMail), findsNothing);
  });

  testWidgets('the picker sheet keeps the list alone', (tester) async {
    useNekoLayout();
    final picker = NekoTestApp(profiles: _profiles(), mail: nekoTestMail);
    await picker.pump(tester, const ProfilesView(picker: true));
    expect(find.text(nekoPasteFromClipboard), findsNothing);
  });

  testWidgets('FlClash keeps the list alone', (tester) async {
    final app = NekoTestApp(profiles: _profiles(), mail: nekoTestMail);
    await app.pump(tester, const ProfilesView());
    expect(find.text(nekoPasteFromClipboard), findsNothing);
  });
}

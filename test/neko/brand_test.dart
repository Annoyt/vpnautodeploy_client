import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/protocol.dart';
import 'package:fl_clash/neko/brand.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  test('the app carries the fork name and repository', () {
    expect(appName, 'NekoVPN');
    expect(repository, 'Annoyt/vpnautodeploy_client');
  });

  test('links use our scheme and leave flclash:// to FlClash', () {
    expect(protocolSchemes, contains('nekovpn'));
    expect(protocolSchemes, isNot(contains('flclash')));
  });

  test('fork texts follow the locale and say what was changed', () {
    final ru = Intl.withLocale('ru', () => nekoDescription);
    final en = Intl.withLocale('en', () => nekoDescription);
    expect(ru, contains('Изменённая версия FlClash'));
    expect(en, contains('A modified version of FlClash'));
    expect(ru, contains(nekoModifiedOn));
    expect(en, contains(nekoModifiedOn));
  });

  test('the privacy text: Firebase removed, ML Kit named', () {
    final ru = Intl.withLocale('ru', () => nekoPrivacyContent);
    final en = Intl.withLocale('en', () => nekoPrivacyContent);
    expect(ru, contains('здесь удалены'));
    expect(en, contains('are removed'));
    expect(ru, contains('Google ML Kit'));
    expect(en, contains('Google ML Kit'));
  });
}

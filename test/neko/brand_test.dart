import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/protocol.dart';
import 'package:fl_clash/neko/brand.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// Texts naming FlClash that the Android app never shows: the desktop
/// ones, renamed together with the desktop build (docs/PLAN.md).
const _desktopOnly = {
  'helperCorruptTip',
  'coreBlockedByPolicyTip',
  'coreBlockedBySmartAppControlTip',
};

List<String> _textsNamingFlClash() {
  final file = File('arb/intl_en.arb');
  final texts = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final MapEntry(:key, :value) in texts.entries)
      if (value is String && value.contains('FlClash')) key,
  ];
}

Iterable<File> _appSources() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (!entity.path.contains('/l10n/')) yield entity;
  }
}

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

  test('the privacy text: no analytics, ML Kit named', () {
    final ru = Intl.withLocale('ru', () => nekoPrivacyContent);
    final en = Intl.withLocale('en', () => nekoPrivacyContent);
    expect(ru, contains('не содержит сервисов статистики и отчётов о сбоях'));
    expect(en, contains('includes no analytics or crash reporting service'));
    expect(ru, contains('Google ML Kit'));
    expect(en, contains('Google ML Kit'));
  });

  test('upstream texts about the app name NekoVPN', () {
    expect(nekoBranded('Send a link to FlClash'), 'Send a link to NekoVPN');
    expect(nekoBranded('Ссылка в FlClash'), 'Ссылка в NekoVPN');
  });

  test('the Android app shows no upstream text naming FlClash as is', () {
    bool android(String key) => !_desktopOnly.contains(key);
    final keys = _textsNamingFlClash().where(android).toList();
    expect(keys, isNotEmpty);
    final uses = RegExp('\\.(${keys.join('|')})\\b');
    final unbranded = [
      for (final file in _appSources())
        for (final (index, line) in file.readAsLinesSync().indexed)
          if (uses.hasMatch(line) && !line.contains('nekoBranded('))
            '${file.path}:${index + 1}',
    ];
    expect(unbranded, isEmpty);
  });
}

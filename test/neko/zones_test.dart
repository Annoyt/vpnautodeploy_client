import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/home.dart';
import 'package:fl_clash/neko/zones.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

const _de = '\u{1F1E9}\u{1F1EA}';
const _nl = '\u{1F1F3}\u{1F1F1}';

Group _group(String name, GroupType type, List<String> all, {String? now}) {
  return Group(
    name: name,
    type: type,
    now: now,
    all: [for (final proxy in all) Proxy(name: proxy, type: 'Vless')],
  );
}

/// The bot's profile: VPN picks Cascade, which runs one of the servers.
final _neko = [
  _group('VPN', GroupType.Selector, [
    'Cascade',
    'Auto',
    'u1-reality',
    'u1-de',
  ], now: 'Cascade'),
  _group('Cascade', GroupType.Fallback, [
    'u1-reality',
    'u1-de',
  ], now: 'u1-reality'),
  _group('Auto', GroupType.URLTest, ['u1-reality', 'u1-de'], now: 'u1-de'),
];

final _flagged = [
  _group('Proxy', GroupType.Selector, [
    'Best',
    '$_de Frankfurt',
    '$_de Berlin',
    '$_nl Amsterdam',
    'DIRECT',
  ], now: '$_de Berlin'),
  _group('Best', GroupType.URLTest, ['$_de Frankfurt'], now: '$_de Frankfurt'),
];

NekoSelection? _select(List<Group> groups, [Map<String, String>? map]) {
  return nekoSelectionOf(
    shown: groups,
    groups: groups,
    selectedMap: map ?? const {},
  );
}

void main() {
  group('countries', () {
    test('a flag in a name is its country, a name alone is none', () {
      expect(nekoCountryOf('$_de Frankfurt'), 'DE');
      expect(nekoCountryOf('Amsterdam $_nl 2'), 'NL');
      expect(nekoCountryOf('u1-de'), isNull);
      expect(nekoCountryOf(''), isNull);
      expect(nekoCountryOf('\u{1F1E9} split \u{1F1EA}'), isNull);
    });

    test('a country reads with its flag in the user language', () {
      expect(
        Intl.withLocale('ru', () => nekoCountryName('de')),
        '$_de Германия',
      );
      expect(
        Intl.withLocale('en', () => nekoCountryName('NL')),
        '$_nl Netherlands',
      );
      expect(nekoCountryName('ZZ'), endsWith(' ZZ'));
    });
  });

  group('the selection', () {
    test('none without groups', () {
      expect(_select(const []), isNull);
    });

    test('the bot profile: automatic, no zones, the running server', () {
      final selection = _select(_neko)!;
      expect(selection.group.name, 'VPN');
      expect(selection.member, 'Cascade');
      expect(selection.auto, isTrue);
      expect(selection.server, 'u1-reality');
      expect(selection.autoMember, 'Cascade');
      expect(selection.zones, isEmpty);
    });

    test('a pick of the user wins over what the group ran', () {
      final selection = _select(_neko, {'VPN': 'u1-de'})!;
      expect(selection.member, 'u1-de');
      expect(selection.auto, isFalse);
      expect(selection.server, 'u1-de');
    });

    test('flags make zones; a country group is a zone, not «Auto»', () {
      final groups = [
        ..._flagged,
        _group('$_nl Netherlands', GroupType.URLTest, ['$_nl Amsterdam']),
      ];
      groups[0] = _group('Proxy', GroupType.Selector, [
        ...groups[0].all.map((proxy) => proxy.name),
        '$_nl Netherlands',
      ], now: '$_nl Netherlands');
      final selection = _select(groups)!;
      expect(selection.auto, isFalse);
      expect(selection.autoMember, 'Best');
      expect(selection.zones.keys.toList(), ['DE', 'NL']);
      expect(selection.zones['DE'], ['$_de Frankfurt', '$_de Berlin']);
      expect(selection.zones['NL'], ['$_nl Amsterdam', '$_nl Netherlands']);
    });

    test('a group that picks by itself is automatic at the top', () {
      final selection = _select([_neko[1]])!;
      expect(selection.group.name, 'Cascade');
      expect(selection.auto, isTrue);
    });

    test('the fastest of a zone, else its first', () {
      final members = ['$_de Frankfurt', '$_de Berlin'];
      expect(
        nekoZonePick(members, {
          'https://a': {'$_de Frankfurt': 120, '$_de Berlin': 0},
          'https://b': {'$_de Berlin': 80},
        }),
        '$_de Berlin',
      );
      expect(
        nekoZonePick(members, {
          'https://a': {'$_de Frankfurt': -1},
        }),
        '$_de Frankfurt',
      );
    });
  });

  group('the exit card lines', () {
    test('the country first, then the server picked', () {
      final lines = Intl.withLocale(
        'en',
        () => nekoExitLines(exit: 'DE', selection: _select(_neko)),
      );
      expect(lines.title, '$_de Germany');
      expect(lines.subtitle, 'Server: Auto');
    });

    test('a flag in the running server tells the country', () {
      final lines = Intl.withLocale(
        'en',
        () => nekoExitLines(exit: null, selection: _select(_flagged)),
      );
      expect(lines.title, '$_de Germany');
      expect(lines.subtitle, 'Server: $_de Berlin');
    });

    test('no country: the pick, and what the automatic one runs', () {
      final lines = Intl.withLocale(
        'en',
        () => nekoExitLines(exit: null, selection: _select(_neko)),
      );
      expect(lines.title, 'Server: Auto');
      expect(lines.subtitle, 'u1-reality');
      final none = Intl.withLocale(
        'en',
        () => nekoExitLines(exit: null, selection: null),
      );
      expect(none.title, 'Server: —');
      expect(none.subtitle, isNull);
    });
  });
}

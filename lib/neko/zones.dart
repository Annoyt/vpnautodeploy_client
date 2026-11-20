import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:intl/intl.dart';

const _indicatorA = 0x1F1E6;
const _indicatorZ = 0x1F1FF;

/// «🇩🇪 Frankfurt» is `DE`. A name without a flag, such as `u1-de`, has no
/// country: guessing one from it would misplace servers.
String? nekoCountryOf(String name) {
  int? first;
  for (final rune in name.runes) {
    if (rune < _indicatorA || rune > _indicatorZ) {
      first = null;
    } else if (first == null) {
      first = rune;
    } else {
      return String.fromCharCodes([
        first - _indicatorA + 0x41,
        rune - _indicatorA + 0x41,
      ]);
    }
  }
  return null;
}

const _countries = {
  'AE': ('ОАЭ', 'UAE'),
  'AM': ('Армения', 'Armenia'),
  'AT': ('Австрия', 'Austria'),
  'AU': ('Австралия', 'Australia'),
  'BE': ('Бельгия', 'Belgium'),
  'BG': ('Болгария', 'Bulgaria'),
  'BR': ('Бразилия', 'Brazil'),
  'CA': ('Канада', 'Canada'),
  'CH': ('Швейцария', 'Switzerland'),
  'CZ': ('Чехия', 'Czechia'),
  'DE': ('Германия', 'Germany'),
  'DK': ('Дания', 'Denmark'),
  'EE': ('Эстония', 'Estonia'),
  'ES': ('Испания', 'Spain'),
  'FI': ('Финляндия', 'Finland'),
  'FR': ('Франция', 'France'),
  'GB': ('Великобритания', 'United Kingdom'),
  'GE': ('Грузия', 'Georgia'),
  'HK': ('Гонконг', 'Hong Kong'),
  'HU': ('Венгрия', 'Hungary'),
  'IE': ('Ирландия', 'Ireland'),
  'IL': ('Израиль', 'Israel'),
  'IN': ('Индия', 'India'),
  'IT': ('Италия', 'Italy'),
  'JP': ('Япония', 'Japan'),
  'KR': ('Южная Корея', 'South Korea'),
  'KZ': ('Казахстан', 'Kazakhstan'),
  'LT': ('Литва', 'Lithuania'),
  'LU': ('Люксембург', 'Luxembourg'),
  'LV': ('Латвия', 'Latvia'),
  'MD': ('Молдова', 'Moldova'),
  'NL': ('Нидерланды', 'Netherlands'),
  'NO': ('Норвегия', 'Norway'),
  'PL': ('Польша', 'Poland'),
  'PT': ('Португалия', 'Portugal'),
  'RO': ('Румыния', 'Romania'),
  'RS': ('Сербия', 'Serbia'),
  'RU': ('Россия', 'Russia'),
  'SE': ('Швеция', 'Sweden'),
  'SG': ('Сингапур', 'Singapore'),
  'TR': ('Турция', 'Turkey'),
  'TW': ('Тайвань', 'Taiwan'),
  'UA': ('Украина', 'Ukraine'),
  'US': ('США', 'United States'),
};

String nekoCountryName(String code) {
  final names = _countries[code.toUpperCase()];
  final ru = Intl.getCurrentLocale().startsWith('ru');
  final name = names == null ? code.toUpperCase() : (ru ? names.$1 : names.$2);
  return '${code.countryFlagEmoji} $name';
}

const _autoTypes = {
  GroupType.URLTest,
  GroupType.Fallback,
  GroupType.LoadBalance,
};

/// Where the first selector the Proxies page shows points.
class NekoSelection {
  const NekoSelection({
    required this.group,
    required this.member,
    required this.auto,
    required this.server,
    required this.autoMember,
    required this.zones,
  });

  final Group group;

  final String member;

  /// The pick chooses by itself: a url-test, fallback or load-balance.
  final bool auto;

  final String server;

  /// The member to pick for «Авто»: the first group that chooses by itself.
  final String? autoMember;

  final Map<String, List<String>> zones;
}

/// [groups] carry what each group runs now; [shown] has it cleared.
NekoSelection? nekoSelectionOf({
  required List<Group> shown,
  required List<Group> groups,
  required Map<String, String> selectedMap,
}) {
  final shownMain =
      shown.firstWhereOrNull((group) => group.type == GroupType.Selector) ??
      shown.firstOrNull;
  if (shownMain == null) return null;
  final main = groups.getGroup(shownMain.name) ?? shownMain;
  final member = main.getCurrentSelectedName(selectedMap[main.name] ?? '');
  final picked = groups.getGroup(member);
  final server = computeRealSelectedProxyState(
    main.name,
    groups: groups,
    selectedMap: selectedMap,
  ).proxyName;
  final zones = <String, List<String>>{};
  String? autoMember;
  for (final proxy in main.all) {
    final country = nekoCountryOf(proxy.name);
    if (country != null) {
      (zones[country] ??= []).add(proxy.name);
    } else if (_autoTypes.contains(groups.getGroup(proxy.name)?.type)) {
      autoMember ??= proxy.name;
    }
  }
  return NekoSelection(
    group: main,
    member: member,
    auto:
        _autoTypes.contains(main.type) ||
        (nekoCountryOf(member) == null && _autoTypes.contains(picked?.type)),
    server: server == main.name ? '' : server,
    autoMember: autoMember,
    zones: zones,
  );
}

/// The member of a zone to pick: the fastest last measured, else the first.
String nekoZonePick(List<String> members, DelayMap delays) {
  String? best;
  int? bestDelay;
  for (final member in members) {
    for (final byProxy in delays.values) {
      final delay = byProxy[member];
      if (delay == null || delay <= 0) continue;
      if (bestDelay == null || delay < bestDelay) {
        best = member;
        bestDelay = delay;
      }
    }
  }
  return best ?? members.first;
}

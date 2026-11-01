import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart';

/// Network memory (client plan E31): which server each automatic group of
/// our profile ran on, per network. Back in a known network the cascade
/// starts on what worked there, instead of on what worked in the last one
/// until its next check. Kept as `neko_networks.json`:
/// `{"enabled": true, "profiles": {"<id>": {"<network>": {"<group>": "<proxy>"}}}}`.
const nekoNetworksFile = 'neko_networks.json';

/// Networks remembered per profile; the oldest go first.
const _maxNetworks = 20;

const _unknownSsid = '<unknown ssid>';

/// A name for the network the phone is on, stable across visits: Wi-Fi by
/// its name when the app may read it, else by its private subnet (a home
/// router keeps one); mobile data as one network; Ethernet by subnet. Null
/// with no network, or with only the VPN's own.
String? nekoNetworkKey(
  List<ConnectivityResult> results, {
  String? ssid,
  List<NetworkInterface> interfaces = const [],
}) {
  String? subnet(bool Function(String name) named) {
    for (final interface in interfaces) {
      if (interface.name.startsWith('tun') || !named(interface.name)) continue;
      for (final address in interface.addresses) {
        if (address.type != InternetAddressType.IPv4) continue;
        final bytes = address.rawAddress;
        final private =
            bytes[0] == 10 ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] < 32) ||
            (bytes[0] == 192 && bytes[1] == 168);
        if (private) return '${bytes[0]}.${bytes[1]}.${bytes[2]}';
      }
    }
    return null;
  }

  if (results.contains(ConnectivityResult.wifi)) {
    final name = ssid?.trim().replaceAll('"', '');
    if (name != null && name.isNotEmpty && name != _unknownSsid) {
      return 'wifi:$name';
    }
    final net = subnet((name) => name.startsWith('wlan'));
    return net == null ? 'wifi' : 'wifi:$net';
  }
  if (results.contains(ConnectivityResult.ethernet)) {
    final net = subnet(
      (name) => name.startsWith('eth') || name.startsWith('en'),
    );
    return net == null ? 'ethernet' : 'ethernet:$net';
  }
  if (results.contains(ConnectivityResult.mobile)) return 'mobile';
  return null;
}

bool _alive(int? delay) => delay != null && delay > 0;

/// Worth remembering: the server each fallback group runs on now, when its
/// last test with the group's URL passed. A url-test group picks the
/// fastest on its own after a test, so only fallback groups are pinned.
Map<String, String> nekoAlivePicks(List<Group> groups, DelayMap delays) {
  final picks = <String, String>{};
  for (final group in groups) {
    final now = group.now;
    if (group.type != GroupType.Fallback || now == null || now.isEmpty) {
      continue;
    }
    final byUrl = delays[group.testUrl] ?? const {};
    final tested = byUrl[now] ?? _anyDelay(delays, now);
    if (_alive(tested)) picks[group.name] = now;
  }
  return picks;
}

int? _anyDelay(DelayMap delays, String proxy) {
  for (final byProxy in delays.values) {
    final delay = byProxy[proxy];
    if (delay != null) return delay;
  }
  return null;
}

/// What to pin on arrival: the remembered picks the profile still has and
/// that are not the group's server already.
Map<String, String> nekoPicksToRestore(
  List<Group> groups,
  Map<String, String> remembered,
) {
  final restore = <String, String>{};
  for (final group in groups) {
    final pick = remembered[group.name];
    if (pick == null || group.type != GroupType.Fallback) continue;
    if (group.now == pick) continue;
    if (group.all.any((proxy) => proxy.name == pick)) {
      restore[group.name] = pick;
    }
  }
  return restore;
}

/// The groups re-tested on arrival: every automatic one.
List<Group> nekoAutoGroups(List<Group> groups) => [
  for (final group in groups)
    if (group.type == GroupType.Fallback || group.type == GroupType.URLTest)
      group,
];

class NekoNetworkMemory {
  NekoNetworkMemory._();

  static Future<void> _writes = Future.value();

  static Future<File> _file() async {
    return File(join(await appPath.homeDirPath, nekoNetworksFile));
  }

  static Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final data = jsonDecode(await file.readAsString());
      return data is Map<String, dynamic> ? data : {};
    } on Exception {
      return {};
    }
  }

  static Future<void> _update(void Function(Map<String, dynamic> data) change) {
    return _writes = _writes.then((_) async {
      try {
        final data = await _read();
        change(data);
        final file = await _file();
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(jsonEncode(data));
        await temp.rename(file.path);
      } on Exception catch (error) {
        commonPrint.log(
          'network memory not saved: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
    });
  }

  /// On unless switched off in Tools.
  static Future<bool> enabled() async => (await _read())['enabled'] != false;

  static Future<void> setEnabled(bool enabled) {
    return _update((data) => data['enabled'] = enabled);
  }

  static Future<Map<String, String>> of(int profileId, String network) async {
    final profiles = (await _read())['profiles'];
    final networks = profiles is Map ? profiles['$profileId'] : null;
    final picks = networks is Map ? networks[network] : null;
    if (picks is! Map) return const {};
    return {
      for (final entry in picks.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  /// Merges [picks] into what the network has, most recent network last.
  static Future<void> remember(
    int profileId,
    String network,
    Map<String, String> picks,
  ) {
    if (picks.isEmpty) return Future.value();
    return _update((data) {
      final profiles = data['profiles'] is Map<String, dynamic>
          ? data['profiles'] as Map<String, dynamic>
          : <String, dynamic>{};
      final networks = profiles['$profileId'] is Map<String, dynamic>
          ? profiles['$profileId'] as Map<String, dynamic>
          : <String, dynamic>{};
      final known = networks.remove(network);
      networks[network] = {if (known is Map) ...known, ...picks};
      while (networks.length > _maxNetworks) {
        networks.remove(networks.keys.first);
      }
      profiles['$profileId'] = networks;
      data['profiles'] = profiles;
    });
  }
}

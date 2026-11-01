import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/network_memory.dart';
import 'package:fl_clash/neko/network_memory_manager.dart';
import 'package:fl_clash/neko/quota.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

class _Address implements InterfaceAddress {
  _Address(String value) : _address = InternetAddress(value);

  final InternetAddress _address;

  @override
  String get address => _address.address;

  @override
  InternetAddressType get type => _address.type;

  @override
  Uint8List get rawAddress => _address.rawAddress;

  @override
  int get prefixLength => 24;

  @override
  InternetAddress? get broadcast => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Interface implements NetworkInterface {
  _Interface(this.name, List<String> addresses)
    : addresses = [for (final value in addresses) _Address(value)];

  @override
  final String name;

  @override
  final List<InterfaceAddress> addresses;

  @override
  int get index => 0;
}

const _url = 'https://www.gstatic.com/generate_204';

class _FakeProxies extends ProxiesAction {
  static final calls = <String>[];

  @override
  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async => calls.add('pin $groupName $proxyName');

  @override
  Future<void> delayTestGroups(List<Group> groups) async =>
      calls.add('test ${groups.map((group) => group.name).join(',')}');

  @override
  Future<void> updateGroups() async => calls.add('refresh');
}

Group _group(
  String name,
  GroupType type,
  String? now, [
  List<String> all = const ['reality', 'hy2', 'ws'],
]) {
  return Group(
    name: name,
    type: type,
    now: now,
    testUrl: _url,
    all: [for (final proxy in all) Proxy(name: proxy, type: 'vless')],
  );
}

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('neko_networks');
    await useAppPaths(home);
  });

  tearDown(() => home.delete(recursive: true));

  group('the network', () {
    final wlan = _Interface('wlan0', ['192.168.1.37']);

    test('Wi-Fi by its name, else by its subnet', () {
      final wifi = [ConnectivityResult.wifi, ConnectivityResult.vpn];
      expect(
        nekoNetworkKey(wifi, ssid: '"Home"', interfaces: [wlan]),
        'wifi:Home',
      );
      expect(
        nekoNetworkKey(wifi, ssid: '<unknown ssid>', interfaces: [wlan]),
        'wifi:192.168.1',
      );
      expect(
        nekoNetworkKey(
          wifi,
          interfaces: [
            _Interface('tun0', ['172.19.0.1']),
            wlan,
          ],
        ),
        'wifi:192.168.1',
      );
      expect(nekoNetworkKey(wifi), 'wifi');
    });

    test('mobile data is one network; nothing or only the VPN is none', () {
      expect(nekoNetworkKey([ConnectivityResult.mobile]), 'mobile');
      expect(
        nekoNetworkKey(
          [ConnectivityResult.ethernet],
          interfaces: [
            _Interface('eth0', ['10.0.5.2']),
          ],
        ),
        'ethernet:10.0.5',
      );
      expect(nekoNetworkKey([ConnectivityResult.vpn]), isNull);
      expect(nekoNetworkKey([ConnectivityResult.none]), isNull);
    });
  });

  group('what to remember and restore', () {
    test('a fallback group running alive is remembered', () {
      final groups = [
        _group('Cascade', GroupType.Fallback, 'hy2'),
        _group('Auto', GroupType.URLTest, 'reality'),
        _group('Dead', GroupType.Fallback, 'ws'),
        _group('VPN', GroupType.Selector, 'Cascade'),
      ];
      final delays = {
        _url: {'hy2': 120, 'reality': 90, 'ws': -1},
      };
      expect(nekoAlivePicks(groups, delays), {'Cascade': 'hy2'});
    });

    test('a delay under another URL still counts', () {
      final groups = [_group('Cascade', GroupType.Fallback, 'hy2')];
      expect(
        nekoAlivePicks(groups, {
          'https://other.example': {'hy2': 50},
        }),
        {'Cascade': 'hy2'},
      );
    });

    test('restores only what the profile has and does not run already', () {
      final groups = [
        _group('Cascade', GroupType.Fallback, 'reality'),
        _group('Other', GroupType.Fallback, 'hy2'),
        _group('Auto', GroupType.URLTest, 'reality'),
      ];
      expect(
        nekoPicksToRestore(groups, {
          'Cascade': 'hy2',
          'Other': 'hy2',
          'Auto': 'ws',
          'Gone': 'ws',
        }),
        {'Cascade': 'hy2'},
      );
      expect(
        nekoPicksToRestore(groups, {'Cascade': 'removed-server'}),
        isEmpty,
      );
    });
  });

  group('the memory file', () {
    test('on by default; the switch is kept', () async {
      expect(await NekoNetworkMemory.enabled(), isTrue);
      await NekoNetworkMemory.setEnabled(false);
      expect(await NekoNetworkMemory.enabled(), isFalse);
    });

    test('per profile and network, merged, the oldest network goes', () async {
      await NekoNetworkMemory.remember(1, 'wifi:Home', {'Cascade': 'hy2'});
      await NekoNetworkMemory.remember(1, 'wifi:Home', {'Calls': 'reality'});
      await NekoNetworkMemory.remember(2, 'wifi:Home', {'Cascade': 'ws'});
      expect(await NekoNetworkMemory.of(1, 'wifi:Home'), {
        'Cascade': 'hy2',
        'Calls': 'reality',
      });
      expect(await NekoNetworkMemory.of(2, 'wifi:Home'), {'Cascade': 'ws'});
      for (var i = 0; i < 20; i++) {
        await NekoNetworkMemory.remember(1, 'net$i', {'Cascade': 'ws'});
      }
      expect(await NekoNetworkMemory.of(1, 'wifi:Home'), isEmpty);
      expect(await NekoNetworkMemory.of(1, 'net19'), {'Cascade': 'ws'});
    });

    test('a damaged file is no memory', () async {
      File('${home.path}/$nekoNetworksFile').writeAsStringSync('{not json');
      expect(await NekoNetworkMemory.of(1, 'mobile'), isEmpty);
      expect(await NekoNetworkMemory.enabled(), isTrue);
    });
  });

  group('the runner', () {
    late List<Group> groups;
    late List<String> calls;
    late int? profileId;

    NekoNetworkMemoryRunner runner() => NekoNetworkMemoryRunner(
      NekoNetworkMemoryHooks(
        profileId: () async => profileId,
        groups: () => groups,
        delays: () => {
          _url: {'hy2': 80, 'reality': 60},
        },
        changeProxy: (group, proxy) async {
          calls.add('pin $group $proxy');
          groups = [_group(group, GroupType.Fallback, proxy)];
        },
        testGroups: (tested) async =>
            calls.add('test ${tested.map((g) => g.name).join(',')}'),
        refreshGroups: () async => calls.add('refresh'),
      ),
    );

    setUp(() {
      groups = [_group('Cascade', GroupType.Fallback, 'reality')];
      calls = [];
      profileId = 7;
    });

    test('a known network starts on what worked there', () async {
      await NekoNetworkMemory.remember(7, 'wifi:Home', {'Cascade': 'hy2'});
      await runner().arrive('wifi:Home');
      expect(calls, ['pin Cascade hy2', 'test Cascade', 'refresh']);
      expect(await NekoNetworkMemory.of(7, 'wifi:Home'), {'Cascade': 'hy2'});
    });

    test('a new network is tested and remembered', () async {
      final memory = runner();
      await memory.arrive('mobile');
      expect(calls, ['test Cascade', 'refresh']);
      expect(await NekoNetworkMemory.of(7, 'mobile'), {'Cascade': 'reality'});
      calls.clear();
      await memory.arrive('mobile');
      expect(calls, isEmpty, reason: 'the same network again');
    });

    test('not our profile, VPN off or memory off: nothing', () async {
      profileId = null;
      await runner().arrive('wifi:Home');
      expect(calls, isEmpty);
      expect(await NekoNetworkMemory.of(7, 'wifi:Home'), isEmpty);
    });

    test('remembers again while the phone stays', () async {
      final memory = runner();
      await memory.arrive('mobile');
      groups = [_group('Cascade', GroupType.Fallback, 'hy2')];
      await memory.rememberNow();
      expect(await NekoNetworkMemory.of(7, 'mobile'), {'Cascade': 'hy2'});
    });
  });

  group('wired to the app', () {
    final profile = Profile.normal(url: 'https://main.example/sub/t');

    ProviderContainer container({bool start = true, Profile? current}) {
      final container = ProviderContainer(
        overrides: [
          isStartProvider.overrideWithValue(start),
          currentProfileProvider.overrideWithValue(current),
          groupsProvider.overrideWithValue([
            _group('Cascade', GroupType.Fallback, 'reality'),
          ]),
          delayDataSourceProvider.overrideWithBuild(
            (_, _) => {
              _url: {'reality': 60},
            },
          ),
          proxiesActionProvider.overrideWith(_FakeProxies.new),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(_FakeProxies.calls.clear);

    test('our profile only, with the VPN on and memory on', () async {
      expect(
        await nekoOurProfileId(container(start: false, current: profile).read),
        isNull,
      );
      expect(await nekoOurProfileId(container().read), isNull);
      expect(
        await nekoOurProfileId(container(current: profile).read),
        isNull,
        reason: 'no plan: not our profile',
      );
      await NekoPlanStore.put(profile.id, const NekoPlan(paid: true));
      expect(
        await nekoOurProfileId(container(current: profile).read),
        profile.id,
      );
      await NekoNetworkMemory.setEnabled(false);
      expect(await nekoOurProfileId(container(current: profile).read), isNull);
    });

    test('the hooks reach the providers and the proxies action', () async {
      final hooks = nekoNetworkMemoryHooks(container(current: profile).read);
      expect(hooks.groups().single.name, 'Cascade');
      expect(hooks.delays()[_url], {'reality': 60});
      await hooks.changeProxy('Cascade', 'hy2');
      await hooks.testGroups(hooks.groups());
      await hooks.refreshGroups();
      expect(_FakeProxies.calls, [
        'pin Cascade hy2',
        'test Cascade',
        'refresh',
      ]);
      expect(await hooks.profileId(), isNull);
    });

    test('the current network, also when the device lists nothing', () async {
      final read = container().read;
      expect(
        await nekoCurrentNetwork(read, [
          ConnectivityResult.mobile,
        ], () async => []),
        'mobile',
      );
      expect(
        await nekoCurrentNetwork(read, [
          ConnectivityResult.wifi,
        ], () async => throw const SocketException('denied')),
        'wifi',
      );
    });
  });
}

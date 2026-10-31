import 'dart:io';
import 'dart:math';

import 'package:fl_clash/neko/gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

class _Interface implements NetworkInterface {
  _Interface(this.name, List<String> addresses)
    : addresses = [for (final value in addresses) InternetAddress(value)];

  @override
  final String name;

  @override
  final List<InternetAddress> addresses;

  @override
  int get index => 0;
}

const _share = NekoGatewayShare(port: 7891, username: 'u', password: 'p');

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('neko_gateway');
    await useAppPaths(home);
  });

  tearDown(() => home.delete(recursive: true));

  File gatewayFile() => File('${home.path}/$nekoGatewayFile');

  group('the code', () {
    test('a link carries the addresses, the port and the password', () {
      final link = nekoGatewayLink(_share, ['192.168.43.1', '10.0.0.5']);
      final join = nekoGatewayFromLink(link)!;
      expect(join.hosts, ['192.168.43.1', '10.0.0.5']);
      expect(join.port, 7891);
      expect(join.username, 'u');
      expect(join.password, 'p');
      expect(Uri.parse(link).scheme, 'nekovpn');
    });

    test('anything else is no gateway', () {
      for (final text in <String?>[
        null,
        '',
        'https://example.com/sub/x',
        'nekovpn://install-config?url=https://example.com',
        'nekovpn://gateway?h=10.0.0.1&u=u&k=p',
        'nekovpn://gateway?h=10.0.0.1&p=70000&u=u&k=p',
        'nekovpn://gateway?h=gateway.local&p=7891&u=u&k=p',
        'nekovpn://gateway?h=10.0.0.1&p=7891&u=u',
      ]) {
        expect(nekoGatewayFromLink(text), isNull, reason: '$text');
      }
    });

    test('the scanner takes the first gateway code', () {
      final link = nekoGatewayLink(_share, ['10.0.0.1']);
      expect(
        nekoGatewayLinkFromQrCodes([null, 'junk', ' $link ', 'other']),
        link,
      );
      expect(nekoGatewayLinkFromQrCodes(['https://example.com']), isNull);
    });

    test('each share gets its own password', () {
      final random = Random(1);
      final first = NekoGatewayShare.create(random: random);
      final second = NekoGatewayShare.create(random: random);
      expect(first.port, nekoGatewayPort);
      expect(first.password, hasLength(24));
      expect(first.password, isNot(second.password));
      expect(first.username, isNot(second.username));
    });
  });

  group('the file', () {
    test('nothing chosen is no gateway', () async {
      final gateway = await nekoReadGateway();
      expect(gateway.share, isNull);
      expect(gateway.join, isNull);
    });

    test('what is written is read back, as the core reads it', () async {
      await nekoWriteGateway(const NekoGateway(share: _share));
      final shared = await nekoReadGateway();
      expect(shared.share?.password, 'p');
      expect(shared.join, isNull);
      expect(
        gatewayFile().readAsStringSync(),
        '{"share":{"port":7891,"username":"u","password":"p"},"join":null}',
      );
      expect(File('${gatewayFile().path}.tmp').existsSync(), isFalse);

      final join = nekoGatewayFromLink(nekoGatewayLink(_share, ['10.0.0.1']));
      await nekoWriteGateway(NekoGateway(join: join));
      final joined = await nekoReadGateway();
      expect(joined.share, isNull);
      expect(joined.join?.hosts, ['10.0.0.1']);
    });

    test('junk is no gateway', () async {
      for (final text in [
        '{not json',
        '[]',
        '{"share":{"port":0,"username":"u","password":"p"}}',
        '{"join":{"hosts":[],"port":7891,"username":"u","password":"p"}}',
      ]) {
        gatewayFile().writeAsStringSync(text);
        final gateway = await nekoReadGateway();
        expect(gateway.share, isNull, reason: text);
        expect(gateway.join, isNull, reason: text);
      }
    });
  });

  group("this phone's addresses", () {
    test('only private IPv4 a neighbour can reach', () async {
      final hosts = await nekoGatewayHosts(
        list: () async => [
          _Interface('wlan0', ['192.168.1.5', 'fe80::1']),
          _Interface('swlan0', ['10.71.33.1']),
          _Interface('tun0', ['172.19.0.1']),
          _Interface('rmnet0', ['100.64.1.2']),
          _Interface('eth0', ['172.16.0.9', '172.32.0.1']),
        ],
      );
      expect(hosts, ['192.168.1.5', '10.71.33.1', '172.16.0.9']);
    });

    test('a device that cannot list them has none', () async {
      final hosts = await nekoGatewayHosts(
        list: () async => throw const SocketException('denied'),
      );
      expect(hosts, isEmpty);
    });
  });
}

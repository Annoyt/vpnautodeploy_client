import 'dart:io';

import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/secure_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

String _fixed(int length) => 'x' * length;

const _login = 'nekoxxxxxxxx:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';

void main() {
  group('locking the port', () {
    test('a fresh install gets a login and stops offering the port', () {
      final locked = nekoSecureProxy(
        const VpnProps(),
        const NetworkProps(),
        secret: _fixed,
      );
      expect(locked.vpn.systemProxy, isFalse);
      final login = locked.network.authentication;
      expect(login.enable, isTrue);
      expect(login.username, 'nekoxxxxxxxx');
      expect(login.password, _fixed(32));
      expect(login.credentials, [_login]);
    });

    test('everything else stays as it was', () {
      const vpn = VpnProps(ipv6: true, allowBypass: false, dnsHijacking: true);
      const network = NetworkProps(
        bypassPrivateRoute: false,
        appendSystemDns: true,
      );
      final locked = nekoSecureProxy(vpn, network, secret: _fixed);
      expect(locked.vpn, vpn.copyWith(systemProxy: false));
      expect(
        locked.network,
        network.copyWith(authentication: locked.network.authentication),
      );
    });

    test('a login that works is kept', () {
      const network = NetworkProps(
        authentication: AuthenticationProps(
          enable: true,
          username: 'me',
          password: 'secret',
        ),
      );
      final locked = nekoSecureProxy(const VpnProps(), network, secret: _fixed);
      expect(locked.network, network);
      expect(locked.vpn.systemProxy, isFalse);
    });

    test('a login that does not work is replaced', () {
      for (final login in const [
        AuthenticationProps(username: 'me', password: 'secret'),
        AuthenticationProps(enable: true, password: 'secret'),
        AuthenticationProps(enable: true, username: 'me'),
      ]) {
        final locked = nekoSecureProxy(
          const VpnProps(),
          NetworkProps(authentication: login),
          secret: _fixed,
        );
        expect(locked.network.authentication.credentials, [
          _login,
        ], reason: '$login');
      }
    });

    test('the default login is random and has no colon', () {
      final first = nekoSecureProxy(
        const VpnProps(),
        const NetworkProps(),
      ).network.authentication;
      final second = nekoSecureProxy(
        const VpnProps(),
        const NetworkProps(),
      ).network.authentication;
      expect(first.username, hasLength(12));
      expect(first.username, startsWith('neko'));
      expect(first.password, hasLength(32));
      expect(first.password, isNot(second.password));
      // A colon in the username would break the login (views/config/general).
      expect('${first.username}${first.password}', isNot(contains(':')));
    });
  });

  group('once per install', () {
    late Directory home;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('neko_secure_proxy');
      await useAppPaths(home);
    });

    tearDown(() => home.delete(recursive: true));

    File flag() => File('${home.path}/$nekoSecureProxyFile');

    test('not done until marked', () async {
      expect(await nekoSecureProxyDone(), isFalse);
      await nekoMarkSecureProxyDone();
      expect(await nekoSecureProxyDone(), isTrue);
      expect(flag().readAsStringSync(), '{"version":$nekoSecureProxyVersion}');
      expect(File('${flag().path}.tmp').existsSync(), isFalse);
    });

    test('junk or another version is not done', () async {
      for (final text in [
        '{not json',
        '[]',
        '{}',
        '{"version":0}',
        '{"version":"1"}',
      ]) {
        flag().writeAsStringSync(text);
        expect(await nekoSecureProxyDone(), isFalse, reason: text);
      }
    });

    test('on Android the port is locked once, then left alone', () async {
      var settings = (vpn: const VpnProps(), network: const NetworkProps());
      var writes = 0;
      Future<bool> apply() => nekoApplySecureProxy(
        android: true,
        read: () => settings,
        write: (value) {
          settings = value;
          writes++;
        },
      );
      expect(await apply(), isTrue);
      expect(settings.vpn.systemProxy, isFalse);
      expect(settings.network.authentication.credentials, hasLength(1));
      expect(await nekoSecureProxyDone(), isTrue);
      // Someone turns the system proxy back on: it stays on.
      settings = (
        vpn: settings.vpn.copyWith(systemProxy: true),
        network: settings.network,
      );
      expect(await apply(), isFalse);
      expect(settings.vpn.systemProxy, isTrue);
      expect(writes, 1);
    });

    test('other systems keep upstream behaviour', () async {
      var writes = 0;
      final changed = await nekoApplySecureProxy(
        android: false,
        read: () => (vpn: const VpnProps(), network: const NetworkProps()),
        write: (_) {
          writes++;
        },
      );
      expect(changed, isFalse);
      expect(writes, 0);
      expect(await nekoSecureProxyDone(), isFalse);
    });
  });
}

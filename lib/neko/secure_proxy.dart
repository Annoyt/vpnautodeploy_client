import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart';

/// NekoVPN keeps the other apps on the phone off its local proxy.
///
/// The core listens on 127.0.0.1 at the mixed port, and any app on the phone
/// can connect there, an app kept out of the VPN as well, and see where its
/// requests come out: the server's address. Upstream leaves the port without
/// a login and hands it to every app as the VPN's HTTP proxy. NekoVPN gives
/// the port a random login and stops handing it out, once per install:
/// whoever turns either back on later keeps that choice. The app's own
/// requests carry the login (lib/common/http.dart), and the core asks it of
/// loopback clients too (`skip-auth-prefixes: []`, lib/common/task.dart).
const nekoSecureProxyFile = 'neko_secure_proxy.json';

/// Raised when these defaults change, so that every install gets them again.
const nekoSecureProxyVersion = 1;

typedef NekoProxySettings = ({VpnProps vpn, NetworkProps network});

/// [vpn] and [network] with the port locked: the VPN no longer offers it as
/// a proxy, and it gets a login made by [secret] unless one already works.
NekoProxySettings nekoSecureProxy(
  VpnProps vpn,
  NetworkProps network, {
  String Function(int length) secret = generateRandomSecret,
}) {
  final login = network.authentication;
  final works =
      login.enable && login.username.isNotEmpty && login.password.isNotEmpty;
  return (
    vpn: vpn.copyWith(systemProxy: false),
    network: works
        ? network
        : network.copyWith(
            authentication: login.copyWith(
              enable: true,
              username: 'neko${secret(8)}',
              password: secret(32),
            ),
          ),
  );
}

Future<File> _file() async {
  return File(join(await appPath.homeDirPath, nekoSecureProxyFile));
}

/// Whether this install already got the current defaults.
Future<bool> nekoSecureProxyDone() async {
  try {
    final file = await _file();
    if (!await file.exists()) return false;
    final data = jsonDecode(await file.readAsString());
    return data is Map && data['version'] == nekoSecureProxyVersion;
  } on Exception {
    return false;
  }
}

/// Notes in one step that this install got the current defaults.
Future<void> nekoMarkSecureProxyDone() async {
  final file = await _file();
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(jsonEncode({'version': nekoSecureProxyVersion}));
  await temp.rename(file.path);
}

/// Applies [nekoSecureProxy] once per install. Only on Android: there every
/// app can reach the port, while a desktop's system proxy cannot carry a
/// login and would stop working. True when the settings were changed.
Future<bool> nekoApplySecureProxy({
  required bool android,
  required NekoProxySettings Function() read,
  required void Function(NekoProxySettings settings) write,
  Future<bool> Function() done = nekoSecureProxyDone,
  Future<void> Function() markDone = nekoMarkSecureProxyDone,
}) async {
  if (!android || await done()) return false;
  final current = read();
  write(nekoSecureProxy(current.vpn, current.network));
  await markDone();
  return true;
}

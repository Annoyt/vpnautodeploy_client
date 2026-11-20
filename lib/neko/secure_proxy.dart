import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart';

// Any app on the phone can reach the core's mixed port, even one kept out of
// the VPN, and learn the server's address through it: lock the port once.
const nekoSecureProxyFile = 'neko_secure_proxy.json';
const nekoSecureProxyVersion = 1;

typedef NekoProxySettings = ({VpnProps vpn, NetworkProps network});

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

Future<void> nekoMarkSecureProxyDone() async {
  final file = await _file();
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(jsonEncode({'version': nekoSecureProxyVersion}));
  await temp.rename(file.path);
}

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

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:path/path.dart';

/// The gateway (client plan E30, docs/MULTIPATH.md 3.2): this phone shares
/// its network with a neighbour that has none, or goes out through a
/// neighbour's. The core reads [nekoGatewayFile] each time it loads the
/// profile (core/neko_gateway.go). Sharing opens a listener with a password
/// on the local network. Joining sends every server, the DNS and the direct
/// traffic through the neighbour, while the tunnel itself stays this
/// phone's own, with its own key.
const nekoGatewayFile = 'neko_gateway.json';

const nekoGatewayPort = 7891;

/// This phone shares: the listener's port and password.
class NekoGatewayShare {
  const NekoGatewayShare({
    required this.port,
    required this.username,
    required this.password,
  });

  final int port;
  final String username;
  final String password;

  /// A fresh password, so that a code shown once is not good forever.
  factory NekoGatewayShare.create({
    int port = nekoGatewayPort,
    Random? random,
  }) {
    return NekoGatewayShare(
      port: port,
      username: _token(random, 6),
      password: _token(random, 18),
    );
  }

  Map<String, Object?> toJson() => {
    'port': port,
    'username': username,
    'password': password,
  };

  static NekoGatewayShare? fromJson(Object? json) {
    if (json is! Map) return null;
    final port = json['port'];
    final username = json['username'];
    final password = json['password'];
    if (port is! int || !_validPort(port)) return null;
    if (username is! String || username.isEmpty) return null;
    if (password is! String || password.isEmpty) return null;
    return NekoGatewayShare(port: port, username: username, password: password);
  }
}

/// This phone goes out through a neighbour: its addresses on the local
/// network, the port and the password from the neighbour's code.
class NekoGatewayJoin {
  const NekoGatewayJoin({
    required this.hosts,
    required this.port,
    required this.username,
    required this.password,
  });

  final List<String> hosts;
  final int port;
  final String username;
  final String password;

  Map<String, Object?> toJson() => {
    'hosts': hosts,
    'port': port,
    'username': username,
    'password': password,
  };

  static NekoGatewayJoin? fromJson(Object? json) {
    if (json is! Map) return null;
    final hosts = json['hosts'];
    final port = json['port'];
    final username = json['username'];
    final password = json['password'];
    if (hosts is! List) return null;
    final addresses = _addresses(hosts.whereType<String>());
    if (addresses.isEmpty) return null;
    if (port is! int || !_validPort(port)) return null;
    if (username is! String || username.isEmpty) return null;
    if (password is! String || password.isEmpty) return null;
    return NekoGatewayJoin(
      hosts: addresses,
      port: port,
      username: username,
      password: password,
    );
  }
}

/// What the app chose: share, join, or neither. Never both: joining wins
/// in the core, and the screen clears the other side.
class NekoGateway {
  const NekoGateway({this.share, this.join});

  final NekoGatewayShare? share;
  final NekoGatewayJoin? join;

  Map<String, Object?> toJson() => {
    'share': share?.toJson(),
    'join': join?.toJson(),
  };

  static NekoGateway fromJson(Object? json) {
    if (json is! Map) return const NekoGateway();
    return NekoGateway(
      share: NekoGatewayShare.fromJson(json['share']),
      join: NekoGatewayJoin.fromJson(json['join']),
    );
  }
}

bool _validPort(int port) => port > 0 && port < 65536;

String _token(Random? random, int bytes) {
  final source = random ?? Random.secure();
  final values = List<int>.generate(bytes, (_) => source.nextInt(256));
  return base64Url.encode(values).replaceAll('=', '');
}

/// The addresses that parse, IPv4 and IPv6; a name is not taken: the
/// neighbour is always reached by its address on the local network.
List<String> _addresses(Iterable<String> values) {
  final addresses = <String>[];
  for (final value in values) {
    final address = InternetAddress.tryParse(value.trim());
    if (address != null && !addresses.contains(address.address)) {
      addresses.add(address.address);
    }
  }
  return addresses;
}

Future<File> _file() async {
  return File(join(await appPath.homeDirPath, nekoGatewayFile));
}

/// The choice in force; nothing when nothing was chosen or the file is
/// unreadable.
Future<NekoGateway> nekoReadGateway() async {
  try {
    final file = await _file();
    if (!await file.exists()) return const NekoGateway();
    return NekoGateway.fromJson(jsonDecode(await file.readAsString()));
  } on Exception {
    return const NekoGateway();
  }
}

/// Saves the choice in one step: the core never reads half a file.
Future<void> nekoWriteGateway(NekoGateway gateway) async {
  final file = await _file();
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(jsonEncode(gateway.toJson()));
  await temp.rename(file.path);
}

/// The link the sharing phone shows as a code.
String nekoGatewayLink(NekoGatewayShare share, Iterable<String> hosts) {
  return Uri(
    scheme: 'nekovpn',
    host: 'gateway',
    queryParameters: {
      'h': hosts.join(','),
      'p': '${share.port}',
      'u': share.username,
      'k': share.password,
    },
  ).toString();
}

/// The neighbour's side of a scanned link; null for anything else.
NekoGatewayJoin? nekoGatewayFromLink(String? text) {
  final uri = Uri.tryParse(text?.trim() ?? '');
  if (uri == null || uri.scheme != 'nekovpn' || uri.host != 'gateway') {
    return null;
  }
  final query = uri.queryParameters;
  return NekoGatewayJoin.fromJson({
    'hosts': (query['h'] ?? '').split(','),
    'port': int.tryParse(query['p'] ?? ''),
    'username': query['u'],
    'password': query['k'],
  });
}

/// For the scanner: the first code that is a gateway link.
String? nekoGatewayLinkFromQrCodes(Iterable<String?> values) {
  for (final value in values) {
    if (nekoGatewayFromLink(value) != null) return value!.trim();
  }
  return null;
}

/// Whether an address is one a neighbour on the same local network can
/// reach: private IPv4 (RFC 1918). The VPN's own interface and the
/// fake-IP range are not.
bool nekoGatewayReachable(String interfaceName, InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  if (interfaceName.startsWith('tun')) return false;
  final bytes = address.rawAddress;
  return bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] < 32) ||
      (bytes[0] == 192 && bytes[1] == 168);
}

/// This phone's addresses a neighbour can reach: on its hotspot and on any
/// Wi-Fi it is on.
Future<List<String>> nekoGatewayHosts({
  Future<List<NetworkInterface>> Function()? list,
}) async {
  try {
    final interfaces = await (list ?? NetworkInterface.list)();
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (nekoGatewayReachable(interface.name, address)) address.address,
    ];
  } on Exception {
    return const [];
  }
}

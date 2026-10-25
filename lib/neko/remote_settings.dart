import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';

import 'version.dart';

/// The public half of the key the bot repository's scripts/neko_settings.py
/// signs with, raw Ed25519 in base64. An app trusts only the key it was
/// built with, so a new key needs a release carrying it first.
const nekoSettingsPublicKey = 'ID6b87cc4SRPMv/CW3y0cvHh3TRvyK7ytx6/6Db6R7I=';

/// Where the settings are asked for until a signed document names others.
const nekoSettingsEndpoints = [
  'https://autonekovpn.duckdns.org:9443',
  'https://sub.nekoweather.xyz:2096',
];

const _settingsPath = '/neko/settings';
const _timeout = Duration(seconds: 20);
final _version = RegExp(r'^\d+\.\d+\.\d+-neko\.\d+$');
final _origin = RegExp(r'^https://[^/\s]+$');

/// An announcement the service wants every user to read once.
class NekoMessage {
  const NekoMessage({required this.id, required this.ru, this.en, this.url});

  final String id;
  final String ru;
  final String? en;
  final String? url;

  /// Russian for a Russian locale, English otherwise when there is one.
  String get text {
    if (Intl.getCurrentLocale().startsWith('ru')) return ru;
    return en ?? ru;
  }
}

/// The service's remote settings, schema 1 (the bot's AGENTS.md, section 40).
class NekoSettings {
  const NekoSettings({
    required this.version,
    required this.endpoints,
    this.minVersion,
    this.message,
    this.flags = const {},
  });

  final int version;
  final List<String> endpoints;
  final String? minVersion;
  final NekoMessage? message;
  final Map<String, Object> flags;

  /// Null for a document this app cannot use: another schema, a version
  /// that is not a positive number, no https endpoint.
  static NekoSettings? fromDoc(Object? doc) {
    if (doc is! Map<String, dynamic> || doc['schema'] != 1) return null;
    final version = doc['version'];
    if (version is! int || version < 1) return null;
    final endpoints = _strings(doc['endpoints']).where(_origin.hasMatch);
    if (endpoints.isEmpty) return null;
    return NekoSettings(
      version: version,
      endpoints: endpoints.toList(),
      minVersion: _minVersion(doc['min_version']),
      message: _message(doc['message']),
      flags: _flags(doc['flags']),
    );
  }
}

Iterable<String> _strings(Object? raw) {
  return raw is List ? raw.whereType<String>() : const [];
}

String? _minVersion(Object? raw) {
  return raw is String && _version.hasMatch(raw) ? raw : null;
}

NekoMessage? _message(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  final ru = raw['ru'];
  if (id is! String || id.trim().isEmpty || ru is! String) return null;
  final en = raw['en'];
  final url = raw['url'];
  return NekoMessage(
    id: id,
    ru: ru,
    en: en is String ? en : null,
    url: url is String && url.startsWith('https://') ? url : null,
  );
}

Map<String, Object> _flags(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final MapEntry(:key, :value) in raw.entries)
      if (key is String && (value is bool || value is num || value is String))
        key: value as Object,
  };
}

/// The settings of a signed document `{kid, doc, sig}` (doc and sig in
/// base64) when the signature over exactly the doc bytes holds.
Future<NekoSettings?> nekoVerifySettings(
  Object? envelope, {
  String publicKey = nekoSettingsPublicKey,
}) async {
  if (envelope is! Map) return null;
  final doc = _base64(envelope['doc']);
  final sig = _base64(envelope['sig']);
  if (doc == null || sig == null || sig.length != 64) return null;
  final key = SimplePublicKey(
    base64.decode(publicKey),
    type: KeyPairType.ed25519,
  );
  final signature = Signature(sig, publicKey: key);
  if (!await Ed25519().verify(doc, signature: signature)) return null;
  try {
    return NekoSettings.fromDoc(jsonDecode(utf8.decode(doc)));
  } on FormatException {
    return null;
  }
}

List<int>? _base64(Object? raw) {
  if (raw is! String) return null;
  try {
    return base64.decode(raw);
  } on FormatException {
    return null;
  }
}

/// The last document accepted, kept signed and checked again on every
/// read, and the messages already shown: `neko_settings.json` next to the
/// app's data.
class NekoSettingsStore {
  NekoSettingsStore._();

  static Future<File> _file() async {
    return File(join(await appPath.homeDirPath, 'neko_settings.json'));
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

  static Future<void> _write(Map<String, dynamic> data) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(data));
  }

  /// The settings in force: the kept document, if it still verifies.
  static Future<NekoSettings?> current({
    String publicKey = nekoSettingsPublicKey,
  }) async {
    final signed = (await _read())['signed'];
    return nekoVerifySettings(signed, publicKey: publicKey);
  }

  /// Keeps [envelope] when it verifies and is newer than the kept one;
  /// returns its settings then, null otherwise.
  static Future<NekoSettings?> offer(
    Object? envelope, {
    String publicKey = nekoSettingsPublicKey,
  }) async {
    final offered = await nekoVerifySettings(envelope, publicKey: publicKey);
    if (offered == null) return null;
    final data = await _read();
    final kept = await nekoVerifySettings(data['signed'], publicKey: publicKey);
    if (kept != null && kept.version >= offered.version) return null;
    data['signed'] = envelope;
    await _write(data);
    return offered;
  }

  static Future<bool> wasShown(String id) async {
    final shown = (await _read())['shown'];
    return shown is List && shown.contains(id);
  }

  static Future<void> markShown(String id) async {
    final data = await _read();
    final shown = _strings(data['shown']).toList();
    if (!shown.contains(id)) shown.add(id);
    data['shown'] = shown;
    await _write(data);
  }
}

/// GET [url] as JSON, for [nekoRefreshSettings].
Future<Object?> nekoGetJson(Dio dio, String url) async {
  final options = Options(responseType: ResponseType.json);
  final response = await dio.get<Object>(url, options: options);
  return response.data;
}

/// Asks the endpoints (the kept document's, then the built-in ones) for
/// the settings and keeps the first signed answer when it is newer.
/// Returns the settings in force afterwards; null before any arrived.
Future<NekoSettings?> nekoRefreshSettings({
  required Future<Object?> Function(String url) get,
  String publicKey = nekoSettingsPublicKey,
}) async {
  final kept = await NekoSettingsStore.current(publicKey: publicKey);
  final endpoints = {...?kept?.endpoints, ...nekoSettingsEndpoints};
  for (final endpoint in endpoints) {
    try {
      final envelope = await get('$endpoint$_settingsPath').timeout(_timeout);
      final settings = await nekoVerifySettings(envelope, publicKey: publicKey);
      if (settings == null) continue;
      final offered = NekoSettingsStore.offer(envelope, publicKey: publicKey);
      return await offered ?? kept;
    } on Exception catch (error) {
      commonPrint.log(
        'remote settings from $endpoint: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    }
  }
  return kept;
}

/// Whether [settings] want this build updated: [installed] is older than
/// their `min_version`. A version that cannot be read asks for nothing.
bool nekoUpdateRequired(NekoSettings settings, {required String installed}) {
  final minVersion = settings.minVersion;
  if (minVersion == null) return false;
  try {
    return compareNekoVersions(installed, minVersion) < 0;
  } on FormatException {
    return false;
  }
}

/// The message of [settings] when it has not been shown yet.
Future<NekoMessage?> nekoMessageToShow(NekoSettings settings) async {
  final message = settings.message;
  if (message == null || await NekoSettingsStore.wasShown(message.id)) {
    return null;
  }
  return message;
}

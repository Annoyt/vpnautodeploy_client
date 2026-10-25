import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';

import 'brand.dart';

const _timeout = Duration(seconds: 20);
const _maxDelays = 30;
final _subPath = RegExp(r'^/sub/([0-9a-f]{32})$');

/// The bot's link that runs /sos: the last resort when the app reaches none
/// of the service's addresses.
const nekoSosBotUrl = '$nekoBotUrl?start=sos';

/// The token of our subscription among [urls]: the first
/// `https://<one of [origins]>/sub/<token>`. Null without one.
String? nekoServiceToken(Iterable<String> urls, Iterable<String> origins) {
  for (final url in urls) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') continue;
    if (!origins.contains(uri.origin)) continue;
    final match = _subPath.firstMatch(uri.path);
    if (match != null) return match.group(1);
  }
  return null;
}

/// What the app tells the service with an SOS (the bot's AGENTS.md,
/// section 41): no addresses, no history, only facts about the app.
Map<String, Object?> nekoSosReport({
  required String app,
  required String platform,
  required String? network,
  required bool vpnRunning,
  required DateTime? profileUpdated,
  required int? settingsVersion,
  required Map<String, int?> delays,
  DateTime? now,
}) {
  final updated = profileUpdated;
  final age = updated == null
      ? null
      : (now ?? DateTime.now()).difference(updated).inMinutes;
  return {
    'app': app,
    'platform': platform,
    'network': network,
    'vpn_running': vpnRunning,
    'profile_age_min': age,
    'settings_version': settingsVersion,
    'delays': [
      for (final MapEntry(:key, :value) in delays.entries.take(_maxDelays))
        {'name': key, 'ms': value},
    ],
  };
}

/// The service's answer to an SOS.
class NekoSosAnswer {
  const NekoSosAnswer({
    required this.status,
    required this.lines,
    this.emergency,
  });

  /// `reported`, `repeat` (one was sent less than 10 min ago) or `no_key`.
  final String status;
  final List<String> lines;

  /// The emergency profile, to add next to the main one.
  final String? emergency;

  static NekoSosAnswer? fromJson(Object? json) {
    if (json is! Map) return null;
    final status = json['status'];
    final lines = json['lines'];
    if (status is! String || lines is! List) return null;
    final emergency = json['emergency'];
    return NekoSosAnswer(
      status: status,
      lines: lines.whereType<String>().toList(),
      emergency: emergency is String && emergency.startsWith('https://')
          ? emergency
          : null,
    );
  }
}

/// Sends [report] for [token] to [origins] in order; the first answer wins.
/// Null when none answered: the page then offers the bot and a copy.
Future<NekoSosAnswer?> nekoSendSos(
  String token,
  Map<String, Object?> report, {
  required Iterable<String> origins,
  required Future<Object?> Function(String url, Object body) post,
}) async {
  for (final origin in origins) {
    try {
      final url = '$origin/api/neko/sos/$token';
      final answer = NekoSosAnswer.fromJson(
        await post(url, report).timeout(_timeout),
      );
      if (answer != null) return answer;
    } on Exception catch (error) {
      commonPrint.log(
        'sos to $origin: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    }
  }
  return null;
}

/// POST [body] as JSON and read the answer as JSON, for [nekoSendSos].
Future<Object?> nekoPostJson(Dio dio, String url, Object body) async {
  final options = Options(
    responseType: ResponseType.json,
    contentType: Headers.jsonContentType,
  );
  final response = await dio.post<Object>(url, data: body, options: options);
  return response.data;
}

/// The networks the device is on (`wifi`, `mobile`, …), null when unknown.
Future<String?> nekoNetworkType() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return results.map((result) => result.name).join('+');
  } on Exception {
    return null;
  }
}

/// Every proxy's last measured delay, from the app's delay map.
Map<String, int?> nekoDelays(Map<String, Map<String, int?>> delayMap) {
  final delays = <String, int?>{};
  for (final byProxy in delayMap.values) {
    delays.addAll(byProxy);
  }
  return delays;
}

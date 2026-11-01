import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:path/path.dart';

import 'quota.dart';

/// The header the NekoVPN bot sends with a profile: this very profile on
/// each of its mirror domains, comma-separated https URLs.
const nekoMirrorsHeader = 'nekovpn-mirrors';

const _maxMirrors = 5;

/// The mirrors a subscription answer names, in its order: https only, at
/// most five, without the profile's own [url] and repeats.
List<String> nekoMirrorsFromHeader(String? header, {required String url}) {
  final mirrors = <String>[];
  for (final part in (header ?? '').split(',')) {
    final mirror = part.trim();
    final uri = Uri.tryParse(mirror);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
    if (mirror == url || mirrors.contains(mirror)) continue;
    mirrors.add(mirror);
    if (mirrors.length == _maxMirrors) break;
  }
  return mirrors;
}

/// The mirrors each profile's last answer named, kept next to the app's
/// data as `neko_mirrors.json`: `{"<profile id>": ["https://…"]}`. Outside
/// the profile model on purpose: a field there is a database migration
/// in upstream's schema at every merge.
class NekoMirrorStore {
  NekoMirrorStore._();

  static Future<void> _writes = Future.value();

  static Future<File> _file() async {
    return File(join(await appPath.homeDirPath, 'neko_mirrors.json'));
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

  static Future<List<String>> of(int profileId) async {
    final mirrors = (await _read())['$profileId'];
    if (mirrors is! List) return const [];
    return mirrors.whereType<String>().toList();
  }

  /// Replaces the profile's list; an empty one removes it. One write at a
  /// time, and a failed one only logs: the mirrors are a spare.
  static Future<void> put(int profileId, List<String> mirrors) {
    return _writes = _writes.then((_) async {
      try {
        final data = await _read();
        if (mirrors.isEmpty) {
          data.remove('$profileId');
        } else {
          data['$profileId'] = mirrors;
        }
        final file = await _file();
        await file.writeAsString(jsonEncode(data));
      } on Exception catch (error) {
        commonPrint.log(
          'mirrors not saved: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
    });
  }
}

/// Downloads a URL profile from [url] or, when that fails, from the
/// mirrors its last answer named, in that order. The answer's headers
/// replace the stored mirrors and plan. When no address answers, the
/// profile's own error is the one rethrown.
Future<Response<Uint8List>> nekoDownloadProfile(
  int profileId,
  String url, {
  required Future<Response<Uint8List>> Function(String url) download,
}) async {
  final response = await _fromAnyAddress(profileId, url, download);
  final header = response.headers.value(nekoMirrorsHeader);
  await NekoMirrorStore.put(profileId, nekoMirrorsFromHeader(header, url: url));
  final plan = NekoPlan.fromHeader(response.headers.value(nekoPlanHeader));
  await NekoPlanStore.put(profileId, plan);
  return response;
}

Future<Response<Uint8List>> _fromAnyAddress(
  int profileId,
  String url,
  Future<Response<Uint8List>> Function(String url) download,
) async {
  try {
    return await download(url);
  } on Exception catch (error, stack) {
    for (final mirror in await NekoMirrorStore.of(profileId)) {
      try {
        return await download(mirror);
      } on Exception catch (mirrorError) {
        commonPrint.log(
          'profile mirror failed: ${compactError(mirrorError)}',
          logLevel: LogLevel.warning,
        );
      }
    }
    Error.throwWithStackTrace(error, stack);
  }
}

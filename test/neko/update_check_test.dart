import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _ReleasesAdapter implements HttpClientAdapter {
  _ReleasesAdapter(this.body);

  final Object body;
  final requested = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _release(String tag, {bool prerelease = true}) {
  return {'tag_name': tag, 'prerelease': prerelease, 'draft': false};
}

Future<(Map<String, dynamic>?, _ReleasesAdapter)> _check(Object body) async {
  final adapter = _ReleasesAdapter(body);
  final original = request.dio.httpClientAdapter;
  request.dio.httpClientAdapter = adapter;
  try {
    return (await request.checkForUpdate(), adapter);
  } finally {
    request.dio.httpClientAdapter = original;
  }
}

void main() {
  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'NekoVPN',
      packageName: 'com.nekovpn.client',
      version: '0.8.99-neko.1',
      buildNumber: '2026101001',
    );
    // Test builds run as APP_ENV=pre, the channel that sees prereleases.
    globalState.appEnv = 'pre';
  });

  test('reads the release list of this repository, not upstream', () async {
    final (_, adapter) = await _check([_release('v0.8.99-neko.2')]);
    expect(adapter.requested.single.toString(), _list);
  });

  test('a test release reaches a test build', () async {
    final (data, _) = await _check([_release('v0.8.99-neko.2')]);
    expect(data?['tag_name'], 'v0.8.99-neko.2');
  });

  test('the installed build and older ones are not updates', () async {
    final older = [_release('v0.8.99-neko.1'), _release('v0.8.98-neko.5')];
    expect((await _check(older)).$1, isNull);
  });

  test('an upstream-style release in this repository is ignored', () async {
    expect((await _check([_release('v9.9.9', prerelease: false)])).$1, isNull);
  });

  test('an answer that is not a list is no update and no crash', () async {
    expect((await _check({'tag_name': 'v0.8.99-neko.2'})).$1, isNull);
  });
}

const _list =
    'https://api.github.com/repos/Annoyt/vpnautodeploy_client/releases'
    '?per_page=30';

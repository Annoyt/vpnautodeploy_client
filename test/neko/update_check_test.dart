import 'dart:convert';
import 'dart:io';
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

/// Answers by path; a request for anything else fails the test.
class _RoutesAdapter implements HttpClientAdapter {
  _RoutesAdapter(this.byPath);

  final Map<String, ResponseBody Function()> byPath;
  final requested = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri.path);
    return byPath[options.uri.path]!();
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _quotaSpent() => ResponseBody.fromString('{}', 403);

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

Future<Map<String, dynamic>?> _checkWith(HttpClientAdapter adapter) async {
  final original = request.dio.httpClientAdapter;
  request.dio.httpClientAdapter = adapter;
  try {
    final found = await request.checkForUpdate();
    return found;
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

  group('once the API quota is spent', () {
    test('a test build reads the feed and skips bare tags', () async {
      final adapter = _RoutesAdapter({
        _listPath: _quotaSpent,
        _feedPath: () => ResponseBody.fromString(_feed, 200),
      });
      final found = await _checkWith(adapter);
      expect(found?['tag_name'], 'v0.8.99-neko.2');
      expect(adapter.requested, [_listPath, _feedPath]);
    });

    test('a stable build takes the latest release, not the feed', () async {
      globalState.appEnv = 'stable';
      addTearDown(() => globalState.appEnv = 'pre');
      final adapter = _RoutesAdapter({
        _listPath: _quotaSpent,
        '$_listPath/latest': _quotaSpent,
        '/$_repo/releases/latest': () => ResponseBody.fromString(
          '',
          302,
          headers: {
            HttpHeaders.locationHeader: [
              'https://github.com/$_repo/releases/tag/v0.8.99-neko.3',
            ],
          },
        ),
      });
      final found = await _checkWith(adapter);
      expect(found?['tag_name'], 'v0.8.99-neko.3');
      expect(adapter.requested, isNot(contains(_feedPath)));
    });

    test('no answer anywhere is an error, not "up to date"', () async {
      final adapter = _RoutesAdapter({
        _listPath: _quotaSpent,
        _feedPath: () => ResponseBody.fromString('', 503),
      });
      await expectLater(_checkWith(adapter), throwsA(isA<DioException>()));
    });
  });
}

const _list =
    'https://api.github.com/repos/Annoyt/vpnautodeploy_client/releases'
    '?per_page=30';

const _repo = 'Annoyt/vpnautodeploy_client';
const _listPath = '/repos/$_repo/releases';
const _feedPath = '/$_repo/releases.atom';

/// The tag of a build still in draft shows as a bare tag, titled by its
/// commit; only the release below it is one.
const _feed = '''
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <link rel="alternate" href="https://github.com/Annoyt/vpnautodeploy_client/releases/tag/v0.8.99-neko.3"/>
    <title>Merge pull request #9 from Annoyt/neko/next</title>
  </entry>
  <entry>
    <link rel="alternate" href="https://github.com/Annoyt/vpnautodeploy_client/releases/tag/v0.8.99-neko.2"/>
    <title>NekoVPN v0.8.99-neko.2 (тестовая сборка)</title>
  </entry>
</feed>
''';

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _ReleaseAdapter implements HttpClientAdapter {
  _ReleaseAdapter(this.tag);

  final String tag;
  final requested = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri);
    return ResponseBody.fromString(
      jsonEncode({'tag_name': tag}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<(Map<String, dynamic>?, _ReleaseAdapter)> _check(String tag) async {
  final adapter = _ReleaseAdapter(tag);
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
  });

  test('asks the releases of this repository, not upstream', () async {
    final (_, adapter) = await _check('v0.8.99-neko.2');
    expect(adapter.requested.single.toString(), _latest);
  });

  test('a later fork build is an update', () async {
    final (data, _) = await _check('v0.8.99-neko.2');
    expect(data?['tag_name'], 'v0.8.99-neko.2');
  });

  test('the installed build and older ones are not', () async {
    expect((await _check('v0.8.99-neko.1')).$1, isNull);
    expect((await _check('v0.8.98-neko.5')).$1, isNull);
  });

  test('a tag it cannot read is no update and no crash', () async {
    expect((await _check('nightly')).$1, isNull);
  });
}

const _latest =
    'https://api.github.com/repos/Annoyt/vpnautodeploy_client/releases/latest';

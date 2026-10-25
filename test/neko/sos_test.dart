import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/neko/sos.dart';
import 'package:flutter_test/flutter_test.dart';

const _main = 'https://autonekovpn.duckdns.org:9443';
const _mirror = 'https://sub.nekoweather.xyz:2096';
const _token = '0123456789abcdef0123456789abcdef';

class _PostAdapter implements HttpClientAdapter {
  RequestOptions? options;
  String? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    final chunks = await requestStream?.toList() ?? const <Uint8List>[];
    body = utf8.decode([for (final chunk in chunks) ...chunk]);
    return ResponseBody.fromString(
      jsonEncode({'status': 'reported', 'lines': <String>[]}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nekoServiceToken', () {
    const origins = [_main, _mirror];

    test('our subscription on one of our origins', () {
      final urls = ['$_mirror/sub/$_token?format=clash'];
      expect(nekoServiceToken(urls, origins), _token);
    });

    test('the first one wins, others are not ours', () {
      final urls = [
        'https://other.example/sub/$_token',
        'http://autonekovpn.duckdns.org:9443/sub/$_token',
        '$_main/sub/${_token.substring(1)}',
        '$_main/sub/$_token/extra',
        '$_main/open/$_token',
        'not a url',
        '$_main/sub/ffffffffffffffffffffffffffffffff',
        '$_main/sub/$_token',
      ];
      expect(nekoServiceToken(urls, origins), 'f' * 32);
    });

    test('none', () {
      expect(nekoServiceToken(const [], origins), isNull);
      expect(nekoServiceToken(['$_main/sub/$_token'], const []), isNull);
    });
  });

  test('the report says what the app sees and nothing else', () {
    final report = nekoSosReport(
      app: '0.9.2-neko.2',
      platform: 'android',
      network: 'wifi',
      vpnRunning: true,
      profileUpdated: DateTime(2026, 10, 25, 10),
      settingsVersion: 3,
      delays: {for (var i = 0; i < 40; i++) 'p$i': i == 1 ? null : 100},
      now: DateTime(2026, 10, 25, 10, 42),
    );
    expect(report['app'], '0.9.2-neko.2');
    expect(report['vpn_running'], isTrue);
    expect(report['profile_age_min'], 42);
    expect(report['settings_version'], 3);
    final delays = report['delays']! as List;
    expect(delays, hasLength(30));
    expect(delays[1], {'name': 'p1', 'ms': null});
    final never = nekoSosReport(
      app: '1',
      platform: 'android',
      network: null,
      vpnRunning: false,
      profileUpdated: null,
      settingsVersion: null,
      delays: const {},
    );
    expect(never['profile_age_min'], isNull);
    expect(never['delays'], isEmpty);
  });

  group('NekoSosAnswer.fromJson', () {
    test('reads the answer', () {
      final answer = NekoSosAnswer.fromJson({
        'status': 'repeat',
        'lines': ['a', 1, 'b'],
        'emergency': '$_main/sub/$_token?format=clash&emergency=1',
      });
      expect(answer?.status, 'repeat');
      expect(answer?.lines, ['a', 'b']);
      expect(answer?.emergency, endsWith('emergency=1'));
    });

    test('junk is no answer; a plain link is no emergency profile', () {
      expect(NekoSosAnswer.fromJson('x'), isNull);
      expect(NekoSosAnswer.fromJson({'lines': <String>[]}), isNull);
      expect(NekoSosAnswer.fromJson({'status': 'reported'}), isNull);
      final plain = NekoSosAnswer.fromJson({
        'status': 'reported',
        'lines': <String>[],
        'emergency': 'http://plain.example',
      });
      expect(plain?.emergency, isNull);
    });
  });

  group('nekoSendSos', () {
    test('origins in order, the first answer wins', () async {
      final asked = <String>[];
      final answer = await nekoSendSos(
        _token,
        const {'app': '1'},
        origins: const [_main, _mirror, 'https://never.example'],
        post: (url, body) async {
          asked.add(url);
          if (url.startsWith(_main)) {
            throw DioException.connectionTimeout(
              timeout: const Duration(seconds: 1),
              requestOptions: RequestOptions(path: url),
            );
          }
          return {'status': 'reported', 'lines': <String>[]};
        },
      );
      expect(answer?.status, 'reported');
      expect(asked, [
        '$_main/api/neko/sos/$_token',
        '$_mirror/api/neko/sos/$_token',
      ]);
    });

    test('an answer it cannot read is tried elsewhere, then none', () async {
      final asked = <String>[];
      final answer = await nekoSendSos(
        _token,
        const {},
        origins: const [_main, _mirror],
        post: (url, body) async {
          asked.add(url);
          return 'html error page';
        },
      );
      expect(answer, isNull);
      expect(asked, hasLength(2));
    });
  });

  test('nekoPostJson posts JSON and reads JSON', () async {
    final adapter = _PostAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final answer = await nekoPostJson(dio, '$_main/api/neko/sos/x', {'a': 1});
    expect(answer, {'status': 'reported', 'lines': <String>[]});
    expect(adapter.options?.method, 'POST');
    expect(adapter.options?.contentType, startsWith('application/json'));
    expect(jsonDecode(adapter.body!), {'a': 1});
  });

  test('without the platform the network is unknown', () async {
    expect(await nekoNetworkType(), isNull);
  });

  test('nekoDelays merges every test url', () {
    final delays = nekoDelays({
      'https://a': {'p1': 10, 'p2': null},
      'https://b': {'p3': -1},
    });
    expect(delays, {'p1': 10, 'p2': null, 'p3': -1});
  });

  test('the bot link runs /sos', () {
    expect(nekoSosBotUrl, 'https://t.me/neko_vpnbot?start=sos');
  });
}

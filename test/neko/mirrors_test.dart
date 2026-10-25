import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/neko/mirrors.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

const _url = 'https://main.example/sub/token?format=clash';
const _m1 = 'https://m1.example/sub/token?format=clash';
const _m2 = 'https://m2.example/sub/token?format=clash';

Response<Uint8List> _answer(String url, {String? mirrors}) {
  return Response(
    requestOptions: RequestOptions(path: url),
    data: Uint8List.fromList('proxies: []'.codeUnits),
    statusCode: 200,
    headers: Headers.fromMap({
      if (mirrors != null) nekoMirrorsHeader: [mirrors],
    }),
  );
}

/// Answers the URLs it knows; any other one fails like a dead host.
class _Network {
  _Network(this.answers);

  final Map<String, Response<Uint8List>> answers;
  final asked = <String>[];

  Future<Response<Uint8List>> download(String url) async {
    asked.add(url);
    final answer = answers[url];
    if (answer != null) return answer;
    throw DioException.connectionError(
      requestOptions: RequestOptions(path: url),
      reason: 'host down',
    );
  }
}

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('neko_mirrors');
    await useAppPaths(home);
  });

  tearDown(() => home.delete(recursive: true));

  File storeFile() => File('${home.path}/neko_mirrors.json');

  group('nekoMirrorsFromHeader', () {
    test('https mirrors in their order, without repeats', () {
      const header = '$_m1, $_m2,$_m1';
      expect(nekoMirrorsFromHeader(header, url: _url), [_m1, _m2]);
    });

    test('never the profile itself, plain http or junk', () {
      const header = '$_url, http://m3.example/sub/token, not a url, https://';
      expect(nekoMirrorsFromHeader(header, url: _url), isEmpty);
    });

    test('at most five', () {
      final many = [for (var i = 0; i < 7; i++) 'https://m$i.example/sub/t'];
      final mirrors = nekoMirrorsFromHeader(many.join(','), url: _url);
      expect(mirrors, many.take(5));
    });

    test('no header, no mirrors', () {
      expect(nekoMirrorsFromHeader(null, url: _url), isEmpty);
      expect(nekoMirrorsFromHeader('', url: _url), isEmpty);
    });
  });

  group('nekoDownloadProfile', () {
    test('an answer stores the mirrors it names', () async {
      final net = _Network({_url: _answer(_url, mirrors: '$_m1, $_m2')});
      final response = await nekoDownloadProfile(
        1,
        _url,
        download: net.download,
      );
      expect(response.requestOptions.path, _url);
      expect(net.asked, [_url]);
      expect(await NekoMirrorStore.of(1), [_m1, _m2]);
    });

    test('a dead address falls back to the mirrors, in order', () async {
      await NekoMirrorStore.put(1, [_m1, _m2]);
      final net = _Network({_m2: _answer(_m2, mirrors: '$_m1, $_m2')});
      final response = await nekoDownloadProfile(
        1,
        _url,
        download: net.download,
      );
      expect(response.requestOptions.path, _m2);
      expect(net.asked, [_url, _m1, _m2]);
    });

    test('no address answers: the error of the profile itself', () async {
      await NekoMirrorStore.put(1, [_m1]);
      final net = _Network({});
      await expectLater(
        nekoDownloadProfile(1, _url, download: net.download),
        throwsA(
          isA<DioException>().having(
            (error) => error.requestOptions.path,
            'path',
            _url,
          ),
        ),
      );
      expect(net.asked, [_url, _m1]);
    });

    test('an answer without the header forgets the mirrors', () async {
      await NekoMirrorStore.put(1, [_m1]);
      final net = _Network({_url: _answer(_url)});
      await nekoDownloadProfile(1, _url, download: net.download);
      expect(await NekoMirrorStore.of(1), isEmpty);
    });
  });

  group('NekoMirrorStore', () {
    test('each profile has its own mirrors', () async {
      await NekoMirrorStore.put(1, [_m1]);
      await NekoMirrorStore.put(2, [_m2]);
      expect(await NekoMirrorStore.of(1), [_m1]);
      expect(await NekoMirrorStore.of(2), [_m2]);
    });

    test('a damaged file reads as no mirrors', () async {
      for (final content in ['{not json', '[1, 2]', '{"1": "$_m1"}']) {
        storeFile().writeAsStringSync(content);
        expect(await NekoMirrorStore.of(1), isEmpty, reason: content);
      }
    });

    test('a failed write only logs', () async {
      Directory(storeFile().path).createSync();
      await NekoMirrorStore.put(1, [_m1]);
      expect(await NekoMirrorStore.of(1), isEmpty);
    });
  });
}

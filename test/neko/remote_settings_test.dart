import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/neko/remote_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../helpers/app_paths.dart';

/// The bot's first published document (its bot/neko/settings.json), signed
/// offline with the key whose public half this app carries.
const _published = {
  'kid': 'neko-settings-1',
  'doc':
      'eyJlbmRwb2ludHMiOlsiaHR0cHM6Ly9hdXRvbmVrb3Zwbi5kdWNrZG5zLm9yZzo5NDQzIiwiaHR0cHM6Ly9zdWIubmVrb3dlYXRoZXIueHl6OjIwOTYiXSwiZmxhZ3MiOnt9LCJtZXNzYWdlIjpudWxsLCJtaW5fdmVyc2lvbiI6bnVsbCwic2NoZW1hIjoxLCJzaWduZWRfYXQiOiIyMDI2LTEwLTI1VDE3OjA3OjExWiIsInZlcnNpb24iOjF9',
  'sig':
      'RSMUdps31/hHQDZwjuY6874nqUa6SPQZSeTjeMTA/2EaFmJqkCojjDcxK+l/teOq5B825Vz7dlozVNgre0YfBQ==',
};

const _main = 'https://autonekovpn.duckdns.org:9443';
const _mirror = 'https://sub.nekoweather.xyz:2096';

final _ed25519 = Ed25519();

Map<String, Object?> _doc({
  int version = 2,
  Object? endpoints = const [_main],
  Object? minVersion,
  Object? message,
  Object? flags = const {},
}) {
  return {
    'schema': 1,
    'version': version,
    'endpoints': endpoints,
    'min_version': minVersion,
    'message': message,
    'flags': flags,
  };
}

/// A test key, so that no test document is valid for real apps.
class _Signer {
  _Signer._(this._pair, this.publicKey);

  final SimpleKeyPair _pair;
  final String publicKey;

  static Future<_Signer> create([int seed = 7]) async {
    final pair = await _ed25519.newKeyPairFromSeed(List.filled(32, seed));
    final key = await pair.extractPublicKey();
    return _Signer._(pair, base64.encode(key.bytes));
  }

  Future<Map<String, String>> sign(Map<String, Object?> doc) async {
    final bytes = utf8.encode(jsonEncode(doc));
    final signature = await _ed25519.sign(bytes, keyPair: _pair);
    return {
      'kid': 'test',
      'doc': base64.encode(bytes),
      'sig': base64.encode(signature.bytes),
    };
  }
}

class _JsonAdapter implements HttpClientAdapter {
  final requested = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri);
    return ResponseBody.fromString(
      jsonEncode(_published),
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
  late Directory home;
  late _Signer signer;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('neko_settings');
    await useAppPaths(home);
    signer = await _Signer.create();
  });

  tearDown(() => home.delete(recursive: true));

  Future<NekoSettings?> verify(Object? envelope) {
    return nekoVerifySettings(envelope, publicKey: signer.publicKey);
  }

  group('nekoVerifySettings', () {
    test('the published document holds with the key the app carries', () async {
      final settings = await nekoVerifySettings(_published);
      expect(settings?.version, 1);
      expect(settings?.endpoints, [_main, _mirror]);
      expect(settings?.minVersion, isNull);
      expect(settings?.message, isNull);
    });

    test('a document signed with another key is not taken', () async {
      final envelope = await signer.sign(_doc());
      expect(await nekoVerifySettings(envelope), isNull);
      expect(await verify(envelope), isNotNull);
    });

    test('a changed doc fails its signature', () async {
      final envelope = await signer.sign(_doc());
      final forged = utf8.encode(jsonEncode(_doc(endpoints: ['https://x.io'])));
      final tampered = {...envelope, 'doc': base64.encode(forged)};
      expect(await verify(tampered), isNull);
    });

    test('junk is no settings and no crash', () async {
      final envelope = await signer.sign(_doc());
      final cut = envelope['sig']!.substring(0, 40);
      for (final junk in <Object?>[
        null,
        'text',
        {'doc': envelope['doc']},
        {...envelope, 'sig': cut},
        {...envelope, 'doc': 'not base64!'},
        {...envelope, 'sig': 'not base64!'},
      ]) {
        expect(await verify(junk), isNull, reason: '$junk');
      }
      final notJson = {
        'doc': base64.encode(utf8.encode('{not json')),
        'sig': envelope['sig'],
      };
      expect(await verify(notJson), isNull);
    });
  });

  group('NekoSettings.fromDoc', () {
    test('reads every field', () {
      final settings = NekoSettings.fromDoc(
        _doc(
          endpoints: [_main, 'http://plain.example', 'https://a.io/path', 7],
          minVersion: '0.9.2-neko.2',
          message: {
            'id': 'm1',
            'ru': 'Текст',
            'en': 'Text',
            'url': 'https://t.me/neko_vpnbot',
          },
          flags: {'multipath': true, 'share': 0.5, 'bad': <Object>[]},
        ),
      );
      expect(settings?.endpoints, [_main]);
      expect(settings?.minVersion, '0.9.2-neko.2');
      expect(settings?.message?.id, 'm1');
      expect(settings?.message?.url, 'https://t.me/neko_vpnbot');
      expect(settings?.flags, {'multipath': true, 'share': 0.5});
    });

    test('what it cannot use is dropped or refused', () {
      expect(NekoSettings.fromDoc(_doc()..['schema'] = 2), isNull);
      expect(NekoSettings.fromDoc(_doc(version: 0)), isNull);
      expect(NekoSettings.fromDoc(_doc(endpoints: ['http://a.io'])), isNull);
      expect(NekoSettings.fromDoc(_doc(endpoints: 'x')), isNull);
      expect(NekoSettings.fromDoc('x'), isNull);
      final loose = NekoSettings.fromDoc(
        _doc(minVersion: '0.9.2', message: {'id': ' ', 'ru': 'x'}, flags: 'x'),
      );
      expect(loose?.minVersion, isNull);
      expect(loose?.message, isNull);
      expect(loose?.flags, isEmpty);
      final plainLink = NekoSettings.fromDoc(
        _doc(message: {'id': 'm', 'ru': 'x', 'url': 'http://a.io', 'en': 1}),
      );
      expect(plainLink?.message?.url, isNull);
      expect(plainLink?.message?.en, isNull);
    });

    test('the message speaks the user language', () {
      const message = NekoMessage(id: 'm', ru: 'Привет', en: 'Hello');
      expect(Intl.withLocale('ru', () => message.text), 'Привет');
      expect(Intl.withLocale('en', () => message.text), 'Hello');
      const ruOnly = NekoMessage(id: 'm', ru: 'Привет');
      expect(Intl.withLocale('en', () => ruOnly.text), 'Привет');
    });
  });

  group('NekoSettingsStore', () {
    test('keeps only a newer signed document', () async {
      final key = signer.publicKey;
      final v2 = await signer.sign(_doc(version: 2));
      final v1 = await signer.sign(_doc(version: 1));
      expect((await NekoSettingsStore.offer(v2, publicKey: key))?.version, 2);
      expect(await NekoSettingsStore.offer(v1, publicKey: key), isNull);
      expect(await NekoSettingsStore.offer(v2, publicKey: key), isNull);
      expect((await NekoSettingsStore.current(publicKey: key))?.version, 2);
    });

    test('a kept file that no longer verifies is no settings', () async {
      final key = signer.publicKey;
      await NekoSettingsStore.offer(await signer.sign(_doc()), publicKey: key);
      final file = File('${home.path}/neko_settings.json');
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final forged = utf8.encode(jsonEncode(_doc(version: 9)));
      (data['signed'] as Map<String, dynamic>)['doc'] = base64.encode(forged);
      file.writeAsStringSync(jsonEncode(data));
      expect(await NekoSettingsStore.current(publicKey: key), isNull);
      file.writeAsStringSync('{not json');
      expect(await NekoSettingsStore.current(publicKey: key), isNull);
    });

    test('remembers the messages shown', () async {
      expect(await NekoSettingsStore.wasShown('m1'), isFalse);
      await NekoSettingsStore.markShown('m1');
      await NekoSettingsStore.markShown('m1');
      expect(await NekoSettingsStore.wasShown('m1'), isTrue);
      expect(await NekoSettingsStore.wasShown('m2'), isFalse);
    });
  });

  group('nekoRefreshSettings', () {
    test('asks the endpoints in order and stops at a signed answer', () async {
      final asked = <String>[];
      final v2 = await signer.sign(_doc(version: 2));
      final settings = await nekoRefreshSettings(
        publicKey: signer.publicKey,
        get: (url) async {
          asked.add(url);
          if (url.startsWith(_main)) throw const SocketException('down');
          return v2;
        },
      );
      expect(settings?.version, 2);
      expect(asked, ['$_main/neko/settings', '$_mirror/neko/settings']);
    });

    test('the kept document names more endpoints, asked first', () async {
      final key = signer.publicKey;
      const extra = 'https://c.example';
      final kept = await signer.sign(_doc(endpoints: [extra, _main]));
      await NekoSettingsStore.offer(kept, publicKey: key);
      final asked = <String>[];
      final settings = await nekoRefreshSettings(
        publicKey: key,
        get: (url) async {
          asked.add(url);
          return 'nothing signed';
        },
      );
      expect(settings?.version, 2);
      expect(asked.map(Uri.parse).map((uri) => uri.origin), [
        extra,
        _main,
        _mirror,
      ]);
    });

    test('an older answer leaves the kept settings in force', () async {
      final key = signer.publicKey;
      await NekoSettingsStore.offer(
        await signer.sign(_doc(version: 5)),
        publicKey: key,
      );
      final v3 = await signer.sign(_doc(version: 3));
      final settings = await nekoRefreshSettings(
        publicKey: key,
        get: (url) async => v3,
      );
      expect(settings?.version, 5);
    });

    test('nothing anywhere: no settings yet', () async {
      final settings = await nekoRefreshSettings(
        publicKey: signer.publicKey,
        get: (url) async => throw const SocketException('down'),
      );
      expect(settings, isNull);
    });
  });

  group('what to tell the user', () {
    test('an update when this build is older than min_version', () {
      bool required(String? minVersion, String installed) {
        final settings = NekoSettings.fromDoc(_doc(minVersion: minVersion))!;
        return nekoUpdateRequired(settings, installed: installed);
      }

      expect(required('0.9.2-neko.2', '0.9.2-neko.1'), isTrue);
      expect(required('0.9.2-neko.1', '0.9.2-neko.1'), isFalse);
      expect(required('0.9.2-neko.1', '0.9.3-neko.1'), isFalse);
      expect(required(null, '0.9.2-neko.1'), isFalse);
      expect(required('0.9.2-neko.2', 'dev'), isFalse);
    });

    test('the message once', () async {
      final settings = NekoSettings.fromDoc(
        _doc(message: {'id': 'm1', 'ru': 'Текст'}),
      )!;
      expect((await nekoMessageToShow(settings))?.id, 'm1');
      await NekoSettingsStore.markShown('m1');
      expect(await nekoMessageToShow(settings), isNull);
      expect(await nekoMessageToShow(NekoSettings.fromDoc(_doc())!), isNull);
    });
  });

  test('nekoGetJson reads the answer as JSON', () async {
    final adapter = _JsonAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final answer = await nekoGetJson(dio, '$_main/neko/settings');
    expect(answer, _published);
    expect(adapter.requested.single.path, '/neko/settings');
  });
}

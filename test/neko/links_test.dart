import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/links.dart';
import 'package:fl_clash/neko/remote_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';

import '../helpers/app_paths.dart';
import 'neko_ui.dart';

final _ed25519 = Ed25519();

Future<({String publicKey, Map<String, String> envelope})> _signed(
  Map<String, Object?> doc,
) async {
  final pair = await _ed25519.newKeyPairFromSeed(List.filled(32, 9));
  final key = await pair.extractPublicKey();
  final bytes = utf8.encode(jsonEncode(doc));
  final signature = await _ed25519.sign(bytes, keyPair: pair);
  return (
    publicKey: base64.encode(key.bytes),
    envelope: {
      'kid': 'test',
      'doc': base64.encode(bytes),
      'sig': base64.encode(signature.bytes),
    },
  );
}

Map<String, Object?> _doc({Object? mail}) => {
  'schema': 1,
  'version': 2,
  'endpoints': ['https://neko.example'],
  'mail': mail,
};

void main() {
  test('letters carry the contract subjects, a space as %20', () {
    expect(
      nekoMailto(nekoTestMail, nekoMailSosSubject).toString(),
      'mailto:help@neko.example?subject=SOS%20NekoVPN',
    );
    expect(
      nekoMailto(nekoTestMail, nekoMailRequestSubject).toString(),
      'mailto:help@neko.example?subject=NekoVPN%3A%20'
      '%D0%B7%D0%B0%D0%BF%D1%80%D0%BE%D1%81%20'
      '%D0%BF%D0%BE%D0%B4%D0%BF%D0%B8%D1%81%D0%BA%D0%B8',
    );
    expect(nekoMailto(nekoTestMail, 'x').path, nekoTestMail);
  });

  test('the bot link asks for the app path', () {
    expect(nekoBotAppUrl, 'https://t.me/neko_vpnbot?start=app');
  });

  test('a mailbox is taken only when it looks like one', () {
    expect(nekoMailOf(nekoTestMail), nekoTestMail);
    for (final junk in <Object?>[null, 7, '', 'help', 'a b@c.d', '@c.d']) {
      expect(nekoMailOf(junk), isNull, reason: '$junk');
    }
  });

  group('the service mailbox', () {
    late Directory home;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('neko_mail');
      await useAppPaths(home);
    });

    tearDown(() => home.delete(recursive: true));

    test('comes from the kept, signed settings', () async {
      final signed = await _signed(_doc(mail: nekoTestMail));
      await NekoSettingsStore.offer(
        signed.envelope,
        publicKey: signed.publicKey,
      );
      expect(await nekoServiceMail(publicKey: signed.publicKey), nekoTestMail);
    });

    test('none without settings, a mailbox or a signature', () async {
      expect(await nekoServiceMail(), isNull);
      final plain = await _signed(_doc());
      await NekoSettingsStore.offer(plain.envelope, publicKey: plain.publicKey);
      expect(await nekoServiceMail(publicKey: plain.publicKey), isNull);
      expect(await nekoServiceMail(), isNull, reason: 'another key');
    });

    test('a broken file is no mailbox', () async {
      await File(
        join(home.path, 'neko_settings.json'),
      ).writeAsString('{broken');
      expect(await nekoServiceMail(), isNull);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/neko/src/site.dart';

Map<String, Object?> _asset(String tag, String abi, {int size = 57671680}) => {
  'name': 'NekoVPN-${tag.substring(1)}-android-$abi.apk',
  'size': size,
  'browser_download_url': 'https://github.example/$tag/$abi.apk',
};

Map<String, Object?> _release(
  String tag, {
  bool draft = false,
  List<String> abis = nekoSiteAbis,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': true,
  'assets': [
    for (final abi in abis) _asset(tag, abi),
    {'name': 'SHA256SUMS', 'browser_download_url': 'x'},
  ],
};

final _releases = [
  _release('v0.9.2-neko.5', draft: true),
  _release('v1.0.0'),
  _release('v0.9.2-neko.4'),
  _release('v0.9.2-neko.3'),
];

void main() {
  group('the newest release', () {
    test('published, ours, with the common APK', () {
      final release = nekoSiteLatest(_releases)!;
      expect(release.tag, 'v0.9.2-neko.4');
      expect(
        release.apks['arm64-v8a']?.url,
        'https://github.example/v0.9.2-neko.4/arm64-v8a.apk',
      );
      expect(release.apks.keys, containsAll(nekoSiteAbis));
    });

    test('a release without the common APK is skipped', () {
      final release = nekoSiteLatest([
        _release('v0.9.2-neko.6', abis: ['x86_64']),
        _release('v0.9.2-neko.4'),
      ]);
      expect(release?.tag, 'v0.9.2-neko.4');
    });

    test('nothing usable is no release', () {
      for (final releases in <Object?>[
        null,
        'x',
        <Object>[],
        [_release('v0.9.2-neko.5', draft: true)],
        [
          'junk',
          <String, Object?>{'tag_name': null},
        ],
      ]) {
        expect(nekoSiteLatest(releases), isNull, reason: '$releases');
      }
    });
  });

  group('the page', () {
    test('every platform with its apps, the newest APK first', () {
      final page = nekoSitePage(nekoSiteLatest(_releases));
      expect(page, contains('<details id="android" open>'));
      expect(page, contains('<details id="ios">'));
      expect(page, contains('<details id="desktop">'));
      expect(
        page,
        contains('href="https://github.example/v0.9.2-neko.4/arm64-v8a.apk"'),
      );
      expect(page, contains('Версия 0.9.2-neko.4 · 55 МБ'));
      expect(page, contains('https://github.example/v0.9.2-neko.4/x86_64.apk'));
      for (final link in [
        'https://hiddify.com/',
        'https://chen08209.github.io/FlClash/#download',
        'https://karing.app/',
        nekoSiteBot,
        nekoSiteSource,
      ]) {
        expect(page, contains(link));
      }
      expect(page, contains(nekoSiteScript));
    });

    test('without a release, the release list', () {
      final page = nekoSitePage(null);
      expect(page, contains('href="$nekoSiteReleases"'));
      expect(page, isNot(contains('Версия')));
    });

    test('names are escaped', () {
      final page = nekoSitePage((
        tag: 'v0.9.2-neko.4',
        apks: {'arm64-v8a': (url: 'https://x/a.apk?a=1&b=<2>', size: 1)},
      ));
      expect(page, contains('https://x/a.apk?a=1&amp;b=&lt;2&gt;'));
    });
  });

  test('the command writes index.html from GitHub\'s JSON', () async {
    final dir = await Directory.systemTemp.createTemp('neko_site');
    addTearDown(() => dir.delete(recursive: true));
    final json = File('${dir.path}/releases.json')
      ..writeAsStringSync(jsonEncode(_releases));
    final result = await Process.run('dart', [
      'tool/neko/site.dart',
      json.path,
      '${dir.path}/out',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final page = File('${dir.path}/out/index.html').readAsStringSync();
    expect(page, contains('v0.9.2-neko.4/arm64-v8a.apk'));
  });
}

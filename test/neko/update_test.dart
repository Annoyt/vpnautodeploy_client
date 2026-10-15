import 'package:fl_clash/neko/update.dart';
import 'package:flutter_test/flutter_test.dart';

const _releases = 'https://github.com/Annoyt/vpnautodeploy_client/releases';

Map<String, dynamic> release(
  String tag, {
  bool prerelease = false,
  bool draft = false,
}) {
  return {
    'tag_name': tag,
    'prerelease': prerelease,
    'draft': draft,
    'html_url': '$_releases/tag/$tag',
  };
}

String? pick(List<dynamic> releases, {bool pre = true}) {
  final found = pickNekoUpdate(
    releases,
    installed: '0.8.99-neko.1',
    includePrerelease: pre,
  );
  return found?['tag_name'] as String?;
}

void main() {
  group('pickNekoUpdate', () {
    test('a test build sees the next test build', () {
      final releases = [release('v0.8.99-neko.2', prerelease: true)];
      expect(pick(releases), 'v0.8.99-neko.2');
    });

    test('a stable build never sees a test build', () {
      final releases = [release('v0.8.99-neko.2', prerelease: true)];
      expect(pick(releases, pre: false), isNull);
    });

    test('the newest wins whatever the list order', () {
      final releases = [
        release('v0.8.99-neko.2'),
        release('v0.9.0-neko.1'),
        release('v0.8.99-neko.3'),
      ];
      expect(pick(releases), 'v0.9.0-neko.1');
    });

    test('only newer than the installed build', () {
      expect(pick([release('v0.8.99-neko.1')]), isNull);
      expect(pick([release('v0.8.98-neko.9')]), isNull);
    });

    test('upstream-style and foreign tags are never offered', () {
      final releases = [
        release('v0.9.9'),
        release('v1.0.0-pre.1'),
        release('nightly'),
        release('v2.0.0-neko'),
      ];
      expect(pick(releases), isNull);
    });

    test('drafts are never offered', () {
      expect(pick([release('v0.8.99-neko.2', draft: true)]), isNull);
    });

    test('junk entries are skipped, not fatal', () {
      final junk = [42, 'x', <String, dynamic>{}];
      expect(pick([...junk, release('v0.8.99-neko.2')]), 'v0.8.99-neko.2');
    });
  });

  group('nekoReleasePageUrl', () {
    test('opens the release the dialog showed', () {
      final url = nekoReleasePageUrl(release('v0.8.99-neko.2'));
      expect(url, endsWith('/releases/tag/v0.8.99-neko.2'));
    });

    test('never a page outside this repository', () {
      final evil = {'html_url': 'https://evil.example/x'};
      expect(nekoReleasePageUrl(evil), _releases);
      expect(
        nekoReleasePageUrl({
          'html_url': 'https://github.com/chen08209/FlClash/releases/tag/v1',
        }),
        _releases,
      );
      expect(nekoReleasePageUrl({}), _releases);
    });
  });
}

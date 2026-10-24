import 'dart:io';

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

  group('nekoReleasesFromFeed', () {
    List<Object?> tags(String feed) {
      return [
        for (final release in nekoReleasesFromFeed(feed)) release['tag_name'],
      ];
    }

    test('reads the releases neko-release.yaml published', () {
      expect(tags(_feed), ['v0.9.2-neko.1', 'v0.8.99-neko.2']);
      final first = nekoReleasesFromFeed(_feed).first;
      expect(first['html_url'], '$_releases/tag/v0.9.2-neko.1');
    });

    test('each counts as a published prerelease', () {
      for (final release in nekoReleasesFromFeed(_feed)) {
        expect(release['prerelease'], isTrue);
        expect(release['draft'], isFalse);
      }
    });

    test('a test build takes the newest, a stable build none', () {
      expect(pick(nekoReleasesFromFeed(_feed)), 'v0.9.2-neko.1');
      expect(pick(nekoReleasesFromFeed(_feed), pre: false), isNull);
    });

    test('junk is no release and no crash', () {
      expect(tags(''), isEmpty);
      expect(tags('<entry><title>NekoVPN v1</title></entry>'), isEmpty);
      expect(tags('<entry>$_releases/tag/v0.9.2-neko.1'), isEmpty);
    });

    test('neko-release.yaml still titles a release the way it is read', () {
      final workflow = File('.github/workflows/neko-release.yaml');
      expect(
        workflow.readAsStringSync(),
        contains(r'name: NekoVPN ${{ github.ref_name }} ('),
      );
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

/// A release feed as GitHub serves it: the bare tag of a build still in
/// draft, two published releases, a release of another repository, a title
/// naming another tag, a repeated entry.
const _feed = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en-US">
  <title>Release notes from vpnautodeploy_client</title>
  <entry>
    <link rel="alternate" type="text/html" href="https://github.com/Annoyt/vpnautodeploy_client/releases/tag/v0.9.2-neko.2"/>
    <title>Merge pull request #9 from Annoyt/neko/next</title>
  </entry>
  <entry>
    <link rel="alternate" type="text/html" href="https://github.com/Annoyt/vpnautodeploy_client/releases/tag/v0.9.2-neko.1"/>
    <title>NekoVPN v0.9.2-neko.1 (тестовая сборка)</title>
  </entry>
  <entry>
    <link rel="alternate" type="text/html" href="https://github.com/chen08209/FlClash/releases/tag/v0.9.3-neko.1"/>
    <title>NekoVPN v0.9.3-neko.1</title>
  </entry>
  <entry>
    <link rel="alternate" type="text/html" href="https://github.com/Annoyt/vpnautodeploy_client/releases/tag/v0.9.1-neko.3"/>
    <title>NekoVPN v0.9.1-neko.30</title>
  </entry>
  <entry>
    <link rel="alternate" type="text/html" href="https://github.com/Annoyt/vpnautodeploy_client/releases/tag/v0.8.99-neko.2"/>
    <title>NekoVPN v0.8.99-neko.2</title>
  </entry>
  <entry>
    <link rel="alternate" type="text/html" href="https://github.com/Annoyt/vpnautodeploy_client/releases/tag/v0.8.99-neko.2"/>
    <title>NekoVPN v0.8.99-neko.2</title>
  </entry>
</feed>
''';

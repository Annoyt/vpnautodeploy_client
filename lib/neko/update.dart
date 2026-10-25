import 'package:fl_clash/common/constant.dart';

import 'version.dart';

/// A test build (`APP_ENV=pre`, the default): it is offered test releases.
/// Read from the build, as lib/bootstrap.dart reads it into
/// `globalState.appEnv`, so that the update check never depends on that
/// field having been set.
const nekoTestBuild =
    String.fromEnvironment('APP_ENV', defaultValue: 'pre') != 'stable';

/// Our release tags and nothing else: an upstream-style `v0.9.0`, or any
/// other tag that ever lands in this repository, is never offered.
final _nekoTag = RegExp(r'^v\d+\.\d+\.\d+-neko\.\d+$');

/// The newest release of this fork newer than [installed], or null.
///
/// [releases] is GitHub's `/releases` list. `/releases/latest`, which
/// upstream reads, skips prereleases, and every test build ships as one.
/// Drafts are never offered; prereleases only when [includePrerelease]:
/// a test build follows test releases, a stable build never sees one.
Map<String, dynamic>? pickNekoUpdate(
  List<dynamic> releases, {
  required String installed,
  required bool includePrerelease,
}) {
  Map<String, dynamic>? best;
  String? bestTag;
  for (final release in releases) {
    if (release is! Map<String, dynamic>) continue;
    final tag = release['tag_name'];
    if (tag is! String || !_nekoTag.hasMatch(tag)) continue;
    if (release['draft'] == true) continue;
    if (release['prerelease'] == true && !includePrerelease) continue;
    if (bestTag == null || compareNekoVersions(tag, bestTag) > 0) {
      best = release;
      bestTag = tag;
    }
  }
  if (bestTag == null || compareNekoVersions(bestTag, installed) <= 0) {
    return null;
  }
  return best;
}

final _feedEntry = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
final _feedTitle = RegExp(r'<title>([^<]*)</title>');
final _feedTag = RegExp(
  '${RegExp.escape('https://github.com/$repository/releases/tag/')}'
  r'([^"<\s]+)',
);

/// The title neko-release.yaml gives a release: `NekoVPN <tag>`, maybe
/// followed by a note such as "(тестовая сборка)".
bool _isReleaseTitle(String title, String tag) {
  return title == 'NekoVPN $tag' || title.startsWith('NekoVPN $tag ');
}

/// Published releases named by the public feed (`/releases.atom`), the
/// fallback once the API quota is spent. The feed lists bare tags too, and
/// the tag of a build still waiting as a draft is one: only an entry titled
/// the way neko-release.yaml names a release counts. The feed does not say
/// which are prereleases, so each counts as one.
List<Map<String, dynamic>> nekoReleasesFromFeed(String feed) {
  final releases = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final entry in _feedEntry.allMatches(feed)) {
    final body = entry.group(1)!;
    final tag = _feedTag.firstMatch(body)?.group(1);
    final title = _feedTitle.firstMatch(body)?.group(1)?.trim() ?? '';
    if (tag == null || !_isReleaseTitle(title, tag)) continue;
    if (!seen.add(tag)) continue;
    releases.add({
      'tag_name': tag,
      'prerelease': true,
      'draft': false,
      'html_url': 'https://github.com/$repository/releases/tag/$tag',
    });
  }
  return releases;
}

/// Where "Download" leads: the page of the release the dialog showed, and
/// only one in this repository; the release list otherwise.
String nekoReleasePageUrl(Map<String, dynamic> release) {
  const releases = 'https://github.com/$repository/releases';
  final url = release['html_url'];
  return url is String && url.startsWith('$releases/') ? url : releases;
}

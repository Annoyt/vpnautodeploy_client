import 'package:fl_clash/common/constant.dart';

import 'version.dart';

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

/// Where "Download" leads: the page of the release the dialog showed, and
/// only one in this repository; the release list otherwise.
String nekoReleasePageUrl(Map<String, dynamic> release) {
  const releases = 'https://github.com/$repository/releases';
  final url = release['html_url'];
  return url is String && url.startsWith('$releases/') ? url : releases;
}

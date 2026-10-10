/// Releases of this fork are tagged `v<upstream>-neko.<n>`, and that is the
/// version the app reports. Upstream's `compareVersions` reads `99-neko` as a
/// number and throws, and the `+build` it does understand never reaches the
/// installed side: `PackageInfo.version` has no build number.
int compareNekoVersions(String a, String b) {
  final left = _parse(a);
  final right = _parse(b);
  for (var i = 0; i < left.length; i++) {
    final order = left[i].compareTo(right[i]);
    if (order != 0) return order;
  }
  return 0;
}

final _pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:-neko\.(\d+))?(?:\+\d+)?$');

List<int> _parse(String version) {
  final match = _pattern.firstMatch(version.trim());
  if (match == null) {
    throw FormatException('Not a NekoVPN version', version);
  }
  return [
    for (var group = 1; group <= 3; group++) int.parse(match.group(group)!),
    int.parse(match.group(4) ?? '0'),
  ];
}

/// Markers the app's update dialog reads (`scopeReleaseNotes`): only the
/// `- ` lines between them are listed, one line per item.
const _begin = '<!-- flclash:changelog:begin -->';
const _end = '<!-- flclash:changelog:end -->';

/// The bullets of [version] in CHANGELOG-NEKO.md as release notes for the
/// update dialog: each wrapped bullet joined into one line, without the
/// Markdown the dialog would print verbatim. Throws [StateError] when the
/// version has no section or no bullets: a release must say what changed.
String nekoReleaseNotes(String changelog, String version) {
  final lines = changelog.split('\n');
  final start = lines.indexWhere(
    (line) => line == '## $version' || line.startsWith('## $version '),
  );
  if (start < 0) {
    throw StateError('CHANGELOG-NEKO.md has no section for $version');
  }
  final items = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('## ')) break;
    if (line.startsWith('- ')) {
      items.add(line.substring(2).trim());
    } else if (line.startsWith('  ') && line.trim().isNotEmpty) {
      if (items.isNotEmpty) items.last = '${items.last} ${line.trim()}';
    } else if (line.startsWith('#')) {
      break;
    }
  }
  if (items.isEmpty) {
    throw StateError('the $version section of CHANGELOG-NEKO.md has no items');
  }
  final notes = [
    _begin,
    for (final item in items) '- ${_plain(item)}',
    _end,
    '',
  ];
  return notes.join('\n');
}

String _plain(String item) => item.replaceAll('**', '').replaceAll('`', '');

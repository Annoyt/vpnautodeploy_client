import 'dart:io';

import 'src/site.dart';

/// `dart tool/neko/site.dart <releases.json> <out dir>`: the GitHub Pages
/// app chooser (`neko-pages.yaml`) for the release list GitHub's API gave.
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: dart tool/neko/site.dart <releases.json> <out dir>');
    exit(2);
  }
  final page = nekoSitePageFromJson(File(args[0]).readAsStringSync());
  final out = Directory(args[1])..createSync(recursive: true);
  File('${out.path}/index.html').writeAsStringSync(page);
  stdout.writeln('wrote ${out.path}/index.html');
}

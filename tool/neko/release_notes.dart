import 'dart:io';

import 'src/release_notes.dart';

/// `dart run tool/neko/release_notes.dart <version>`: the update-dialog
/// notes of one release, from CHANGELOG-NEKO.md, on stdout.
void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/neko/release_notes.dart <version>');
    exit(2);
  }
  final changelog = File('CHANGELOG-NEKO.md').readAsStringSync();
  stdout.write(nekoReleaseNotes(changelog, args.single));
}

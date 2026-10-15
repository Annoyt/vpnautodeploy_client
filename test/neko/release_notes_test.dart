import 'dart:io';

import 'package:fl_clash/common/package.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/neko/src/release_notes.dart';

const _changelog = '''
# Изменения NekoVPN

## 0.8.99-neko.2 — 2026-10-15

Intro paragraph, not an item.

- **Обновления.** Только наш канал:
  теги `v…-neko.N`.
- Второй пункт.

### Изменённые файлы апстрима

- `lib/x.dart` — this subsection is not release notes.

## 0.8.99-neko.1 — 2026-10-10

- Первая сборка.
''';

void main() {
  test('one line per item, Markdown stripped, between the markers', () {
    expect(
      nekoReleaseNotes(_changelog, '0.8.99-neko.2'),
      '$releaseNotesBeginMarker\n'
      '- Обновления. Только наш канал: теги v…-neko.N.\n'
      '- Второй пункт.\n'
      '$releaseNotesEndMarker\n',
    );
  });

  test('the update dialog reads exactly these items', () {
    final notes = nekoReleaseNotes(_changelog, '0.8.99-neko.2');
    expect(parseReleaseBody('Header\n- not an item\n$notes\n- after'), [
      'Обновления. Только наш канал: теги v…-neko.N.',
      'Второй пункт.',
    ]);
  });

  test('a version is matched whole, not by prefix', () {
    expect(nekoReleaseNotes(_changelog, '0.8.99-neko.1'), contains('Первая'));
    expect(() => nekoReleaseNotes(_changelog, '0.8.99-neko'), throwsStateError);
  });

  test('no section or no items: the release must not go out', () {
    const missing = '9.9.9-neko.1';
    expect(() => nekoReleaseNotes(_changelog, missing), throwsStateError);
    const empty = '## 0.8.99-neko.3 — 2026-10-16\n\nText only.\n';
    expect(() => nekoReleaseNotes(empty, '0.8.99-neko.3'), throwsStateError);
  });

  test('every version in CHANGELOG-NEKO.md has notes', () {
    final changelog = File('CHANGELOG-NEKO.md').readAsStringSync();
    final heading = RegExp(r'^## (\S+)', multiLine: true);
    final versions = [
      for (final match in heading.allMatches(changelog)) match.group(1)!,
    ];
    expect(versions, isNotEmpty);
    for (final version in versions) {
      expect(nekoReleaseNotes(changelog, version), contains('\n- '));
    }
  });
}

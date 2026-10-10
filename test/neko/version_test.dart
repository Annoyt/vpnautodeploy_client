import 'package:fl_clash/neko/version.dart';
import 'package:flutter_test/flutter_test.dart';

int cmp(String a, String b) => compareNekoVersions(a, b);

void main() {
  test('a later fork build of the same upstream is newer', () {
    expect(cmp('0.8.99-neko.2', '0.8.99-neko.1'), 1);
    expect(cmp('0.8.99-neko.1', '0.8.99-neko.2'), -1);
  });

  test('equal versions are equal whatever the build number', () {
    expect(cmp('0.8.99-neko.1', '0.8.99-neko.1'), 0);
    expect(cmp('0.8.99-neko.1+2026101001', '0.8.99-neko.1'), 0);
    expect(cmp('v0.8.99-neko.1', '0.8.99-neko.1'), 0);
  });

  test('a newer upstream base wins over the fork counter', () {
    expect(cmp('0.9.0-neko.1', '0.8.99-neko.7'), 1);
    expect(cmp('1.0.0-neko.1', '0.99.99-neko.9'), 1);
  });

  test('parts compare as numbers, not as text', () {
    expect(cmp('0.8.100-neko.1', '0.8.99-neko.1'), 1);
    expect(cmp('0.8.99-neko.10', '0.8.99-neko.9'), 1);
  });

  test('a plain upstream version counts as fork build zero', () {
    expect(cmp('0.8.99-neko.1', '0.8.99'), 1);
    expect(cmp('0.8.99', '0.8.99-neko.1'), -1);
  });

  test('anything else is rejected, never guessed', () {
    const bad = ['', 'latest', '0.8', '0.8.99-pre.1', '0.8.99-neko', 'x.y.z'];
    for (final version in bad) {
      expect(() => cmp(version, '0.8.99'), throwsFormatException);
    }
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

Iterable<File> _sources(String dir, List<String> extensions) {
  final files = Directory(dir).listSync(recursive: true).whereType<File>();
  return files.where((file) => extensions.any(file.path.endsWith));
}

/// Plugin ids, catalog entries and tasks, not prose: a comment may still
/// mention Crashlytics without wiring anything in.
final _firebase = RegExp(
  r'com\.google\.(gms|firebase)|libs\.firebase|google-services|'
  r'uploadCrashlytics|CrashlyticsExtension',
);

void main() {
  test('the Android app has its own package id', () {
    expect(
      _read('android/app/build.gradle.kts'),
      contains('applicationId = "com.nekovpn.client"'),
    );
  });

  test('no Firebase in any Android build script', () {
    expect(File('android/app/google-services.json').existsSync(), isFalse);
    for (final file in _sources('android', ['.gradle.kts', '.gradle'])) {
      expect(_firebase.hasMatch(_read(file.path)), isFalse, reason: file.path);
    }
  });

  test('no Firebase in Kotlin or Java code', () {
    for (final file in _sources('android', ['.kt', '.java'])) {
      expect(
        _read(file.path),
        isNot(contains('com.google.firebase')),
        reason: file.path,
      );
    }
  });

  test('the manifest claims nekovpn:// and leaves flclash:// alone', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('android:scheme="nekovpn"'));
    expect(manifest, isNot(contains('android:scheme="flclash"')));
  });
}

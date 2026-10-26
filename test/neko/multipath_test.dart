import 'dart:io';

import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/multipath.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('neko_multipath');
    await useAppPaths(home);
  });

  tearDown(() => home.delete(recursive: true));

  File modeFile() => File('${home.path}/$nekoMultipathFile');

  group('the mode file', () {
    test('nothing chosen is off', () async {
      expect(await nekoReadMultipathMode(), NekoMultipathMode.off);
    });

    test('what is written is read back, as the service reads it', () async {
      await nekoWriteMultipathMode(NekoMultipathMode.distribute);
      expect(await nekoReadMultipathMode(), NekoMultipathMode.distribute);
      // NekoNetworksModule matches "mode":"<name>" in this text.
      expect(modeFile().readAsStringSync(), '{"mode":"distribute"}');
      expect(File('${modeFile().path}.tmp').existsSync(), isFalse);
      await nekoWriteMultipathMode(NekoMultipathMode.failover);
      expect(await nekoReadMultipathMode(), NekoMultipathMode.failover);
    });

    test('junk is off', () async {
      for (final text in ['{not json', '[]', '{"mode":"turbo"}', '{}']) {
        modeFile().writeAsStringSync(text);
        expect(await nekoReadMultipathMode(), NekoMultipathMode.off);
      }
    });
  });

  test('every mode has a label', () {
    expect(nekoMultipathLabel(NekoMultipathMode.off), nekoMultipathOff);
    expect(
      nekoMultipathLabel(NekoMultipathMode.failover),
      nekoMultipathFailover,
    );
    expect(
      nekoMultipathLabel(NekoMultipathMode.distribute),
      nekoMultipathDistribute,
    );
  });
}

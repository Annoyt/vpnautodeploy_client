import 'dart:io';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/bypass.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

/// Upstream's default: reject mode, switched off, nothing selected.
const _fresh = AccessControlProps();

NekoBypassResult _merge(
  AccessControlProps access,
  List<String> list, [
  NekoBypassState state = const NekoBypassState(),
]) {
  return nekoMergeBypass(access, list, state);
}

void main() {
  group('applying the list', () {
    test('a fresh install excludes the list and switches it on once', () {
      final first = _merge(_fresh, ['ru.rostel', 'com.vkontakte.android']);
      expect(first.access.enable, isTrue);
      expect(first.access.rejectList, ['com.vkontakte.android', 'ru.rostel']);
      expect(first.state.added, {'ru.rostel', 'com.vkontakte.android'});
      expect(first.state.listed, {'ru.rostel', 'com.vkontakte.android'});
      expect(first.state.switchedOn, isTrue);
      final again = _merge(first.access, [
        'ru.rostel',
        'com.vkontakte.android',
      ], first.state);
      expect(again.access, first.access);
    });

    test('the user exclusions stay and never count as the list', () {
      const access = AccessControlProps(
        enable: true,
        rejectList: ['org.telegram.messenger', 'ru.rostel'],
      );
      final merged = _merge(access, ['ru.rostel', 'ru.oneme.app']);
      expect(merged.access.rejectList, [
        'org.telegram.messenger',
        'ru.rostel',
        'ru.oneme.app',
      ]);
      expect(merged.state.added, {'ru.oneme.app'});
      // The list drops both later: only what NekoVPN added leaves.
      final later = _merge(merged.access, [], merged.state);
      expect(later.access.rejectList, ['org.telegram.messenger', 'ru.rostel']);
      expect(later.state.added, isEmpty);
      expect(later.state.listed, isEmpty);
    });

    test('an app taken back into the VPN is not excluded again', () {
      final first = _merge(_fresh, ['ru.rostel', 'ru.oneme.app']);
      final onlyMax = first.access.copyWith(rejectList: ['ru.oneme.app']);
      final saved = nekoBypassSaved(
        first.state,
        access: onlyMax,
        visible: {'ru.rostel', 'ru.oneme.app'},
      );
      expect(saved.kept, {'ru.rostel'});
      expect(saved.added, {'ru.oneme.app'});
      final next = _merge(onlyMax, ['ru.rostel', 'ru.oneme.app'], saved);
      expect(next.access.rejectList, ['ru.oneme.app']);
      expect(next.state.added, {'ru.oneme.app'});
    });

    test('an app the screen dropped as not installed comes back', () {
      final first = _merge(_fresh, ['ru.rostel', 'com.vkontakte.android']);
      // The screen saves only what it shows, and VK is not installed.
      final pruned = first.access.copyWith(rejectList: ['ru.rostel']);
      final saved = nekoBypassSaved(
        first.state,
        access: pruned,
        visible: {'ru.rostel', 'org.telegram.messenger'},
      );
      expect(saved.kept, isEmpty);
      final next = _merge(pruned, [
        'ru.rostel',
        'com.vkontakte.android',
      ], saved);
      expect(next.access.rejectList, ['ru.rostel', 'com.vkontakte.android']);
    });

    test('access control switched off by the user stays off', () {
      final first = _merge(_fresh, ['ru.rostel']);
      final off = first.access.copyWith(enable: false);
      final next = _merge(off, ['ru.rostel', 'ru.oneme.app'], first.state);
      expect(next.access.enable, isFalse);
      expect(next.access.rejectList, ['ru.rostel', 'ru.oneme.app']);
    });

    test('nothing to exclude switches nothing on', () {
      final empty = _merge(_fresh, []);
      expect(empty.access, _fresh);
      expect(empty.state.switchedOn, isFalse);
      final allKept = _merge(_fresh, [
        'ru.rostel',
      ], const NekoBypassState(kept: {'ru.rostel'}));
      expect(allKept.access, _fresh);
      expect(allKept.state.switchedOn, isFalse);
    });

    test('accept mode is the user choice and is left alone', () {
      const accept = AccessControlProps(
        enable: true,
        mode: AccessControlMode.acceptSelected,
        acceptList: ['ru.rostel'],
      );
      final merged = _merge(accept, ['ru.rostel']);
      expect(merged.access, accept);
      expect(merged.state.added, isEmpty);
      const kept = NekoBypassState(kept: {'ru.rostel'});
      expect(
        nekoBypassSaved(kept, access: accept, visible: {'ru.rostel'}).kept,
        {'ru.rostel'},
      );
    });
  });

  group('what the user saves', () {
    test(
      'a listed app the user had excluded and unchecks stays in the VPN',
      () {
        const access = AccessControlProps(
          enable: true,
          rejectList: ['ru.rostel'],
        );
        final merged = _merge(access, ['ru.rostel']);
        expect(merged.state.added, isEmpty);
        final unchecked = access.copyWith(rejectList: []);
        final saved = nekoBypassSaved(
          merged.state,
          access: unchecked,
          visible: {'ru.rostel'},
        );
        expect(saved.kept, {'ru.rostel'});
        expect(
          _merge(unchecked, ['ru.rostel'], saved).access.rejectList,
          isEmpty,
        );
      },
    );

    test('an app checked again belongs to the list again', () {
      const state = NekoBypassState(listed: {'ru.rostel'}, kept: {'ru.rostel'});
      final saved = nekoBypassSaved(
        state,
        access: const AccessControlProps(rejectList: ['ru.rostel']),
        visible: {'ru.rostel'},
      );
      expect(saved.kept, isEmpty);
      expect(saved.listed, {'ru.rostel'});
    });

    test('apps the list does not name are not remembered', () {
      const state = NekoBypassState(listed: {'ru.rostel'});
      final saved = nekoBypassSaved(
        state,
        access: const AccessControlProps(rejectList: ['ru.rostel']),
        visible: {'ru.rostel', 'org.telegram.messenger'},
      );
      expect(saved.kept, isEmpty);
      expect(saved.added, isEmpty);
    });
  });

  group('the remembered state', () {
    late Directory home;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('neko_bypass');
      await useAppPaths(home);
    });

    tearDown(() => home.delete(recursive: true));

    File file() => File('${home.path}/$nekoBypassFile');

    test('nothing saved is nothing remembered', () async {
      final state = await nekoReadBypassState();
      expect(state.listed, isEmpty);
      expect(state.added, isEmpty);
      expect(state.kept, isEmpty);
      expect(state.switchedOn, isFalse);
    });

    test('what is written is read back', () async {
      await nekoWriteBypassState(
        const NekoBypassState(
          listed: {'b.b', 'a.a'},
          added: {'a.a'},
          kept: {'b.b'},
          switchedOn: true,
        ),
      );
      final state = await nekoReadBypassState();
      expect(state.listed, {'a.a', 'b.b'});
      expect(state.added, {'a.a'});
      expect(state.kept, {'b.b'});
      expect(state.switchedOn, isTrue);
      expect(
        file().readAsStringSync(),
        '{"listed":["a.a","b.b"],"added":["a.a"],"kept":["b.b"],'
        '"switched_on":true}',
      );
      expect(File('${file().path}.tmp').existsSync(), isFalse);
    });

    test('junk is nothing remembered', () async {
      for (final text in [
        '{not json',
        '[]',
        '{"added":"a.a","switched_on":"yes"}',
      ]) {
        file().writeAsStringSync(text);
        final state = await nekoReadBypassState();
        expect(state.added, isEmpty, reason: text);
        expect(state.switchedOn, isFalse, reason: text);
      }
    });

    test('the access control is written only when it changes', () async {
      var access = _fresh;
      var writes = 0;
      Future<bool> apply(List<String> list) => nekoApplyBypass(
        list: list,
        read: () => access,
        write: (value) {
          access = value;
          writes++;
        },
      );
      expect(await apply(['ru.rostel']), isTrue);
      expect(access.rejectList, ['ru.rostel']);
      expect(access.enable, isTrue);
      expect(await apply(['ru.rostel']), isFalse);
      expect(writes, 1);
      expect((await nekoReadBypassState()).added, {'ru.rostel'});
    });

    test('a save the state file refuses is only logged', () async {
      await nekoRecordBypassSave(
        access: _fresh,
        visible: {'ru.rostel'},
        save: (_) async => throw const FileSystemException('read-only'),
      );
      await nekoRecordBypassSave(
        access: _fresh,
        visible: {'ru.rostel'},
        load: () async => throw const FileSystemException('gone'),
      );
    });

    test('a save on the screen is remembered for the next start', () async {
      var access = _fresh;
      await nekoApplyBypass(
        list: ['ru.rostel'],
        read: () => access,
        write: (value) {
          access = value;
        },
      );
      final unchecked = access.copyWith(rejectList: []);
      await nekoRecordBypassSave(access: unchecked, visible: {'ru.rostel'});
      expect((await nekoReadBypassState()).kept, {'ru.rostel'});
      final changed = await nekoApplyBypass(
        list: ['ru.rostel'],
        read: () => unchecked,
        write: (_) {},
      );
      expect(changed, isFalse);
    });
  });
}

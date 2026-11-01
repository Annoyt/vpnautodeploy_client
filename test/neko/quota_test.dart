import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/neko/mirrors.dart';
import 'package:fl_clash/neko/quota.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

const _gb = 1024 * 1024 * 1024;
const _demo = NekoPlan(paid: false, appGb: 10, otherGb: 5);
const _paid = NekoPlan(paid: true);
const _url = 'https://main.example/sub/token?format=clash';

Response<Uint8List> _answer({String? plan}) {
  return Response(
    requestOptions: RequestOptions(path: _url),
    data: Uint8List.fromList('proxies: []'.codeUnits),
    statusCode: 200,
    headers: Headers.fromMap({
      if (plan != null) nekoPlanHeader: [plan],
    }),
  );
}

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('neko_quota');
    await useAppPaths(home);
  });

  tearDown(() => home.delete(recursive: true));

  group('the plan header', () {
    test('demo with both allowances, and paid', () {
      final demo = NekoPlan.fromHeader('plan=demo; app=10; other=5')!;
      expect(demo.paid, isFalse);
      expect(demo.appGb, 10);
      expect(demo.otherGb, 5);
      expect(NekoPlan.fromHeader(' plan = paid ')!.paid, isTrue);
    });

    test('anything else is no plan', () {
      for (final header in [null, '', 'plan=gold', 'app=10', 'plan']) {
        expect(NekoPlan.fromHeader(header), isNull, reason: '$header');
      }
    });
  });

  group('the plan store', () {
    test('each profile keeps the plan its last answer named', () async {
      await NekoPlanStore.put(1, _demo);
      await NekoPlanStore.put(2, _paid);
      expect((await NekoPlanStore.of(1))?.appGb, 10);
      expect((await NekoPlanStore.of(2))?.paid, isTrue);
      await NekoPlanStore.put(1, null);
      expect(await NekoPlanStore.of(1), isNull);
    });

    test('a damaged file is no plan', () async {
      final file = File('${home.path}/neko_plans.json');
      for (final content in ['{not json', '[]', '{"1": {"paid": "yes"}}']) {
        file.writeAsStringSync(content);
        expect(await NekoPlanStore.of(1), isNull, reason: content);
      }
    });

    test(
      'a profile download stores the plan and drops a missing one',
      () async {
        await nekoDownloadProfile(
          1,
          _url,
          download: (_) async => _answer(plan: 'plan=demo; app=10; other=5'),
        );
        expect((await NekoPlanStore.of(1))?.otherGb, 5);
        await nekoDownloadProfile(1, _url, download: (_) async => _answer());
        expect(await NekoPlanStore.of(1), isNull);
      },
    );
  });

  group('the month', () {
    NekoQuota quota(NekoPlan plan, int used, int total, {DateTime? expire}) =>
        NekoQuota(plan: plan, used: used, total: total, expire: expire);

    test('warns from 80 percent, runs out at 100', () {
      expect(quota(_demo, 7 * _gb, 10 * _gb).level, NekoQuotaLevel.normal);
      expect(quota(_demo, 8 * _gb, 10 * _gb).level, NekoQuotaLevel.high);
      expect(quota(_demo, 10 * _gb, 10 * _gb).level, NekoQuotaLevel.out);
      expect(quota(_demo, 1, 0).level, NekoQuotaLevel.normal);
    });

    test('a demo key under the app allowance is about to grow', () {
      expect(quota(_demo, 0, 5 * _gb).belowAppAllowance, isTrue);
      expect(quota(_demo, 0, 10 * _gb).belowAppAllowance, isFalse);
      expect(quota(_paid, 0, 5 * _gb).belowAppAllowance, isFalse);
    });

    test('a paid period that ended', () {
      final now = DateTime(2026, 11, 1);
      final ended = quota(_paid, 0, 100 * _gb, expire: DateTime(2026, 10, 31));
      final going = quota(_paid, 0, 100 * _gb, expire: DateTime(2026, 12, 31));
      expect(ended.expiredAt(now), isTrue);
      expect(going.expiredAt(now), isFalse);
      expect(
        quota(_demo, 0, 10 * _gb, expire: DateTime(2026, 10, 1)).expiredAt(now),
        isFalse,
      );
    });
  });
}

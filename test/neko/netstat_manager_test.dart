import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/netstat.dart';
import 'package:fl_clash/neko/netstat_manager.dart';
import 'package:fl_clash/neko/quota.dart';
import 'package:fl_clash/neko/remote_settings.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/app_paths.dart';

// NekoNetstatPlugin.kt listens here.
const _channel = MethodChannel('com.follow.clash/neko_netstat');
const _token = '0123456789abcdef0123456789abcdef';
const _ts = 1795190400;
final _probeUrl = '${nekoSettingsEndpoints.first}/neko/settings';
const _snapshot = NekoNetstatSnapshot(
  net: 'cell',
  mcc: '250',
  mnc: '01',
  rat: 'lte',
  level: 3,
  cell: NekoNetstatCell(tac: 7701, cid: 1, pci: 2, earfcn: 3),
  area: 'ucfv0',
);

typedef _Post = ({
  String url,
  Map<String, String> headers,
  Map<String, dynamic> body,
});

class _Fake {
  bool running = true;
  bool failSettings = false;
  NekoSettings? settings;
  String? token = _token;
  SubscriptionInfo? subscription;
  bool? ours = true;
  NekoNetstatSnapshot? snapshot = _snapshot;
  bool? ru = true;
  bool cellEnabled = false;
  String app = '0.9.2-neko.6';
  DateTime now = DateTime.fromMillisecondsSinceEpoch((_ts + 30) * 1000);
  NekoNetstatAnswer answer = (status: 204, retryAfter: null);
  Completer<void>? gate;
  void Function()? duringProbe;
  final probes = <String>[];
  final snapshots = <bool>[];
  final posts = <_Post>[];
  var ruProbes = 0;
  var runningAsked = 0;

  void later(Duration duration) => now = now.add(duration);

  NekoNetstatHooks get hooks => NekoNetstatHooks(
    running: () {
      runningAsked++;
      return running;
    },
    settings: () async {
      if (failSettings) throw StateError('broken settings');
      return settings;
    },
    token: () async => token,
    subscription: () => subscription,
    probeOurs: (url) async {
      probes.add(url);
      await gate?.future;
      duringProbe?.call();
      return ours;
    },
    snapshot: (cell) async {
      snapshots.add(cell);
      return snapshot;
    },
    probeRu: () async {
      ruProbes++;
      return ru;
    },
    cellEnabled: () async => cellEnabled,
    post: (url, headers, body) async {
      posts.add((
        url: url,
        headers: headers,
        body: jsonDecode(body) as Map<String, dynamic>,
      ));
      return answer;
    },
    app: () => app,
    now: () => now,
  );

  Future<void> check() => NekoNetstatRunner(hooks).check();
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <String>[];
  int status = 204;
  Map<String, List<String>> headers = const {};
  Exception? error;
  bool hang = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final chunks = await requestStream?.toList() ?? const <Uint8List>[];
    bodies.add(utf8.decode([for (final chunk in chunks) ...chunk]));
    if (hang) return Completer<ResponseBody>().future;
    final failure = error;
    if (failure != null) throw failure;
    return ResponseBody.fromString('', status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void _answer(Future<Object?>? Function(MethodCall call) handler) {
  _messenger.setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;

  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'NekoVPN',
      packageName: 'com.nekovpn.client',
      version: '0.9.2-neko.6',
      buildNumber: '1',
    );
  });

  setUp(() async {
    home = await Directory.systemTemp.createTemp('neko_netstat_run');
    await useAppPaths(home);
  });

  tearDown(() async {
    _messenger.setMockMethodCallHandler(_channel, null);
    await home.delete(recursive: true);
  });

  group('the runner', () {
    test('a drop carries the cell and the area with the switch on', () async {
      final fake = _Fake()
        ..ours = false
        ..cellEnabled = true;
      await fake.check();
      expect(fake.probes, [_probeUrl]);
      expect(fake.snapshots, [true]);
      expect(fake.ruProbes, 1);
      expect(fake.posts, isEmpty, reason: 'the channel is down');
      final state = await NekoNetstatStore.read();
      expect(state.events.single.toJson(), {
        'ts': _ts,
        'kind': 'drop',
        'net': 'cell',
        'mcc': '250',
        'mnc': '01',
        'rat': 'lte',
        'level': 3,
        'ru': true,
        'ours': false,
        'cell': {'tac': 7701, 'cid': 1, 'pci': 2, 'earfcn': 3},
        'area': 'ucfv0',
      });
      expect(state.lastOk, isNull);
    });

    test('with the switch off a drop asks for no cell', () async {
      final fake = _Fake()..ours = false;
      await fake.check();
      expect(fake.snapshots, [false]);
    });

    test(
      'ok once an hour, sent to the first endpoint with the token',
      () async {
        final fake = _Fake()
          ..settings = const NekoSettings(
            version: 3,
            endpoints: ['https://kept.example:9443'],
          );
        await fake.check();
        expect(fake.probes, ['https://kept.example:9443/neko/settings']);
        expect(fake.snapshots, [false]);
        final post = fake.posts.single;
        expect(post.url, 'https://kept.example:9443/api/neko/netstat');
        expect(post.headers['Authorization'], 'NekoToken $_token');
        expect(post.headers.containsKey('X-Neko-Token'), isFalse);
        expect(post.body['app'], '0.9.2-neko.6');
        expect((post.body['events'] as List).single['kind'], 'ok');
        var state = await NekoNetstatStore.read();
        expect(state.events, isEmpty);
        expect(state.lastOk, _ts);
        expect(state.lastUpload, _ts + 30);

        fake.later(const Duration(minutes: 20));
        await fake.check();
        expect(fake.snapshots, hasLength(1), reason: 'the ok is not due yet');
        expect(fake.posts, hasLength(1));

        fake.later(const Duration(minutes: 40));
        await fake.check();
        expect(fake.posts, hasLength(2));
        state = await NekoNetstatStore.read();
        expect(state.lastOk, _ts + 3600);
      },
    );

    test('drops wait for the channel and go at 20 within the hour', () async {
      await NekoNetstatStore.write(
        NekoNetstatState(
          events: [
            for (var i = 1; i <= 19; i++)
              NekoNetstatEvent(
                ts: _ts - i * 600,
                kind: NekoNetstatKind.drop,
                net: 'cell',
                ours: false,
              ),
          ],
          lastOk: _ts,
          lastUpload: _ts - 60,
        ),
      );
      final fake = _Fake()..ours = false;
      await fake.check();
      expect(fake.posts, isEmpty);
      expect((await NekoNetstatStore.read()).events, hasLength(20));
      fake
        ..ours = true
        ..later(const Duration(minutes: 10));
      await fake.check();
      expect(fake.snapshots, hasLength(1), reason: 'no ok within the hour');
      expect(fake.posts.single.body['events'], hasLength(20));
      expect((await NekoNetstatStore.read()).events, isEmpty);
    });

    test('a refusal with Retry-After holds the queue back', () async {
      final fake = _Fake()..answer = (status: 429, retryAfter: 600);
      await fake.check();
      final state = await NekoNetstatStore.read();
      expect(state.events, hasLength(1));
      expect(state.notBefore, _ts + 30 + 600);
    });

    test('a lapsed subscription records no drop', () async {
      final fake = _Fake()
        ..ours = false
        ..subscription = const SubscriptionInfo(expire: _ts - 1);
      await fake.check();
      expect(fake.snapshots, isEmpty);
      expect(File('${home.path}/$nekoNetstatFile').existsSync(), isFalse);
    });

    test(
      'nothing without the VPN, with netstat off or without our token',
      () async {
        final off = _Fake()..running = false;
        final stopped = _Fake()
          ..settings = const NekoSettings(
            version: 3,
            endpoints: ['https://kept.example'],
            flags: {'netstat': false},
          );
        final foreign = _Fake()..token = null;
        for (final fake in [off, stopped, foreign]) {
          await fake.check();
          expect(fake.probes, isEmpty);
        }
      },
    );

    test('nothing when the probe could not go through the tunnel', () async {
      final bypassed = _Fake()..ours = null;
      final stopping = _Fake()..ours = false;
      stopping.duringProbe = () => stopping.running = false;
      for (final fake in [bypassed, stopping]) {
        await fake.check();
        expect(fake.probes, hasLength(1));
        expect(fake.snapshots, isEmpty);
      }
      expect(File('${home.path}/$nekoNetstatFile').existsSync(), isFalse);
    });

    test('no network under the VPN: no event', () async {
      final fake = _Fake()
        ..ours = false
        ..snapshot = null;
      await fake.check();
      expect(fake.ruProbes, 0);
      expect((await NekoNetstatStore.read()).events, isEmpty);
    });

    test('a version the service would refuse stays unsent', () async {
      final fake = _Fake()..app = '0.9.2';
      await fake.check();
      expect(fake.posts, isEmpty);
      expect((await NekoNetstatStore.read()).events, hasLength(1));
    });

    test('one check at a time; a failure does not stop the next', () async {
      final fake = _Fake()..gate = Completer<void>();
      final runner = NekoNetstatRunner(fake.hooks);
      final first = runner.check();
      await runner.check();
      fake.gate!.complete();
      await first;
      expect(fake.probes, hasLength(1));
      fake.failSettings = true;
      await runner.check();
      fake.failSettings = false;
      await runner.check();
      expect(fake.probes, hasLength(2));
    });
  });

  group('the Android side', () {
    test('a snapshot, cell asked for or not', () async {
      final calls = <MethodCall>[];
      _answer((call) async {
        calls.add(call);
        return {'net': 'wifi', 'level': 2, 'lat': 55.7558, 'lon': 37.6173};
      });
      final snapshot = await const NekoNetstatNative().snapshot(cell: true);
      expect(snapshot!.net, 'wifi');
      expect(snapshot.level, 2);
      expect(snapshot.area, 'ucfv0');
      expect(calls.single.method, 'snapshot');
      expect(calls.single.arguments, {'cell': true});
    });

    test('the Russian site and the permission', () async {
      final answers = <String, Object?>{
        'probeRu': false,
        'hasLocation': true,
        'requestLocation': true,
      };
      _answer((call) async => answers[call.method]);
      const native = NekoNetstatNative();
      expect(await native.probeRu(), isFalse);
      expect(await native.hasLocation(), isTrue);
      expect(await native.requestLocation(), isTrue);
      answers.clear();
      expect(await native.probeRu(), isNull);
      expect(await native.hasLocation(), isFalse);
      expect(await native.requestLocation(), isFalse);
    });
  });

  group('wired to the app', () {
    late _Adapter adapter;
    late Dio dio;
    final profile = Profile.normal(
      url: 'https://radar.example:8443/sub/$_token?format=clash',
    );

    ProviderContainer container({
      bool start = true,
      bool suspend = false,
      Profile? current,
    }) {
      final container = ProviderContainer(
        overrides: [
          isStartProvider.overrideWithValue(start),
          suspendProvider.overrideWithValue(suspend),
          currentProfileProvider.overrideWithValue(current),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() {
      adapter = _Adapter();
      dio = Dio()..httpClientAdapter = adapter;
    });

    test('only while the VPN runs and nothing suspends it', () {
      expect(nekoNetstatHooks(container().read).running(), isTrue);
      expect(
        nekoNetstatHooks(container(suspend: true).read).running(),
        isFalse,
      );
      expect(nekoNetstatHooks(container(start: false).read).running(), isFalse);
    });

    test('the token of the current profile when it is ours', () async {
      expect(await nekoNetstatHooks(container().read).token(), isNull);
      final hooks = nekoNetstatHooks(container(current: profile).read);
      expect(await hooks.token(), isNull, reason: 'no plan: not ours');
      await NekoPlanStore.put(profile.id, const NekoPlan(paid: true));
      expect(await hooks.token(), _token);
      final main = Profile.normal(
        url: '${nekoSettingsEndpoints.first}/sub/$_token',
      );
      expect(
        await nekoNetstatHooks(container(current: main).read).token(),
        _token,
      );
    });

    test(
      'the profile, the switch, the settings, the version, the clock',
      () async {
        final current = profile.copyWith(
          subscriptionInfo: const SubscriptionInfo(total: 1, expire: 2),
        );
        final hooks = nekoNetstatHooks(container(current: current).read);
        expect(
          hooks.subscription(),
          const SubscriptionInfo(total: 1, expire: 2),
        );
        expect(await hooks.cellEnabled(), isFalse);
        expect(await hooks.settings(), isNull);
        expect(hooks.app(), '0.9.2-neko.6');
        expect(
          hooks.now().difference(DateTime.now()).inSeconds.abs(),
          lessThan(5),
        );
      },
    );

    test('our channel: any answer is a yes, none a no', () async {
      final hooks = nekoNetstatHooks(container().read, dio: dio);
      adapter.status = 404;
      expect(await hooks.probeOurs(_probeUrl), isTrue);
      expect(adapter.requests.single.method, 'HEAD');
      expect(adapter.requests.single.uri.toString(), _probeUrl);
      adapter.error = const SocketException('reset');
      expect(await hooks.probeOurs(_probeUrl), isFalse);
    });

    test('nothing goes out without the VPN', () async {
      final hooks = nekoNetstatHooks(container(start: false).read, dio: dio);
      expect(await hooks.probeOurs(_probeUrl), isNull);
      await expectLater(
        hooks.post('https://kept.example/api/neko/netstat', const {}, '{}'),
        throwsA(isA<HttpException>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('the upload: the body, the header, the status, Retry-After', () async {
      final hooks = nekoNetstatHooks(container().read, dio: dio);
      adapter
        ..status = 429
        ..headers = {
          'retry-after': ['90'],
        };
      final answer = await hooks.post('https://kept.example/api/neko/netstat', {
        'Authorization': 'NekoToken $_token',
      }, '{"v":1}');
      expect(answer.status, 429);
      expect(answer.retryAfter, 90);
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'NekoToken $_token');
      expect(adapter.bodies.single, '{"v":1}');
      adapter
        ..status = 204
        ..headers = const {};
      expect(await hooks.post('https://kept.example', const {}, '{}'), (
        status: 204,
        retryAfter: null,
      ));
    });

    test('the Android side: answers, failures and a missing plugin', () async {
      final hooks = nekoNetstatHooks(container().read);
      expect(await hooks.snapshot(false), isNull);
      expect(await hooks.probeRu(), isNull);
      _answer((call) async {
        if (call.method == 'probeRu') return true;
        return {'net': 'cell', 'mcc': '250', 'mnc': '01'};
      });
      expect((await hooks.snapshot(true))!.mcc, '250');
      expect(await hooks.probeRu(), isTrue);
      _answer((call) async => throw PlatformException(code: 'denied'));
      expect(await hooks.snapshot(true), isNull);
      expect(await hooks.probeRu(), isNull);
    });

    testWidgets('slow answers end in time', (tester) async {
      final hooks = nekoNetstatHooks(container().read, dio: dio);
      adapter.hang = true;
      _answer((call) => Completer<Object?>().future);
      final ours = hooks.probeOurs(_probeUrl);
      final snapshot = hooks.snapshot(true);
      final ru = hooks.probeRu();
      final post = hooks.post('https://kept.example', const {}, '{}');
      final posted = expectLater(post, throwsA(isA<TimeoutException>()));
      await tester.pump(const Duration(seconds: 31));
      expect(await ours, isFalse);
      expect(await snapshot, isNull);
      expect(await ru, isFalse, reason: 'no answer in time is no answer');
      await posted;
    });
  });

  group('the manager', () {
    Widget manager({
      bool start = true,
      bool? enabled = true,
      NekoNetstatHooks? hooks,
    }) {
      return ProviderScope(
        overrides: [
          isStartProvider.overrideWithValue(start),
          suspendProvider.overrideWithValue(true),
        ],
        child: NekoNetstatManager(
          enabled: enabled,
          hooks: hooks,
          first: const Duration(seconds: 1),
          every: const Duration(seconds: 5),
          child: const SizedBox.shrink(),
        ),
      );
    }

    testWidgets('checks soon after the VPN is up, then regularly', (
      tester,
    ) async {
      final fake = _Fake()..running = false;
      await tester.pumpWidget(manager(hooks: fake.hooks));
      expect(fake.runningAsked, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(fake.runningAsked, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(fake.runningAsked, 2);
      await tester.pump(const Duration(seconds: 5));
      expect(fake.runningAsked, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
      expect(fake.runningAsked, 3, reason: 'gone with the widget');
    });

    testWidgets('no checks with the VPN off or off Android', (tester) async {
      final fake = _Fake()..running = false;
      await tester.pumpWidget(manager(start: false, hooks: fake.hooks));
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(manager(enabled: null, hooks: fake.hooks));
      await tester.pump(const Duration(seconds: 10));
      expect(fake.runningAsked, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the hooks of the app by default', (tester) async {
      await tester.pumpWidget(manager());
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

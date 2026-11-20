import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/netstat.dart';
import 'package:fl_clash/neko/remote_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

const _token = '0123456789abcdef0123456789abcdef';
const _ts = 1795190400;
const _now = _ts + 120;
const _cell = NekoNetstatCell(
  tac: 7701,
  cid: 123456789,
  pci: 301,
  earfcn: 1850,
);

// The example of contract D2, docs/NEKO6_PLAN.md in the bot repository.
const _d2 =
    '{"ts": 1795190400, "kind": "drop", "net": "cell", "mcc": "250", '
    '"mnc": "01", "rat": "lte", "level": 2, "ru": true, "ours": false, '
    '"proto": {"hy2": false, "stls": false}, '
    '"cell": {"tac": 7701, "cid": 123456789, "pci": 301, "earfcn": 1850}, '
    '"area": "ucfv0"}';

NekoNetstatEvent _event({
  int ts = _ts,
  NekoNetstatKind kind = NekoNetstatKind.drop,
}) {
  return NekoNetstatEvent(
    ts: ts,
    kind: kind,
    net: 'cell',
    mcc: '250',
    mnc: '01',
    rat: 'lte',
    level: 2,
    ru: true,
    ours: kind == NekoNetstatKind.ok,
  );
}

List<NekoNetstatEvent> _events(int count) {
  return [for (var i = 0; i < count; i++) _event(ts: _ts + i * 600)];
}

typedef _Request = ({
  String url,
  Map<String, String> headers,
  Map<String, dynamic> body,
});

class _Service {
  _Service(this.answers);

  final List<Object> answers;
  final requests = <_Request>[];

  Future<NekoNetstatAnswer> post(
    String url,
    Map<String, String> headers,
    String body,
  ) async {
    requests.add((
      url: url,
      headers: headers,
      body: jsonDecode(body) as Map<String, dynamic>,
    ));
    final answer = answers.removeAt(0);
    if (answer is Exception) throw answer;
    return answer as NekoNetstatAnswer;
  }
}

NekoNetstatAnswer _status(int status, [int? retryAfter]) {
  return (status: status, retryAfter: retryAfter);
}

Future<NekoNetstatState> _upload(NekoNetstatState state, _Service service) {
  return nekoNetstatUpload(
    state,
    url: 'https://main.example/api/neko/netstat',
    token: _token,
    app: '0.9.2-neko.6',
    now: _now,
    post: service.post,
  );
}

void main() {
  group('the event', () {
    test('is the event of D2, without the optional proto', () {
      const event = NekoNetstatEvent(
        ts: _ts,
        kind: NekoNetstatKind.drop,
        net: 'cell',
        mcc: '250',
        mnc: '01',
        rat: 'lte',
        level: 2,
        ru: true,
        ours: false,
        cell: _cell,
        area: 'ucfv0',
      );
      final example = jsonDecode(_d2) as Map<String, dynamic>;
      example.remove('proto');
      expect(event.toJson(), example);
      expect(
        jsonEncode(event.toJson()),
        '{"ts":1795190400,"kind":"drop","net":"cell","mcc":"250","mnc":"01",'
        '"rat":"lte","level":2,"ru":true,"ours":false,'
        '"cell":{"tac":7701,"cid":123456789,"pci":301,"earfcn":1850},'
        '"area":"ucfv0"}',
      );
    });

    test('stage 1 sends no cell and no area; what is unknown is null', () {
      const event = NekoNetstatEvent(
        ts: _ts,
        kind: NekoNetstatKind.ok,
        net: 'wifi',
        ours: true,
      );
      expect(
        jsonEncode(event.toJson()),
        '{"ts":1795190400,"kind":"ok","net":"wifi","mcc":null,"mnc":null,'
        '"rat":"unknown","level":null,"ru":null,"ours":true}',
      );
    });

    test('reads back what it wrote and nothing the service refuses', () {
      final example = jsonDecode(_d2) as Map<String, dynamic>;
      final event = NekoNetstatEvent.fromJson(example)!;
      example.remove('proto');
      expect(event.toJson(), example);
      final bad = <Object?>[
        null,
        'drop',
        {...example, 'ts': -1},
        {...example, 'ts': 1 << 32},
        {...example, 'ts': '1795190400'},
        {...example, 'kind': 'lost'},
        {...example, 'net': 'satellite'},
        {...example, 'ours': null},
        {...example, 'ru': 'yes'},
      ];
      for (final json in bad) {
        expect(NekoNetstatEvent.fromJson(json), isNull, reason: '$json');
      }
      final cleaned = NekoNetstatEvent.fromJson({
        ...example,
        'mcc': '2500',
        'mnc': '1',
        'rat': 'cdma',
        'level': 5,
        'ru': null,
        'cell': {'tac': 1, 'cid': 0x7FFFFFFF},
        'area': 'ucfv',
      })!;
      expect(cleaned.toJson(), {
        'ts': _ts,
        'kind': 'drop',
        'net': 'cell',
        'mcc': null,
        'mnc': null,
        'rat': 'unknown',
        'level': null,
        'ru': null,
        'ours': false,
        'cell': {'tac': 1, 'cid': null, 'pci': null, 'earfcn': null},
      });
    });
  });

  test('ts is unix seconds down to the 10 minutes', () {
    expect(nekoNetstatTs(DateTime.utc(2026, 11, 20, 12, 34, 56)), 1795177800);
    final at = DateTime.fromMillisecondsSinceEpoch;
    expect(nekoNetstatTs(at(_ts * 1000)), _ts);
    expect(nekoNetstatTs(at(_ts * 1000 + 599999)), _ts);
    expect(nekoNetstatTs(at(_ts * 1000 + 600000)), _ts + 600);
  });

  test('the geohash', () {
    expect(nekoGeohash(55.7558, 37.6173), 'ucfv0');
    expect(nekoGeohash(57.64911, 10.40744, length: 11), 'u4pruydqqvj');
    expect(nekoGeohash(42.6, -5.6), 'ezs42');
    expect(nekoGeohash(-33.8688, 151.2093), 'r3gx2');
    expect(nekoGeohash(0, 0), 's0000');
    expect(nekoGeohash(90, 180), 'zzzzz');
    expect(nekoGeohash(-90, -180), '00000');
    expect(nekoGeohash(90.1, 0), isNull);
    expect(nekoGeohash(0, -180.1), isNull);
    expect(nekoGeohash(double.nan, 0), isNull);
    expect(nekoGeohash(0, double.infinity), isNull);
  });

  group('what the Android side reports', () {
    test('a full snapshot; the coordinates leave only the area', () {
      final snapshot = NekoNetstatSnapshot.fromNative({
        'net': 'cell',
        'mcc': '250',
        'mnc': '001',
        'rat': 'nr',
        'level': 4,
        'cell': {'tac': 1, 'cid': 68719476735, 'pci': 1007, 'earfcn': 3279165},
        'lat': 55.7558,
        'lon': 37.6173,
      })!;
      expect(snapshot.net, 'cell');
      expect(snapshot.mcc, '250');
      expect(snapshot.mnc, '001');
      expect(snapshot.rat, 'nr');
      expect(snapshot.level, 4);
      expect(snapshot.cell!.toJson(), {
        'tac': 1,
        'cid': 68719476735,
        'pci': 1007,
        'earfcn': 3279165,
      });
      expect(snapshot.area, 'ucfv0');
    });

    test('out of range, unavailable or missing is null', () {
      final snapshot = NekoNetstatSnapshot.fromNative({
        'net': 'wifi',
        'mcc': 'abc',
        'mnc': '1234',
        'rat': 'cdma',
        'level': -1,
        'cell': {
          'tac': 0x1000000,
          'cid': 0x7FFFFFFF,
          'pci': 1008,
          'earfcn': 3279166,
        },
        'lat': 55.7558,
      })!;
      expect(snapshot.mcc, isNull);
      expect(snapshot.mnc, isNull);
      expect(snapshot.rat, 'unknown');
      expect(snapshot.level, isNull);
      expect(snapshot.cell, isNull);
      expect(snapshot.area, isNull);
      expect(
        NekoNetstatSnapshot.fromNative({
          'net': 'other',
          'lat': 55,
          'lon': 37,
        })!.area,
        'ucf2c',
      );
    });

    test('no network under the VPN, or junk: nothing', () {
      for (final raw in <Object?>[
        null,
        'cell',
        <String, Object?>{},
        {'net': 'vpn'},
        {'net': 7},
      ]) {
        expect(NekoNetstatSnapshot.fromNative(raw), isNull, reason: '$raw');
      }
    });

    test('the radio counts on mobile data only', () {
      const radio = NekoNetstatSnapshot(
        net: 'wifi',
        mcc: '250',
        mnc: '01',
        rat: 'lte',
        level: 3,
        cell: _cell,
        area: 'ucfv0',
      );
      final onWifi = NekoNetstatEvent.of(
        ts: _ts,
        kind: NekoNetstatKind.drop,
        snapshot: radio,
        ru: true,
        ours: false,
      );
      expect(onWifi.toJson(), {
        'ts': _ts,
        'kind': 'drop',
        'net': 'wifi',
        'mcc': null,
        'mnc': null,
        'rat': 'unknown',
        'level': 3,
        'ru': true,
        'ours': false,
        'area': 'ucfv0',
      });
      final onCell = NekoNetstatEvent.of(
        ts: _ts,
        kind: NekoNetstatKind.drop,
        snapshot: const NekoNetstatSnapshot(
          net: 'cell',
          mcc: '250',
          mnc: '01',
          rat: 'lte',
          level: 2,
          cell: _cell,
          area: 'ucfv0',
        ),
        ru: true,
        ours: false,
      );
      expect(onCell.toJson(), (jsonDecode(_d2) as Map)..remove('proto'));
    });
  });

  group('the files', () {
    late Directory home;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('neko_netstat');
      await useAppPaths(home);
    });

    tearDown(() => home.delete(recursive: true));

    File file(String name) => File('${home.path}/$name');

    test(
      'an empty queue without a file; written whole and read back',
      () async {
        final empty = await NekoNetstatStore.read();
        expect(empty.events, isEmpty);
        expect(empty.lastOk, isNull);
        final state = NekoNetstatState(
          events: _events(3),
          lastOk: _ts,
          lastUpload: _now,
          notBefore: _now + 60,
        );
        await NekoNetstatStore.write(state);
        expect(file('$nekoNetstatFile.tmp').existsSync(), isFalse);
        final read = await NekoNetstatStore.read();
        expect(jsonEncode(read.toJson()), jsonEncode(state.toJson()));
      },
    );

    test('junk is an empty queue, and a bad event alone is dropped', () async {
      for (final text in ['{not json', '[]', '{"events":"many"}']) {
        file(nekoNetstatFile).writeAsStringSync(text);
        final state = await NekoNetstatStore.read();
        expect(state.events, isEmpty, reason: text);
      }
      file(nekoNetstatFile).writeAsStringSync(
        jsonEncode({
          'events': [_event().toJson(), 'junk', _event(ts: _ts + 600).toJson()],
          'last_ok': 'yesterday',
          'last_upload': _now,
        }),
      );
      final state = await NekoNetstatStore.read();
      expect(state.events.map((event) => event.ts), [_ts, _ts + 600]);
      expect(state.lastOk, isNull);
      expect(state.lastUpload, _now);
    });

    test('at most 500 events: the oldest go', () async {
      var state = NekoNetstatState(events: _events(nekoNetstatQueueLimit));
      state = state.add(_event(ts: _ts + 600 * nekoNetstatQueueLimit));
      expect(state.events, hasLength(nekoNetstatQueueLimit));
      expect(state.events.first.ts, _ts + 600);
      file(nekoNetstatFile).writeAsStringSync(
        jsonEncode({
          'events': [for (final event in _events(520)) event.toJson()],
        }),
      );
      final read = await NekoNetstatStore.read();
      expect(read.events, hasLength(nekoNetstatQueueLimit));
      expect(read.events.first.ts, _ts + 20 * 600);
    });

    test('one event of a kind per 10 minutes; an ok sets its clock', () {
      final state = const NekoNetstatState().add(_event());
      expect(identical(state.add(_event()), state), isTrue);
      final ok = state.add(_event(kind: NekoNetstatKind.ok));
      expect(ok.events, hasLength(2));
      expect(ok.lastOk, _ts);
      expect(state.lastOk, isNull);
    });

    test('the switch is off until written; the service reads it', () async {
      expect(await nekoReadNetstatCell(), isFalse);
      await nekoWriteNetstatCell(true);
      expect(await nekoReadNetstatCell(), isTrue);
      // NekoNetstatSwitch.kt looks for "enabled":true in this text.
      expect(file(nekoNetstatCellFile).readAsStringSync(), '{"enabled":true}');
      expect(file('$nekoNetstatCellFile.tmp').existsSync(), isFalse);
      await nekoWriteNetstatCell(false);
      expect(await nekoReadNetstatCell(), isFalse);
      for (final text in ['{not json', '{"enabled":"yes"}', '[true]']) {
        file(nekoNetstatCellFile).writeAsStringSync(text);
        expect(await nekoReadNetstatCell(), isFalse, reason: text);
      }
    });
  });

  group('the service', () {
    const settings = NekoSettings(
      version: 2,
      endpoints: ['https://kept.example:9443'],
    );

    test('only flags.netstat: false stops it', () {
      expect(nekoNetstatAllowed(null), isTrue);
      expect(nekoNetstatAllowed(settings), isTrue);
      for (final (flag, allowed) in [
        (false, false),
        (true, true),
        ('no', true),
      ]) {
        final flagged = NekoSettings(
          version: 2,
          endpoints: const ['https://kept.example'],
          flags: {'netstat': flag},
        );
        expect(nekoNetstatAllowed(flagged), allowed, reason: '$flag');
      }
    });

    test('the first settings endpoint', () {
      expect(nekoNetstatEndpoint(null), nekoSettingsEndpoints.first);
      expect(nekoNetstatEndpoint(settings), 'https://kept.example:9443');
    });

    test('the token of our subscription only', () {
      const radar = 'https://radar.example:8443/sub/$_token?format=clash';
      const main = 'https://main.example/sub/$_token';
      const origins = ['https://main.example'];
      expect(nekoNetstatToken(radar, planned: true, origins: []), _token);
      expect(nekoNetstatToken(main, planned: false, origins: origins), _token);
      expect(nekoNetstatToken(radar, planned: false, origins: origins), isNull);
      for (final url in [
        'https://radar.example/sub/${_token.substring(1)}',
        'https://radar.example/sub/$_token/x',
        'http://radar.example/sub/$_token',
        'https:///sub/$_token',
        'not a url at all',
        '',
      ]) {
        expect(
          nekoNetstatToken(url, planned: true, origins: origins),
          isNull,
          reason: url,
        );
      }
    });
  });

  group('when to record and send', () {
    test('drop on a live subscription, ok once an hour', () {
      NekoNetstatKind? due(bool ours, int? lastOk, {bool lapsed = false}) {
        return nekoNetstatKindDue(
          ours: ours,
          ts: _ts,
          lastOk: lastOk,
          lapsed: lapsed,
        );
      }

      expect(due(false, _ts), NekoNetstatKind.drop);
      expect(due(false, null, lapsed: true), isNull);
      expect(due(true, null), NekoNetstatKind.ok);
      expect(due(true, null, lapsed: true), NekoNetstatKind.ok);
      expect(due(true, _ts - 3000), isNull);
      expect(due(true, _ts - 3600), NekoNetstatKind.ok);
    });

    test('a lapsed subscription by its own userinfo', () {
      const gb = 1 << 30;
      expect(nekoNetstatLapsed(null, _now), isFalse);
      expect(nekoNetstatLapsed(const SubscriptionInfo(), _now), isFalse);
      expect(
        nekoNetstatLapsed(const SubscriptionInfo(expire: _now), _now),
        isTrue,
      );
      expect(
        nekoNetstatLapsed(const SubscriptionInfo(expire: _now + 1), _now),
        isFalse,
      );
      const spent = SubscriptionInfo(
        upload: gb,
        download: 9 * gb,
        total: 10 * gb,
      );
      expect(nekoNetstatLapsed(spent, _now), isTrue);
      const left = SubscriptionInfo(
        upload: gb,
        download: 8 * gb,
        total: 10 * gb,
      );
      expect(nekoNetstatLapsed(left, _now), isFalse);
    });

    test('hourly, at 20 events, never before the service allows', () {
      bool due(int count, {int? lastUpload, int? notBefore}) {
        return nekoNetstatUploadDue(
          NekoNetstatState(
            events: _events(count),
            lastUpload: lastUpload,
            notBefore: notBefore,
          ),
          _now,
        );
      }

      expect(due(0), isFalse);
      expect(due(1), isTrue);
      expect(due(1, lastUpload: _now - 100), isFalse);
      expect(due(1, lastUpload: _now - 3600), isTrue);
      expect(due(nekoNetstatUploadCount, lastUpload: _now - 100), isTrue);
      expect(due(30, notBefore: _now + 1), isFalse);
      expect(due(1, notBefore: _now), isTrue);
    });

    test('the app version the service takes', () {
      expect(nekoNetstatApp('0.9.2-neko.6'), isTrue);
      expect(nekoNetstatApp('10.0.0-neko.12'), isTrue);
      for (final app in ['0.9.2', '0.9.2-neko', '0.9.2-neko.6+1', 'neko.6']) {
        expect(nekoNetstatApp(app), isFalse, reason: app);
      }
    });

    test('Retry-After in seconds', () {
      expect(nekoRetryAfter('120'), 120);
      expect(nekoRetryAfter(' 30 '), 30);
      expect(nekoRetryAfter('1.5'), 2);
      expect(nekoRetryAfter('-1'), isNull);
      expect(nekoRetryAfter('Wed, 21 Oct 2026 07:28:00 GMT'), isNull);
      expect(nekoRetryAfter(null), isNull);
    });
  });

  group('the upload', () {
    test(
      'batches of 100, oldest first, with the token in the header',
      () async {
        final service = _Service([_status(204), _status(204), _status(200)]);
        final state = await _upload(
          NekoNetstatState(events: _events(250), lastOk: _ts),
          service,
        );
        expect(state.events, isEmpty);
        expect(state.lastOk, _ts);
        expect(state.lastUpload, _now);
        expect(state.notBefore, isNull);
        final sizes = [
          for (final request in service.requests)
            (request.body['events'] as List).length,
        ];
        expect(sizes, [100, 100, 50]);
        final first = service.requests.first;
        expect(first.url, 'https://main.example/api/neko/netstat');
        expect(first.headers, {
          'Authorization': 'NekoToken $_token',
          'Content-Type': 'application/json',
        });
        expect(first.body['v'], 1);
        expect(first.body['app'], '0.9.2-neko.6');
        expect(first.body.keys, ['v', 'app', 'events']);
        expect((first.body['events'] as List).first, _event().toJson());
        final last = service.requests.last.body['events'] as List;
        expect((last.last as Map)['ts'], _ts + 249 * 600);
      },
    );

    test('a refused batch is dropped: it would never be taken', () async {
      for (final status in [400, 401, 413]) {
        final service = _Service([_status(status), _status(204)]);
        final state = await _upload(
          NekoNetstatState(events: _events(150)),
          service,
        );
        expect(state.events, isEmpty, reason: '$status');
        expect(service.requests, hasLength(2));
      }
    });

    test('429 keeps the queue as long as Retry-After says', () async {
      for (final (retryAfter, wait) in [
        (120, 120),
        (null, 3600),
        (864000, 86400),
      ]) {
        final service = _Service([_status(429, retryAfter)]);
        final state = await _upload(
          NekoNetstatState(events: _events(150)),
          service,
        );
        expect(state.events, hasLength(150));
        expect(state.notBefore, _now + wait);
        expect(service.requests, hasLength(1));
      }
    });

    test('5xx, a redirect or no answer keep the rest for later', () async {
      final answers = <Object>[
        _status(503),
        _status(302),
        const SocketException('unreachable'),
      ];
      for (final answer in answers) {
        final service = _Service([_status(204), answer]);
        final state = await _upload(
          NekoNetstatState(events: _events(250), notBefore: _ts),
          service,
        );
        expect(state.events, hasLength(150), reason: '$answer');
        expect(state.events.first.ts, _ts + 100 * 600);
        expect(state.notBefore, _ts);
        expect(state.lastUpload, _now);
      }
    });

    test('a full batch stays well under 64 KB', () {
      final widest = NekoNetstatEvent(
        ts: (1 << 32) - 1,
        kind: NekoNetstatKind.drop,
        net: 'other',
        mcc: '250',
        mnc: '001',
        rat: 'unknown',
        level: 4,
        ru: false,
        ours: false,
        cell: const NekoNetstatCell(
          tac: 0xFFFFFF,
          cid: 0xFFFFFFFFF,
          pci: 1007,
          earfcn: 3279165,
        ),
        area: 'zzzzz',
      );
      final body = jsonEncode(
        nekoNetstatBody(
          '0.9.2-neko.6',
          List.filled(nekoNetstatBatchLimit, widest),
        ),
      );
      expect(utf8.encode(body).length, lessThan(32 * 1024));
    });
  });
}

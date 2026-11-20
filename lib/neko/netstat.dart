import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart';

import 'remote_settings.dart';
import 'sos.dart';

/// Contract D2 of docs/NEKO6_PLAN.md in the bot repository.
const nekoNetstatFile = 'neko_netstat.json';

/// «Помогать искать блокировки». NekoForeground.kt reads it too.
const nekoNetstatCellFile = 'neko_netstat_cell.json';

const nekoNetstatQueueLimit = 500;
const nekoNetstatBatchLimit = 100;
const nekoNetstatUploadCount = 20;
const _bucket = 600;
const _hour = 3600;
const _day = 86400;
const _unavailable = 0x7FFFFFFF;
const _geohashDigits = '0123456789bcdefghjkmnpqrstuvwxyz';
const _nets = {'wifi', 'cell', 'other'};
const _rats = {'gsm', 'umts', 'lte', 'nr', 'unknown'};
final _mcc = RegExp(r'^\d{3}$');
final _mnc = RegExp(r'^\d{2,3}$');
final _geohash = RegExp(r'^[0-9b-hjkmnp-z]{5}$');
final _appVersion = RegExp(r'^\d+\.\d+\.\d+-neko\.\d+$');

enum NekoNetstatKind { drop, ok }

int nekoNetstatTs(DateTime time) {
  final seconds = time.millisecondsSinceEpoch ~/ 1000;
  return seconds - seconds % _bucket;
}

String? nekoGeohash(double lat, double lon, {int length = 5}) {
  if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
    return null;
  }
  final lats = [-90.0, 90.0];
  final lons = [-180.0, 180.0];
  final hash = StringBuffer();
  var bits = 0;
  var digit = 0;
  var even = true;
  while (hash.length < length) {
    final range = even ? lons : lats;
    final value = even ? lon : lat;
    final middle = (range[0] + range[1]) / 2;
    digit <<= 1;
    if (value >= middle) {
      digit |= 1;
      range[0] = middle;
    } else {
      range[1] = middle;
    }
    even = !even;
    if (++bits == 5) {
      hash.write(_geohashDigits[digit]);
      bits = 0;
      digit = 0;
    }
  }
  return hash.toString();
}

String? _matching(Object? value, RegExp pattern) {
  return value is String && pattern.hasMatch(value) ? value : null;
}

String _rat(Object? value) {
  return value is String && _rats.contains(value) ? value : 'unknown';
}

int? _level(Object? value) {
  return value is int && value >= 0 && value <= 4 ? value : null;
}

int? _int(Object? value) => value is int ? value : null;

/// The serving cell, one set of names for every radio: `tac` is the TAC or
/// LAC, `pci` the PCI, PSC or BSIC, `earfcn` the channel number.
class NekoNetstatCell {
  const NekoNetstatCell({this.tac, this.cid, this.pci, this.earfcn});

  final int? tac;
  final int? cid;
  final int? pci;
  final int? earfcn;

  Map<String, Object?> toJson() => {
    'tac': tac,
    'cid': cid,
    'pci': pci,
    'earfcn': earfcn,
  };

  /// Android's "unavailable" and anything out of range are null: the service
  /// refuses a whole batch over one.
  static NekoNetstatCell? fromJson(Object? json) {
    if (json is! Map) return null;
    int? number(String key, int max) {
      final value = json[key];
      if (value is! int || value == _unavailable) return null;
      return value >= 0 && value <= max ? value : null;
    }

    final cell = NekoNetstatCell(
      tac: number('tac', 0xFFFFFF),
      cid: number('cid', 0xFFFFFFFFF),
      pci: number('pci', 1007),
      earfcn: number('earfcn', 3279165),
    );
    final known = [cell.tac, cell.cid, cell.pci, cell.earfcn].nonNulls;
    return known.isEmpty ? null : cell;
  }
}

class NekoNetstatSnapshot {
  const NekoNetstatSnapshot({
    required this.net,
    this.mcc,
    this.mnc,
    this.rat = 'unknown',
    this.level,
    this.cell,
    this.area,
  });

  final String net;
  final String? mcc;
  final String? mnc;
  final String rat;
  final int? level;
  final NekoNetstatCell? cell;
  final String? area;

  /// Null without a network under the VPN; the coordinates stop at [area].
  static NekoNetstatSnapshot? fromNative(Object? raw) {
    if (raw is! Map) return null;
    final net = raw['net'];
    if (net is! String || !_nets.contains(net)) return null;
    final lat = raw['lat'];
    final lon = raw['lon'];
    return NekoNetstatSnapshot(
      net: net,
      mcc: _matching(raw['mcc'], _mcc),
      mnc: _matching(raw['mnc'], _mnc),
      rat: _rat(raw['rat']),
      level: _level(raw['level']),
      cell: NekoNetstatCell.fromJson(raw['cell']),
      area: lat is num && lon is num
          ? nekoGeohash(lat.toDouble(), lon.toDouble())
          : null,
    );
  }
}

class NekoNetstatEvent {
  const NekoNetstatEvent({
    required this.ts,
    required this.kind,
    required this.net,
    this.mcc,
    this.mnc,
    this.rat = 'unknown',
    this.level,
    this.ru,
    required this.ours,
    this.cell,
    this.area,
  });

  /// The radio only on mobile data: on Wi-Fi the SIM's carrier is not the path.
  factory NekoNetstatEvent.of({
    required int ts,
    required NekoNetstatKind kind,
    required NekoNetstatSnapshot snapshot,
    required bool? ru,
    required bool ours,
  }) {
    final mobile = snapshot.net == 'cell';
    return NekoNetstatEvent(
      ts: ts,
      kind: kind,
      net: snapshot.net,
      mcc: mobile ? snapshot.mcc : null,
      mnc: mobile ? snapshot.mnc : null,
      rat: mobile ? snapshot.rat : 'unknown',
      level: snapshot.level,
      ru: ru,
      ours: ours,
      cell: mobile ? snapshot.cell : null,
      area: snapshot.area,
    );
  }

  final int ts;
  final NekoNetstatKind kind;
  final String net;
  final String? mcc;
  final String? mnc;
  final String rat;
  final int? level;
  final bool? ru;
  final bool ours;
  final NekoNetstatCell? cell;
  final String? area;

  Map<String, Object?> toJson() => {
    'ts': ts,
    'kind': kind.name,
    'net': net,
    'mcc': mcc,
    'mnc': mnc,
    'rat': rat,
    'level': level,
    'ru': ru,
    'ours': ours,
    if (cell case final known?) 'cell': known.toJson(),
    if (area case final known?) 'area': known,
  };

  static NekoNetstatEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final ts = json['ts'];
    final kind = NekoNetstatKind.values.asNameMap()[json['kind']];
    final net = json['net'];
    final ru = json['ru'];
    final ours = json['ours'];
    if (ts is! int || ts < 0 || ts >= 1 << 32 || kind == null) return null;
    if (net is! String || !_nets.contains(net) || ours is! bool) return null;
    if (ru != null && ru is! bool) return null;
    return NekoNetstatEvent(
      ts: ts,
      kind: kind,
      net: net,
      mcc: _matching(json['mcc'], _mcc),
      mnc: _matching(json['mnc'], _mnc),
      rat: _rat(json['rat']),
      level: _level(json['level']),
      ru: ru as bool?,
      ours: ours,
      cell: NekoNetstatCell.fromJson(json['cell']),
      area: _matching(json['area'], _geohash),
    );
  }
}

class NekoNetstatState {
  const NekoNetstatState({
    this.events = const [],
    this.lastOk,
    this.lastUpload,
    this.notBefore,
  });

  final List<NekoNetstatEvent> events;
  final int? lastOk;
  final int? lastUpload;
  final int? notBefore;

  /// One event of a kind per 10 minutes; past the limit the oldest go.
  NekoNetstatState add(NekoNetstatEvent event) {
    final last = events.lastOrNull;
    if (last != null && last.ts == event.ts && last.kind == event.kind) {
      return this;
    }
    return NekoNetstatState(
      events: _newest([...events, event]),
      lastOk: event.kind == NekoNetstatKind.ok ? event.ts : lastOk,
      lastUpload: lastUpload,
      notBefore: notBefore,
    );
  }

  Map<String, Object?> toJson() => {
    'events': [for (final event in events) event.toJson()],
    'last_ok': lastOk,
    'last_upload': lastUpload,
    'not_before': notBefore,
  };

  static NekoNetstatState fromJson(Object? json) {
    if (json is! Map) return const NekoNetstatState();
    final events = json['events'];
    return NekoNetstatState(
      events: _newest([
        if (events is List)
          for (final event in events) ?NekoNetstatEvent.fromJson(event),
      ]),
      lastOk: _int(json['last_ok']),
      lastUpload: _int(json['last_upload']),
      notBefore: _int(json['not_before']),
    );
  }
}

List<NekoNetstatEvent> _newest(List<NekoNetstatEvent> events) {
  final over = events.length - nekoNetstatQueueLimit;
  return over > 0 ? events.sublist(over) : events;
}

Future<File> _file(String name) async {
  return File(join(await appPath.homeDirPath, name));
}

/// Written aside and renamed over: a reader never sees half a file.
Future<void> _replace(String name, String text) async {
  final file = await _file(name);
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(text, flush: true);
  await temp.rename(file.path);
}

class NekoNetstatStore {
  NekoNetstatStore._();

  static Future<NekoNetstatState> read() async {
    try {
      final file = await _file(nekoNetstatFile);
      if (!await file.exists()) return const NekoNetstatState();
      return NekoNetstatState.fromJson(jsonDecode(await file.readAsString()));
    } on Exception {
      return const NekoNetstatState();
    }
  }

  static Future<void> write(NekoNetstatState state) {
    return _replace(nekoNetstatFile, jsonEncode(state.toJson()));
  }
}

Future<bool> nekoReadNetstatCell() async {
  try {
    final file = await _file(nekoNetstatCellFile);
    if (!await file.exists()) return false;
    final data = jsonDecode(await file.readAsString());
    return data is Map && data['enabled'] == true;
  } on Exception {
    return false;
  }
}

Future<void> nekoWriteNetstatCell(bool enabled) {
  return _replace(nekoNetstatCellFile, jsonEncode({'enabled': enabled}));
}

/// Off only when the signed settings say `flags.netstat: false` (D1).
bool nekoNetstatAllowed(NekoSettings? settings) {
  return settings?.flags['netstat'] != false;
}

String nekoNetstatEndpoint(NekoSettings? settings) {
  return settings?.endpoints.first ?? nekoSettingsEndpoints.first;
}

/// Our subscription's token: on one of [origins], or on its own origin once
/// the bot named its plan. Another service's token stays on the phone.
String? nekoNetstatToken(
  String url, {
  required bool planned,
  required Iterable<String> origins,
}) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return nekoServiceToken([url], planned ? [uri.origin] : origins);
}

/// Out of time or traffic by its own userinfo: the key fails, not a block.
bool nekoNetstatLapsed(SubscriptionInfo? info, int now) {
  if (info == null) return false;
  if (info.expire > 0 && info.expire <= now) return true;
  return info.total > 0 && info.upload + info.download >= info.total;
}

NekoNetstatKind? nekoNetstatKindDue({
  required bool ours,
  required int ts,
  required int? lastOk,
  required bool lapsed,
}) {
  if (!ours) return lapsed ? null : NekoNetstatKind.drop;
  return lastOk == null || ts - lastOk >= _hour ? NekoNetstatKind.ok : null;
}

bool nekoNetstatApp(String app) => _appVersion.hasMatch(app);

bool nekoNetstatUploadDue(NekoNetstatState state, int now) {
  if (state.events.isEmpty) return false;
  final notBefore = state.notBefore;
  if (notBefore != null && now < notBefore) return false;
  final last = state.lastUpload;
  return state.events.length >= nekoNetstatUploadCount ||
      last == null ||
      now - last >= _hour;
}

Map<String, Object?> nekoNetstatBody(
  String app,
  Iterable<NekoNetstatEvent> events,
) => {
  'v': 1,
  'app': app,
  'events': [for (final event in events) event.toJson()],
};

typedef NekoNetstatAnswer = ({int status, int? retryAfter});

/// POSTs a body; throws when nothing came back.
typedef NekoNetstatPost =
    Future<NekoNetstatAnswer> Function(
      String url,
      Map<String, String> headers,
      String body,
    );

/// Seconds only: the service sends no HTTP date.
int? nekoRetryAfter(String? value) {
  final seconds = num.tryParse(value?.trim() ?? '');
  return seconds == null || seconds < 0 ? null : seconds.ceil();
}

/// A 2xx is taken and another 4xx never will be: both let the batch go.
bool _settled(int status) {
  return (status >= 200 && status < 300) ||
      (status >= 400 && status < 500 && status != 429);
}

Future<NekoNetstatState> nekoNetstatUpload(
  NekoNetstatState state, {
  required String url,
  required String token,
  required String app,
  required int now,
  required NekoNetstatPost post,
}) async {
  var events = state.events;
  var notBefore = state.notBefore;
  final headers = {
    'Authorization': 'NekoToken $token',
    'Content-Type': 'application/json',
  };
  while (events.isNotEmpty) {
    final batch = events.take(nekoNetstatBatchLimit).toList();
    final NekoNetstatAnswer answer;
    try {
      answer = await post(
        url,
        headers,
        jsonEncode(nekoNetstatBody(app, batch)),
      );
    } on Exception catch (error) {
      commonPrint.log(
        'netstat upload: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      break;
    }
    if (answer.status == 429) {
      final wait = answer.retryAfter ?? _hour;
      notBefore = now + (wait > _day ? _day : wait);
    }
    if (!_settled(answer.status)) break;
    events = events.sublist(batch.length);
  }
  return NekoNetstatState(
    events: events,
    lastOk: state.lastOk,
    lastUpload: now,
    notBefore: notBefore,
  );
}

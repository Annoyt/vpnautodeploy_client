import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:path/path.dart';

/// The header the NekoVPN bot sends with a Clash profile: which plan the
/// bytes in `subscription-userinfo` are (bot AGENTS.md section 46).
/// `plan=paid`, or `plan=demo; app=10; other=5` with the demo allowances
/// in this app and in any other.
const nekoPlanHeader = 'nekovpn-plan';

const _bytesPerGb = 1024 * 1024 * 1024;

class NekoPlan {
  const NekoPlan({required this.paid, this.appGb, this.otherGb});

  final bool paid;

  /// The demo allowance in NekoVPN and in other clients, in GB.
  final int? appGb;
  final int? otherGb;

  static NekoPlan? fromHeader(String? header) {
    final fields = <String, String>{};
    for (final part in (header ?? '').split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      fields[part.substring(0, index).trim()] = part
          .substring(index + 1)
          .trim();
    }
    return switch (fields['plan']) {
      'paid' => const NekoPlan(paid: true),
      'demo' => NekoPlan(
        paid: false,
        appGb: int.tryParse(fields['app'] ?? ''),
        otherGb: int.tryParse(fields['other'] ?? ''),
      ),
      _ => null,
    };
  }

  Map<String, Object?> toJson() => {
    'paid': paid,
    'app': appGb,
    'other': otherGb,
  };

  static NekoPlan? fromJson(Object? json) {
    if (json is! Map || json['paid'] is! bool) return null;
    final app = json['app'];
    final other = json['other'];
    return NekoPlan(
      paid: json['paid'] as bool,
      appGb: app is int ? app : null,
      otherGb: other is int ? other : null,
    );
  }
}

/// The plan each profile's last answer named, as `neko_plans.json` next to
/// the app's data: `{"<profile id>": {"paid": false, "app": 10, ...}}`.
/// Outside the profile model, like the mirrors: a field there is a database
/// migration in upstream's schema at every merge.
class NekoPlanStore {
  NekoPlanStore._();

  static Future<void> _writes = Future.value();

  static Future<File> _file() async {
    return File(join(await appPath.homeDirPath, 'neko_plans.json'));
  }

  static Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final data = jsonDecode(await file.readAsString());
      return data is Map<String, dynamic> ? data : {};
    } on Exception {
      return {};
    }
  }

  static Future<NekoPlan?> of(int profileId) async {
    return NekoPlan.fromJson((await _read())['$profileId']);
  }

  /// Replaces the profile's plan; none removes it (not our profile, or an
  /// older bot). One write at a time; a failed one only logs.
  static Future<void> put(int profileId, NekoPlan? plan) {
    return _writes = _writes.then((_) async {
      try {
        final data = await _read();
        if (plan == null) {
          data.remove('$profileId');
        } else {
          data['$profileId'] = plan.toJson();
        }
        final file = await _file();
        await file.writeAsString(jsonEncode(data));
      } on Exception catch (error) {
        commonPrint.log(
          'plan not saved: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
    });
  }
}

enum NekoQuotaLevel { normal, high, out }

/// A key's month: the plan and the bytes from `subscription-userinfo`.
class NekoQuota {
  const NekoQuota({
    required this.plan,
    required this.used,
    required this.total,
    this.expire,
  });

  /// Warn from this share of the month's traffic on, like the bot does.
  static const highShare = 0.8;

  final NekoPlan plan;
  final int used;
  final int total;
  final DateTime? expire;

  double get share => total > 0 ? used / total : 0;

  NekoQuotaLevel get level {
    if (share >= 1) return NekoQuotaLevel.out;
    if (share >= highShare) return NekoQuotaLevel.high;
    return NekoQuotaLevel.normal;
  }

  /// A paid period that has ended; the key is off until a payment.
  bool expiredAt(DateTime now) {
    final end = expire;
    return plan.paid && end != null && end.isBefore(now);
  }

  /// A demo key still on the smaller allowance: the bot raises it after
  /// this app's first fetch, and the next profile update shows it.
  bool get belowAppAllowance {
    final app = plan.appGb;
    return !plan.paid && app != null && total < app * _bytesPerGb;
  }
}

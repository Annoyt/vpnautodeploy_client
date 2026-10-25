import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/profile_update.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _answered(Map<String, List<String>> headers) {
  final profile = Profile.normal(url: 'https://example.com/sub/token');
  return profile.withSubscriptionHeaders(Headers.fromMap(headers));
}

void main() {
  group('nekoUpdateInterval', () {
    test('reads hours, as the bot sends them', () {
      expect(nekoUpdateInterval('6'), const Duration(hours: 6));
      expect(nekoUpdateInterval(' 12 '), const Duration(hours: 12));
      expect(nekoUpdateInterval('1.5'), const Duration(minutes: 90));
    });

    test('never more often than hourly, never rarer than weekly', () {
      expect(nekoUpdateInterval('0.25'), const Duration(hours: 1));
      expect(nekoUpdateInterval('1'), const Duration(hours: 1));
      expect(nekoUpdateInterval('168'), const Duration(days: 7));
      expect(nekoUpdateInterval('100000'), const Duration(days: 7));
    });

    test('no usable number leaves the interval to the profile', () {
      for (final header in [null, '', 'six', '0', '-6', 'NaN', 'Infinity']) {
        expect(nekoUpdateInterval(header), isNull, reason: '$header');
      }
    });
  });

  group('a subscription answer', () {
    test('sets how often the profile is fetched again', () {
      final profile = _answered({'profile-update-interval': ['6']});
      expect(profile.autoUpdateDuration, const Duration(hours: 6));
    });

    test('without the header leaves the interval as it was', () {
      expect(_answered({}).autoUpdateDuration, defaultUpdateDuration);
      const threeHours = Duration(hours: 3);
      final profile = Profile.normal(url: 'https://example.com/sub/token');
      final custom = profile.copyWith(autoUpdateDuration: threeHours);
      final kept = custom.withSubscriptionHeaders(Headers.fromMap({}));
      expect(kept.autoUpdateDuration, threeHours);
    });

    test('still names the profile and reads the traffic', () {
      final profile = _answered({
        'content-disposition': ['attachment; filename="NekoVPN.yaml"'],
        'subscription-userinfo': ['upload=1; download=2; total=3; expire=4'],
      });
      expect(profile.label, 'NekoVPN.yaml');
      expect(profile.subscriptionInfo?.total, 3);
    });
  });
}

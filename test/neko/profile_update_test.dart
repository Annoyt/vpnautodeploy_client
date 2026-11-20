import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/profile_update.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _answered(Map<String, List<String>> headers) {
  final profile = Profile.normal(url: 'https://example.com/sub/token');
  return profile.withSubscriptionHeaders(Headers.fromMap(headers));
}

Profile _profile(int id, String url, {ProfileType type = ProfileType.url}) {
  return Profile(
    id: id,
    type: type,
    url: url,
    autoUpdateDuration: defaultUpdateDuration,
  );
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
      final profile = _answered({
        'profile-update-interval': ['6'],
      });
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

  group('nekoIntervalAfterUpdate', () {
    const day = Duration(days: 1);
    const sixHours = Duration(hours: 6);
    const twoHours = Duration(hours: 2);

    test('takes the interval the answer set', () {
      final after = nekoIntervalAfterUpdate(
        started: day,
        fetched: sixHours,
        now: day,
      );
      expect(after, sixHours);
    });

    test('the answer outranks an edit made during the download', () {
      final after = nekoIntervalAfterUpdate(
        started: day,
        fetched: sixHours,
        now: twoHours,
      );
      expect(after, sixHours);
    });

    test('an answer that kept the interval leaves the profile as it is', () {
      expect(
        nekoIntervalAfterUpdate(started: day, fetched: day, now: day),
        day,
      );
      expect(
        nekoIntervalAfterUpdate(started: day, fetched: day, now: twoHours),
        twoHours,
      );
    });
  });

  group('nekoSubscriptionKey', () {
    const key = 'https://sub.example.com/sub/token?format=clash';

    test('the scheme and the host in any case', () {
      expect(
        nekoSubscriptionKey('HTTPS://Sub.Example.COM/sub/token?format=clash'),
        key,
      );
    });

    test('with or without a trailing slash', () {
      expect(
        nekoSubscriptionKey('https://sub.example.com/sub/token/?format=clash'),
        key,
      );
      expect(
        nekoSubscriptionKey('https://sub.example.com//'),
        nekoSubscriptionKey('https://sub.example.com'),
      );
    });

    test('spaces around the link do not count', () {
      expect(nekoSubscriptionKey('  $key\n'), key);
    });

    test('the path and the query are kept as written', () {
      for (final other in [
        'https://sub.example.com/Sub/Token?format=clash',
        'https://sub.example.com/sub/token',
        'https://sub.example.com/sub/token?format=CLASH',
        'http://sub.example.com/sub/token?format=clash',
      ]) {
        expect(nekoSubscriptionKey(other), isNot(key), reason: other);
      }
    });

    test('a link that is no web address compares as it is', () {
      const share = 'vless://id@hk.example.com:443#HK';
      expect(nekoSubscriptionKey(' $share '), share);
    });
  });

  group('nekoSubscription', () {
    const url = 'https://sub.example.com/sub/token?format=clash';
    const spelled = 'HTTPS://SUB.example.com/sub/token/?format=clash';

    test('finds the profile of the same subscription', () {
      final profiles = [
        _profile(1, 'https://other.example.com/sub/token?format=clash'),
        _profile(2, url),
      ];
      expect(profiles.nekoSubscription(spelled)?.id, 2);
      expect(profiles.nekoSubscription(url, currentId: 1)?.id, 2);
    });

    test('of several copies, the current one, otherwise the first', () {
      final profiles = [_profile(1, url), _profile(2, url), _profile(3, url)];
      expect(profiles.nekoSubscription(url, currentId: 2)?.id, 2);
      expect(profiles.nekoSubscription(url, currentId: 9)?.id, 1);
      expect(profiles.nekoSubscription(url)?.id, 1);
    });

    test('only a URL profile, and none for a new address', () {
      final profiles = [
        _profile(1, url, type: ProfileType.file),
        _profile(2, url, type: ProfileType.custom),
        _profile(3, 'https://sub.example.com/sub/other?format=clash'),
      ];
      expect(profiles.nekoSubscription(url), isNull);
      expect(<Profile>[].nekoSubscription(url), isNull);
    });
  });
}

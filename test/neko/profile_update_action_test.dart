import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/mirrors.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_profiles.dart';

const _url = 'https://sub.example.com/sub/a?format=clash';
const _other = 'https://sub.example.com/sub/b?format=clash';

class _MockCore extends Mock implements CoreHandlerInterface {}

class _RecordingSetupAction extends SetupAction {
  int applied = 0;

  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {
    applied++;
  }
}

Response<Uint8List> _answer(String url, Map<String, String> headers) {
  return Response(
    requestOptions: RequestOptions(path: url),
    data: Uint8List.fromList('proxies: []\n'.codeUnits),
    statusCode: 200,
    headers: Headers.fromMap({
      for (final MapEntry(:key, :value) in headers.entries) key: [value],
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  var headers = <String, String>{};
  final asked = <String>[];
  Completer<void>? arrived;
  Completer<void>? held;
  late _MockCore core;
  late _RecordingSetupAction setupAction;
  late ProviderContainer container;

  setUpAll(() async {
    loadAppLocalizations(const Locale('en'));
    home = Directory.systemTemp.createTempSync('neko-profile-update-');
    await useAppPaths(home);
  });

  tearDownAll(() => home.deleteSync(recursive: true));

  setUp(() {
    final network = nekoFetchProfile;
    addTearDown(() => nekoFetchProfile = network);
    nekoFetchProfile = (url) async {
      asked.add(url);
      arrived?.complete();
      await held?.future;
      return _answer(url, headers);
    };
    headers = {};
    asked.clear();
    arrived = null;
    held = null;
    core = _MockCore();
    when(() => core.validateConfig(any())).thenAnswer((_) async => null);
    when(() => core.clearEffect(any())).thenAnswer((_) async => '');
    setupAction = _RecordingSetupAction();
  });

  void start(List<Profile> profiles, {int? currentId}) {
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles(profiles)),
        currentProfileIdProvider.overrideWithBuild((_, _) => currentId),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        setupActionProvider.overrideWith(() => setupAction),
      ],
    );
    addTearDown(container.dispose);
    container.listen(currentProfileIdProvider, (_, _) {});
    globalState.container = container;
  }

  ProfilesAction action() => container.read(profilesActionProvider.notifier);

  List<Profile> profiles() => container.read(profilesProvider);

  Profile saved(int id) => profiles().getProfile(id)!;

  group('a link to a subscription already added', () {
    test('opened twice adds one profile, then refreshes it', () async {
      start(const []);
      headers = {'content-disposition': 'attachment; filename="NekoVPN"'};

      await action().addProfileFromLink(_url);
      final added = profiles().single;
      headers = {'subscription-userinfo': 'upload=1; download=2; total=3'};
      await action().addProfileFromLink(_url);

      expect(profiles().single.id, added.id);
      expect(profiles().single.label, 'NekoVPN');
      expect(profiles().single.subscriptionInfo?.total, 3);
      expect(asked, [_url, _url]);
      expect(setupAction.applied, 1);
    });

    test('makes the refreshed profile current', () async {
      final subscription = Profile.normal(url: _url);
      final other = Profile.normal(url: _other);
      start([subscription, other], currentId: other.id);

      await action().addProfileFromLink(_url);

      expect(profiles().map((profile) => profile.id), [
        subscription.id,
        other.id,
      ]);
      expect(container.read(currentProfileIdProvider), subscription.id);
      expect(saved(subscription.id).lastUpdateDate, isNotNull);
      expect(saved(other.id).lastUpdateDate, isNull);
    });

    test('is not made current once deleted meanwhile', () async {
      final subscription = Profile.normal(url: _url);
      final other = Profile.normal(url: _other);
      start([subscription, other], currentId: other.id);
      arrived = Completer();
      held = Completer();

      final opening = action().addProfileFromLink(_url);
      await arrived!.future;
      await container.read(profilesProvider.notifier).del(subscription.id);
      held!.complete();
      await opening;

      expect(profiles().single.id, other.id);
      expect(container.read(currentProfileIdProvider), other.id);
    });

    test('is found in another spelling and keeps its own address', () async {
      start([Profile.normal(url: _url)]);

      await action().addProfileFromLink(
        ' HTTPS://Sub.Example.COM/sub/a/?format=clash ',
      );

      expect(profiles().single.url, _url);
      expect(profiles().single.lastUpdateDate, isNotNull);
      expect(asked, [_url]);
    });

    test('at another address is added beside it', () async {
      final subscription = Profile.normal(url: _url);
      start([subscription], currentId: subscription.id);

      await action().addProfileFromLink(_other);

      expect(profiles().map((profile) => profile.url), [_url, _other]);
      expect(container.read(currentProfileIdProvider), subscription.id);
      expect(asked, [_other]);
    });
  });

  group('an update', () {
    Profile subscription({
      Duration interval = const Duration(hours: 6),
      bool autoUpdate = true,
    }) {
      return Profile.normal(
        url: _url,
      ).copyWith(autoUpdateDuration: interval, autoUpdate: autoUpdate);
    }

    Future<Profile> update(Profile profile, String? interval) async {
      headers = {'profile-update-interval': ?interval};
      await action().updateProfile(profile);
      return saved(profile.id);
    }

    test('takes the interval the service asks for now', () async {
      final profile = subscription();
      start([profile]);

      final updated = await update(profile, '12');

      expect(updated.autoUpdateDuration, const Duration(hours: 12));
    });

    test('keeps the interval between an hour and a week', () async {
      final profile = subscription();
      start([profile]);

      final often = await update(profile, '0.1');
      expect(often.autoUpdateDuration, const Duration(hours: 1));
      final rarely = await update(often, '1000');
      expect(rarely.autoUpdateDuration, const Duration(days: 7));
    });

    test('without a usable header keeps the interval it has', () async {
      const threeHours = Duration(hours: 3);
      final profile = subscription(interval: threeHours);
      start([profile]);

      for (final interval in [null, 'soon', '0']) {
        final updated = await update(saved(profile.id), interval);
        expect(updated.autoUpdateDuration, threeHours, reason: '$interval');
      }
      expect(asked, hasLength(3));
    });

    test('leaves auto update off', () async {
      final profile = subscription(autoUpdate: false);
      start([profile]);

      final updated = await update(profile, '12');

      expect(updated.autoUpdate, isFalse);
      expect(updated.autoUpdateDuration, const Duration(hours: 12));
    });

    test('an edit made while it downloads stands without a header', () async {
      const twoHours = Duration(hours: 2);
      final profile = subscription();
      start([profile]);
      arrived = Completer();
      held = Completer();

      final updating = action().updateProfile(profile);
      await arrived!.future;
      container
          .read(profilesProvider.notifier)
          .put(profile.copyWith(autoUpdateDuration: twoHours));
      held!.complete();
      await updating;

      expect(saved(profile.id).autoUpdateDuration, twoHours);
      expect(saved(profile.id).lastUpdateDate, isNotNull);
    });
  });
}

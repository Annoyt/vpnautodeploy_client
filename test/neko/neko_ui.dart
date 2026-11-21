import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/home.dart';
import 'package:fl_clash/neko/layout.dart';
import 'package:fl_clash/neko/links.dart';
import 'package:fl_clash/neko/quota.dart';
import 'package:fl_clash/neko/view_mode.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const nekoTestMail = 'help@neko.example';

/// NekoVPN's layout for this test only: the next file may be upstream's.
void useNekoLayout() {
  debugNekoLayout = true;
  addTearDown(() => debugNekoLayout = null);
}

class Launches {
  final opened = <String>[];
  var answer = true;
  var fails = false;

  Future<bool> launch(Uri uri) async {
    opened.add(uri.toString());
    if (fails) throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
    return answer;
  }
}

class RecordingProfilesAction extends ProfilesAction {
  final added = <String>[];
  final updated = <int>[];

  @override
  Future<void> addProfileFromLink(
    String link, {
    String? label,
    String ageSecretKey = '',
  }) async {
    added.add(link);
  }

  @override
  Future<void> updateProfile(
    Profile profile, {
    bool showLoading = false,
  }) async {
    updated.add(profile.id);
  }
}

class RecordingCommonAction extends CommonAction {
  var toggles = 0;

  @override
  void toggleRunning() {
    toggles++;
  }
}

class RecordingProxiesAction extends ProxiesAction {
  final picks = <String>[];
  var refreshes = 0;

  @override
  void changeProxyDebounce(String groupName, String proxyName) {
    picks.add('$groupName $proxyName');
  }

  @override
  void updateGroupsDebounce([Duration? duration]) {
    refreshes++;
  }
}

class NekoTestApp {
  NekoTestApp({
    this.profiles = const [],
    this.mail,
    this.plan,
    this.advanced = false,
    this.overrides = const [],
  });

  final List<Profile> profiles;
  final String? mail;
  final NekoPlan? plan;
  final bool advanced;
  final List<Override> overrides;

  final launches = Launches();
  final profilesAction = RecordingProfilesAction();
  final commonAction = RecordingCommonAction();
  final proxiesAction = RecordingProxiesAction();
  final saved = <bool>[];
  late final ProviderContainer container;

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(400, 900),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles(profiles)),
        currentProfileIdProvider.overrideWithBuild(
          (_, _) => profiles.firstOrNull?.id,
        ),
        nekoAdvancedProvider.overrideWith(
          () => NekoAdvancedMode(save: (advanced) async => saved.add(advanced)),
        ),
        nekoLaunchProvider.overrideWithValue(launches.launch),
        nekoMailProvider.overrideWith((ref) async => mail),
        nekoCurrentPlanProvider.overrideWith((ref) async => plan),
        profilesActionProvider.overrideWith(() => profilesAction),
        commonActionProvider.overrideWith(() => commonAction),
        proxiesActionProvider.overrideWith(() => proxiesAction),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = size;
    if (advanced) {
      await container.read(nekoAdvancedProvider.notifier).set(true);
      saved.clear();
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(child: child),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }
}

/// Answers `Clipboard.getData` with [text] for this test.
void mockClipboard(WidgetTester tester, String? text, {bool fails = false}) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method != 'Clipboard.getData') return null;
    if (fails) throw PlatformException(code: 'denied');
    return text == null ? null : <String, Object?>{'text': text};
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

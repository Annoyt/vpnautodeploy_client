import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/neko/consent.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/disclaimer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import 'neko_ui.dart';

const _phone = Size(360, 640);

Future<void> _pumpPhone(WidgetTester tester, [Size size = _phone]) async {
  useNekoLayout();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).value = size;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const TestApp(child: Scaffold(body: SizedBox.shrink())),
    ),
  );
  await tester.pump();
}

FilledButton _agree(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.descendant(
      of: find.byType(NekoConsentBar),
      matching: find.byType(FilledButton),
    ),
  );
}

bool _hittable(WidgetTester tester, Finder finder) {
  final target = tester.renderObject(finder);
  final result = tester.hitTestOnBinding(tester.getCenter(finder));
  return result.path.any((entry) => entry.target == target);
}

void main() {
  testWidgets('on a small phone the tick is in view and gates «Agree»', (
    tester,
  ) async {
    await _pumpPhone(tester);
    final agreed = requestDisclaimerConsent();
    await tester.pumpAndSettle();
    final l10n = currentAppLocalizations;
    final tick = find.text(l10n.disclaimerAcknowledgeLabel);
    expect(tick, findsOneWidget);
    expect(_hittable(tester, tick), isTrue);
    expect(_agree(tester).onPressed, isNull);

    await tester.tap(tick);
    await tester.pump();
    expect(_agree(tester).onPressed, isNotNull);
    await tester.tap(find.text(l10n.agree));
    await tester.pumpAndSettle();
    expect(find.text(l10n.disclaimerAcknowledgeTitle), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(await agreed, isTrue);
  });

  testWidgets('a tablet keeps the tick by the buttons', (tester) async {
    await _pumpPhone(tester, const Size(1000, 800));
    final agreed = requestDisclaimerConsent();
    await tester.pumpAndSettle();
    final tick = find.text(currentAppLocalizations.disclaimerAcknowledgeLabel);
    expect(_hittable(tester, tick), isTrue);
    await tester.tap(tick);
    await tester.pump();
    await tester.tap(find.text(currentAppLocalizations.agree));
    await tester.pumpAndSettle();
    expect(await agreed, isTrue);
  });

  testWidgets('«Exit» declines on the phone too', (tester) async {
    await _pumpPhone(tester);
    final agreed = requestDisclaimerConsent();
    await tester.pumpAndSettle();
    await tester.tap(find.text(currentAppLocalizations.exit));
    await tester.pumpAndSettle();
    expect(await agreed, isFalse);
  });
}

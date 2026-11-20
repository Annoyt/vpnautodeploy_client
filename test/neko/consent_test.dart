import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/disclaimer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import 'neko_ui.dart';

TextButton _button(WidgetTester tester, String label) {
  return tester.widget<TextButton>(find.widgetWithText(TextButton, label));
}

void main() {
  testWidgets('on the phone a tick, not the typed statement, gates «Agree»', (
    tester,
  ) async {
    useNekoLayout();
    const size = Size(400, 800);
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

    final agreed = requestDisclaimerConsent();
    await tester.pumpAndSettle();
    final l10n = currentAppLocalizations;
    await tester.tap(find.text(l10n.agree));
    await tester.pumpAndSettle();
    expect(find.text(l10n.disclaimerAcknowledgeTitle), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(_button(tester, l10n.confirm).onPressed, isNull);

    await tester.tap(find.text(l10n.disclaimerAcknowledgeLabel));
    await tester.pump();
    expect(_button(tester, l10n.confirm).onPressed, isNotNull);
    await tester.tap(find.text(l10n.confirm));
    await tester.pumpAndSettle();
    expect(await agreed, isTrue);
  });
}

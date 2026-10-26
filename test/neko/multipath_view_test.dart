import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/multipath.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('the Tools entry shows the mode and saves a choice', (
    tester,
  ) async {
    final written = <NekoMultipathMode>[];
    await tester.pumpWidget(
      TestApp(
        child: Scaffold(
          body: NekoMultipathItem(
            read: () async => NekoMultipathMode.failover,
            write: (mode) async => written.add(mode),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(nekoMultipathTitle), findsOneWidget);
    expect(find.text(nekoMultipathFailover), findsOneWidget);
    await tester.tap(find.text(nekoMultipathTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(nekoMultipathDistribute).last);
    await tester.pumpAndSettle();
    expect(written, [NekoMultipathMode.distribute]);
  });
}

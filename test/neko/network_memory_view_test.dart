import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/network_memory_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('the Tools switch reads and saves the choice', (tester) async {
    final written = <bool>[];
    await tester.pumpWidget(
      TestApp(
        child: Scaffold(
          body: NekoNetworkMemoryItem(
            read: () async => true,
            write: (enabled) async => written.add(enabled),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(nekoNetworkMemoryTitle), findsOneWidget);
    await tester.tap(find.text(nekoNetworkMemoryTitle));
    await tester.pumpAndSettle();
    expect(written, [false]);
  });
}

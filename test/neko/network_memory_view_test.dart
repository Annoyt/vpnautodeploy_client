import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/network_memory_manager.dart';
import 'package:fl_clash/providers/providers.dart';
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

  testWidgets('the manager follows the network and lets go on dispose', (
    tester,
  ) async {
    final changes = StreamController<List<ConnectivityResult>>();
    addTearDown(changes.close);
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [isStartProvider.overrideWithValue(false)],
        child: NekoNetworkMemoryManager(
          connectivityStream: changes.stream,
          interfaces: () async => [],
          rememberEvery: const Duration(seconds: 1),
          child: const Text('app'),
        ),
      ),
    );
    expect(find.text('app'), findsOneWidget);
    // The VPN is off: a change and a tick are noticed and left alone.
    changes.add([ConnectivityResult.mobile]);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    expect(changes.hasListener, isFalse);
  });
}

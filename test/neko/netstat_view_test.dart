import 'package:fl_clash/neko/brand.dart';
import 'package:fl_clash/neko/netstat_view.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

const _channel = MethodChannel('com.follow.clash/neko_netstat');

class _Switch {
  _Switch({this.stored = false, this.granted = true, this.located = true});

  bool stored;
  bool granted;
  bool located;
  var asked = 0;
  final written = <bool>[];
  final notes = <String>[];

  Future<bool> read() async => stored;

  Future<void> write(bool enabled) async {
    written.add(enabled);
    stored = enabled;
  }

  NekoNetstatItem item() {
    return NekoNetstatItem(
      read: read,
      write: write,
      hasLocation: () async => located,
      requestLocation: () async {
        asked++;
        return granted;
      },
      notify: (context, text) => notes.add(text),
    );
  }
}

Future<void> _pump(WidgetTester tester, Widget item) async {
  await tester.pumpWidget(TestApp(child: Scaffold(body: item)));
  await tester.pumpAndSettle();
}

bool _on(WidgetTester tester) {
  return tester.widget<Switch>(find.byType(Switch)).value;
}

Future<void> _toggle(WidgetTester tester) async {
  await tester.tap(find.text(nekoNetstatTitle));
  await tester.pumpAndSettle();
}

void main() {
  test('the Tools section says what goes, and when the cell does', () {
    expect(nekoNetstatSection, isNotEmpty);
    expect(nekoNetstatFooter, contains('10'));
  });

  testWidgets('off by default; on once location is allowed', (tester) async {
    final state = _Switch();
    await _pump(tester, state.item());
    expect(find.text(nekoNetstatTitle), findsOneWidget);
    expect(find.text(nekoNetstatSubtitle), findsOneWidget);
    expect(_on(tester), isFalse);
    await _toggle(tester);
    expect(state.asked, 1);
    expect(state.written, [true]);
    expect(_on(tester), isTrue);
    expect(state.notes, isEmpty);
  });

  testWidgets('denied: back off with a note, and kept off', (tester) async {
    final state = _Switch(granted: false);
    await _pump(tester, state.item());
    await _toggle(tester);
    expect(_on(tester), isFalse);
    expect(state.written, [false]);
    expect(state.notes, [nekoNetstatDenied]);
    expect(state.stored, isFalse);
  });

  testWidgets('on stays on; switching off asks nothing', (tester) async {
    final state = _Switch(stored: true);
    await _pump(tester, state.item());
    expect(_on(tester), isTrue);
    expect(state.written, isEmpty);
    await _toggle(tester);
    expect(_on(tester), isFalse);
    expect(state.written, [false]);
    expect(state.asked, 0);
  });

  testWidgets('a permission taken back turns the switch off', (tester) async {
    final state = _Switch(stored: true, located: false);
    await _pump(tester, state.item());
    expect(_on(tester), isFalse);
    expect(state.written, [false]);
  });

  testWidgets('asks the Android side; its failure is a no', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final methods = <String>[];
    var answer = true;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      methods.add(call.method);
      if (call.method == 'requestLocation' && !answer) {
        throw PlatformException(code: 'no_activity');
      }
      return answer;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
    final state = _Switch(stored: true);
    await _pump(tester, NekoNetstatItem(read: state.read, write: state.write));
    expect(_on(tester), isTrue);
    await _toggle(tester);
    answer = false;
    await _toggle(tester);
    expect(_on(tester), isFalse);
    expect(methods, ['hasLocation', 'requestLocation']);
    expect(state.written, [false, false]);
  });
}

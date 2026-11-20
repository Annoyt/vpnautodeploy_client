import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/neko/speed.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('the top speed keeps the highest of each direction', () {
    var top = const NekoTopSpeed();
    top = top.seen(const Traffic(up: 10, down: 300));
    top = top.seen(const Traffic(up: 50, down: 100));
    expect((top.up, top.down), (50, 300));
    final same = top.seen(const Traffic(up: 20, down: 200));
    expect(identical(same, top), isTrue);
  });

  test('a start opens a new session, a stop keeps the figures', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(nekoTopSpeedProvider, (_, _) {});
    Future<void> run(bool running) async {
      container.read(runTimeProvider.notifier).value = running ? 1000 : null;
      container.read(isStartProvider);
      await _settle();
    }

    Future<void> sample(int up, int down) async {
      container
          .read(trafficsProvider.notifier)
          .addTraffic(Traffic(up: up, down: down));
      await _settle();
    }

    (num, num) top() {
      final speed = container.read(nekoTopSpeedProvider);
      return (speed.up, speed.down);
    }

    await run(true);
    await sample(100, 2000);
    await sample(300, 500);
    expect(top(), (300, 2000));

    await run(false);
    container.read(trafficsProvider.notifier).clear();
    await _settle();
    expect(top(), (300, 2000));

    await run(true);
    expect(top(), (0, 0));
    await sample(5, 7);
    expect(top(), (5, 7));
  });
}

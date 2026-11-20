import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A VPN session's top upload and download, in bytes a second.
class NekoTopSpeed {
  const NekoTopSpeed({this.up = 0, this.down = 0});

  final num up;
  final num down;

  NekoTopSpeed seen(Traffic traffic) {
    if (traffic.up <= up && traffic.down <= down) return this;
    return NekoTopSpeed(
      up: math.max(up, traffic.up),
      down: math.max(down, traffic.down),
    );
  }
}

/// A start opens a new session; a stop keeps the last one's figures.
class NekoTopSpeedTracker extends Notifier<NekoTopSpeed> {
  @override
  NekoTopSpeed build() {
    ref.listen(isStartProvider, (previous, running) {
      if (running && previous == false) state = const NekoTopSpeed();
    });
    ref.listen(
      trafficsProvider.select(
        (traffics) => traffics.list.safeLast(const Traffic()),
      ),
      (_, traffic) => state = state.seen(traffic),
    );
    return const NekoTopSpeed();
  }
}

final nekoTopSpeedProvider =
    NotifierProvider<NekoTopSpeedTracker, NekoTopSpeed>(
      NekoTopSpeedTracker.new,
    );

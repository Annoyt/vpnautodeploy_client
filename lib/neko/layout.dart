import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/foundation.dart';

import 'brand.dart';

@visibleForTesting
bool? debugNekoLayout;

/// The owner's board lays out the Android app, the one NekoVPN ships.
bool get nekoLayout => debugNekoLayout ?? system.isAndroid;

String? nekoPageLabel(PageLabel label) {
  if (!nekoLayout) return null;
  return switch (label) {
    PageLabel.dashboard => nekoHomeTitle,
    PageLabel.tools => nekoSettingsTitle,
    _ => null,
  };
}

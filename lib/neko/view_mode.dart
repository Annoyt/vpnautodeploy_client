import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';

import 'layout.dart';

enum NekoView { flclash, simple, advanced }

const nekoViewFile = 'neko_view.json';

/// `{"advanced": true}`, apart from the app's settings, which upstream's
/// migrations own.
class NekoViewStore {
  NekoViewStore._();

  static Future<File> _file() async {
    return File(join(await appPath.homeDirPath, nekoViewFile));
  }

  static Future<bool> advanced() async {
    try {
      final file = await _file();
      if (!await file.exists()) return false;
      final data = jsonDecode(await file.readAsString());
      return data is Map && data['advanced'] == true;
    } on Exception {
      return false;
    }
  }

  static Future<void> setAdvanced(bool advanced) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({'advanced': advanced}));
    } on Exception catch (error) {
      commonPrint.log(
        'view not saved: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    }
  }
}

/// Starts from the file, read before the first frame (bootstrap.dart).
class NekoAdvancedMode extends Notifier<bool> {
  NekoAdvancedMode({this.save = NekoViewStore.setAdvanced});

  final Future<void> Function(bool advanced) save;

  @override
  bool build() => false;

  Future<void> set(bool advanced) {
    state = advanced;
    return save(advanced);
  }
}

final nekoAdvancedProvider = NotifierProvider<NekoAdvancedMode, bool>(
  NekoAdvancedMode.new,
);

final nekoViewProvider = Provider<NekoView>((ref) {
  if (!nekoLayout) return NekoView.flclash;
  return ref.watch(nekoAdvancedProvider) ? NekoView.advanced : NekoView.simple;
});

List<NavigationItem> nekoNavigationItems(
  List<NavigationItem> items,
  NekoView view,
) {
  if (view != NekoView.simple) return items;
  return [
    for (final item in items)
      if (item.label == PageLabel.dashboard || item.label == PageLabel.tools)
        item,
  ];
}

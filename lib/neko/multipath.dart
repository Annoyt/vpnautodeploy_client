import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart';

import 'brand.dart';

/// How the VPN uses Wi-Fi and mobile data at once (client plan E37,
/// docs/MULTIPATH.md 3.1). The service's NekoNetworksModule reads it from
/// [nekoMultipathFile] in the app's files every few seconds, and the core
/// binds each new connection to a network accordingly.
enum NekoMultipathMode { off, failover, distribute }

const nekoMultipathFile = 'neko_multipath.json';

Future<File> _file() async {
  return File(join(await appPath.homeDirPath, nekoMultipathFile));
}

/// The mode in force; off when nothing was chosen or the file is unreadable.
Future<NekoMultipathMode> nekoReadMultipathMode() async {
  try {
    final file = await _file();
    if (!await file.exists()) return NekoMultipathMode.off;
    final data = jsonDecode(await file.readAsString());
    final mode = data is Map ? data['mode'] : null;
    return NekoMultipathMode.values.firstWhere(
      (value) => value.name == mode,
      orElse: () => NekoMultipathMode.off,
    );
  } on Exception {
    return NekoMultipathMode.off;
  }
}

/// Saves [mode] in one step: the service never reads half a file.
Future<void> nekoWriteMultipathMode(NekoMultipathMode mode) async {
  final file = await _file();
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(jsonEncode({'mode': mode.name}));
  await temp.rename(file.path);
}

String nekoMultipathLabel(NekoMultipathMode mode) {
  return switch (mode) {
    NekoMultipathMode.off => nekoMultipathOff,
    NekoMultipathMode.failover => nekoMultipathFailover,
    NekoMultipathMode.distribute => nekoMultipathDistribute,
  };
}

/// The Tools entry: off, backup or both networks at once.
class NekoMultipathItem extends StatefulWidget {
  const NekoMultipathItem({super.key, this.read, this.write});

  /// Replaced in tests; the file by default.
  final Future<NekoMultipathMode> Function()? read;
  final Future<void> Function(NekoMultipathMode mode)? write;

  @override
  State<NekoMultipathItem> createState() => _NekoMultipathItemState();
}

class _NekoMultipathItemState extends State<NekoMultipathItem> {
  NekoMultipathMode _mode = NekoMultipathMode.off;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final mode = await (widget.read ?? nekoReadMultipathMode)();
    if (mounted) setState(() => _mode = mode);
  }

  Future<void> _change(NekoMultipathMode mode) async {
    setState(() => _mode = mode);
    await (widget.write ?? nekoWriteMultipathMode)(mode);
  }

  @override
  Widget build(BuildContext context) {
    return ListItem<NekoMultipathMode>.options(
      leading: const GlyphIcon(AppGlyphs.wifi),
      title: Text(nekoMultipathTitle),
      options: NekoMultipathMode.values,
      value: _mode,
      textBuilder: nekoMultipathLabel,
      onChanged: (mode) => unawaited(_change(mode)),
    );
  }
}

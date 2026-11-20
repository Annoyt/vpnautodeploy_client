import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';

import 'brand.dart';
import 'netstat.dart';
import 'netstat_manager.dart';

const _native = NekoNetstatNative();

class NekoNetstatItem extends StatefulWidget {
  const NekoNetstatItem({
    super.key,
    this.read,
    this.write,
    this.hasLocation,
    this.requestLocation,
    this.notify,
  });

  /// Replaced in tests; the switch file and the Android side by default.
  final Future<bool> Function()? read;
  final Future<void> Function(bool enabled)? write;
  final Future<bool> Function()? hasLocation;
  final Future<bool> Function()? requestLocation;
  final void Function(BuildContext context, String text)? notify;

  @override
  State<NekoNetstatItem> createState() => _NekoNetstatItemState();
}

class _NekoNetstatItemState extends State<NekoNetstatItem> {
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _write(bool enabled) {
    return (widget.write ?? nekoWriteNetstatCell)(enabled);
  }

  /// A permission taken back in the system settings turns the switch off.
  Future<void> _load() async {
    var enabled = await (widget.read ?? nekoReadNetstatCell)();
    if (enabled && !await _ask(widget.hasLocation ?? _native.hasLocation)) {
      enabled = false;
      await _write(false);
    }
    if (mounted) setState(() => _enabled = enabled);
  }

  Future<void> _change(bool enabled) async {
    setState(() => _enabled = enabled);
    if (!enabled) {
      await _write(false);
      return;
    }
    final granted = await _ask(
      widget.requestLocation ?? _native.requestLocation,
    );
    await _write(granted);
    if (granted) return;
    if (!mounted) return;
    setState(() => _enabled = false);
    (widget.notify ?? _note)(context, nekoNetstatDenied);
  }

  @override
  Widget build(BuildContext context) {
    return ListItem.toggle(
      leading: const GlyphIcon(AppGlyphs.target),
      title: Text(nekoNetstatTitle),
      subtitle: Text(nekoNetstatSubtitle),
      value: _enabled,
      onChanged: (enabled) => unawaited(_change(enabled)),
    );
  }
}

Future<bool> _ask(Future<bool> Function() permission) async {
  try {
    return await permission();
  } on Exception {
    return false;
  }
}

void _note(BuildContext context, String text) => dialogs.showBanner(text);

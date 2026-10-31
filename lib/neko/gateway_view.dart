import 'dart:async';

import 'package:fl_clash/pages/scan.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'gateway.dart';

/// The entry in Tools that opens [NekoGatewayView].
class NekoGatewayItem extends StatelessWidget {
  const NekoGatewayItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.devices),
      title: Text(nekoGatewayTitle),
      subtitle: Text(nekoGatewaySubtitle),
      widget: const NekoGatewayView(),
    );
  }
}

/// Share this phone's network with a neighbour, or go out through one.
class NekoGatewayView extends ConsumerStatefulWidget {
  const NekoGatewayView({
    super.key,
    this.read,
    this.write,
    this.apply,
    this.hosts,
    this.scan,
  });

  /// Replaced in tests; the file, the core and the device by default.
  final Future<NekoGateway> Function()? read;
  final Future<void> Function(NekoGateway gateway)? write;
  final void Function()? apply;
  final Future<List<String>> Function()? hosts;
  final Future<String?> Function(BuildContext context)? scan;

  @override
  ConsumerState<NekoGatewayView> createState() => _NekoGatewayViewState();
}

class _NekoGatewayViewState extends ConsumerState<NekoGatewayView> {
  NekoGateway _gateway = const NekoGateway();
  List<String> _hosts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final gateway = await (widget.read ?? nekoReadGateway)();
    final hosts = await (widget.hosts ?? nekoGatewayHosts)();
    if (!mounted) return;
    setState(() {
      _gateway = gateway;
      _hosts = hosts;
      _loading = false;
    });
  }

  /// Saves the choice and loads the profile again: the core reads the
  /// gateway when it loads one.
  Future<void> _save(NekoGateway gateway) async {
    setState(() => _gateway = gateway);
    await (widget.write ?? nekoWriteGateway)(gateway);
    final apply = widget.apply;
    if (apply != null) {
      apply();
    } else {
      ref
          .read(setupActionProvider.notifier)
          .applyProfileDebounce(silence: true, force: true);
    }
  }

  Future<void> _toggleShare(bool value) async {
    if (value) {
      final hosts = await (widget.hosts ?? nekoGatewayHosts)();
      if (!mounted) return;
      setState(() => _hosts = hosts);
      await _save(NekoGateway(share: NekoGatewayShare.create()));
    } else {
      await _save(const NekoGateway());
    }
  }

  Future<String?> _defaultScan(BuildContext context) {
    return BaseNavigator.push<String>(
      context,
      ScanPage(
        accept: nekoGatewayLinkFromQrCodes,
        invalidHint: nekoGatewayInvalidCode,
      ),
    );
  }

  Future<void> _join() async {
    final link = await (widget.scan ?? _defaultScan)(context);
    final join = nekoGatewayFromLink(link);
    if (join == null || !mounted) return;
    await _save(NekoGateway(join: join));
  }

  List<Widget> _shareItems(NekoGatewayShare share) {
    if (_hosts.isEmpty) {
      return [
        generateSection(items: [ListItem(title: Text(nekoGatewayNoNetwork))]),
      ];
    }
    return [
      Center(child: QrCodeView(data: nekoGatewayLink(share, _hosts))),
      const SizedBox(height: 8),
      generateSection(
        items: [
          ListItem(
            title: Text(_hosts.join(', ')),
            subtitle: Text(nekoGatewayShareHint),
          ),
        ],
      ),
    ];
  }

  List<Widget> _joinItems() {
    final join = _gateway.join;
    if (join == null) {
      return [
        ListItem(
          leading: const GlyphIcon(AppGlyphs.qrCode),
          title: Text(nekoGatewayScan),
          subtitle: Text(nekoGatewayScanSubtitle),
          onTap: () => unawaited(_join()),
        ),
      ];
    }
    return [
      ListItem(
        leading: const GlyphIcon(AppGlyphs.devices),
        title: Text('${join.hosts.join(', ')}:${join.port}'),
        subtitle: Text(nekoGatewayJoined),
      ),
      ListItem(
        leading: const GlyphIcon(AppGlyphs.close),
        title: Text(nekoGatewayLeave),
        onTap: () => unawaited(_save(const NekoGateway())),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final share = _gateway.share;
    return CommonScaffold(
      isLoading: _loading,
      title: nekoGatewayTitle,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.contentTopPadding,
          bottom: 32 + context.bottomInset,
        ),
        children: [
          Text(nekoGatewayIntro, style: AppTextStyle.subheadline.of(context)),
          const SizedBox(height: 16),
          generateSection(
            title: nekoGatewayShareSection,
            items: [
              ListItem.toggle(
                title: Text(nekoGatewayShare),
                subtitle: Text(nekoGatewayShareSubtitle),
                value: share != null,
                onChanged: (value) => unawaited(_toggleShare(value)),
              ),
            ],
          ),
          if (share != null) ..._shareItems(share),
          generateSection(title: nekoGatewayJoinSection, items: _joinItems()),
        ],
      ),
    );
  }
}

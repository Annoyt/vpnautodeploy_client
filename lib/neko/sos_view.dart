import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'remote_settings.dart';
import 'sos.dart';

/// The entry in Tools that opens [NekoSosView].
class NekoSosItem extends StatelessWidget {
  const NekoSosItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      leading: const GlyphIcon(AppGlyphs.warning),
      title: Text(nekoSosTitle),
      subtitle: Text(nekoSosSubtitle),
      widget: const NekoSosView(),
    );
  }
}

typedef NekoSosSend =
    Future<NekoSosAnswer?> Function(
      String token,
      Map<String, Object?> report,
      Iterable<String> origins,
    );

/// "Cannot connect": sends the service what the app sees (POST
/// /api/neko/sos), shows what works right now and offers the emergency
/// profile; with no answer from any address, the bot and a copy.
class NekoSosView extends ConsumerStatefulWidget {
  const NekoSosView({super.key, this.send, this.network, this.settings});

  /// Replaced in tests; the service, the device and the store by default.
  final NekoSosSend? send;
  final Future<String?> Function()? network;
  final Future<NekoSettings?> Function()? settings;

  @override
  ConsumerState<NekoSosView> createState() => _NekoSosViewState();
}

class _NekoSosViewState extends ConsumerState<NekoSosView> {
  bool _sending = false;
  bool _failed = false;
  bool _noProfile = false;
  NekoSosAnswer? _answer;
  Map<String, Object?>? _report;

  Future<NekoSosAnswer?> _defaultSend(
    String token,
    Map<String, Object?> report,
    Iterable<String> origins,
  ) {
    return nekoSendSos(
      token,
      report,
      origins: origins,
      post: (url, body) => nekoPostJson(request.dio, url, body),
    );
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _failed = false;
      _noProfile = false;
      _answer = null;
    });
    final kept = await (widget.settings ?? NekoSettingsStore.current)();
    final origins = {...?kept?.endpoints, ...nekoSettingsEndpoints};
    final profiles = ref.read(profilesProvider);
    final current = ref.read(currentProfileProvider);
    final ordered = [?current, ...profiles];
    final token = nekoServiceToken(ordered.map((p) => p.url), origins);
    if (token == null) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _noProfile = true;
      });
      return;
    }
    final ours = ordered.firstWhere((p) => p.url.contains('/sub/$token'));
    final report = nekoSosReport(
      app: globalState.packageInfo.version,
      platform: system.isAndroid ? 'android' : 'desktop',
      network: await (widget.network ?? nekoNetworkType)(),
      vpnRunning: ref.read(isStartProvider),
      profileUpdated: ours.lastUpdateDate,
      settingsVersion: kept?.version,
      delays: nekoDelays(ref.read(delayDataSourceProvider)),
    );
    final send = widget.send ?? _defaultSend;
    final answer = await send(token, report, origins);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _report = report;
      _answer = answer;
      _failed = answer == null;
    });
  }

  Future<void> _copyReport() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: jsonEncode(report)));
    dialogs.showNotifier(nekoSosCopied);
  }

  List<Widget> _answerItems(NekoSosAnswer answer) {
    final emergency = answer.emergency;
    return [
      generateSection(
        title: answer.status == 'repeat' ? nekoSosRepeat : nekoSosReported,
        items: [for (final line in answer.lines) ListItem(title: Text(line))],
      ),
      if (emergency != null)
        generateSection(
          items: [
            ListItem(
              leading: const GlyphIcon(AppGlyphs.add),
              title: Text(nekoSosEmergency),
              subtitle: Text(nekoSosEmergencyHint),
              onTap: () {
                ref
                    .read(profilesActionProvider.notifier)
                    .addProfileFromLink(emergency);
              },
            ),
          ],
        ),
    ];
  }

  List<Widget> _fallbackItems(String text, {bool copy = false}) {
    return [
      generateSection(
        title: text,
        items: [
          ListItem(
            leading: const GlyphIcon(AppGlyphs.send),
            title: Text(nekoSosBot),
            trailing: const GlyphIcon(AppGlyphs.openExternal),
            onTap: () => dialogs.openUrl(nekoSosBotUrl),
          ),
          if (copy)
            ListItem(
              leading: const GlyphIcon(AppGlyphs.copy),
              title: Text(nekoSosCopy),
              onTap: _copyReport,
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final answer = _answer;
    return CommonScaffold(
      isLoading: _sending,
      title: nekoSosTitle,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.contentTopPadding,
          bottom: 32 + context.bottomInset,
        ),
        children: [
          Text(nekoSosIntro, style: AppTextStyle.subheadline.of(context)),
          const SizedBox(height: 16),
          TonalButton(
            size: TonalButtonSize.bar,
            glyph: AppGlyphs.send,
            label: nekoSosSend,
            onPressed: _sending ? null : _send,
          ),
          const SizedBox(height: 16),
          if (answer != null) ..._answerItems(answer),
          if (_failed) ..._fallbackItems(nekoSosFailed, copy: true),
          if (_noProfile) ..._fallbackItems(nekoSosNoProfile),
        ],
      ),
    );
  }
}

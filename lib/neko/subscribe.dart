import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'links.dart';
import 'view_mode.dart';

final _whitespace = RegExp(r'\s+');

/// The text itself or a word of it, as a letter or a chat message holds one.
String? nekoSubscriptionLinkIn(String? text) {
  if (text == null) return null;
  return profileUrlFromQrCodes([text, ...text.split(_whitespace)]);
}

Future<String?> _clipboardText() async {
  try {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  } on PlatformException {
    return null;
  }
}

/// With no link in the clipboard, the link form to paste or type one.
Future<void> nekoPasteSubscription(BuildContext context, WidgetRef ref) async {
  final link = nekoSubscriptionLinkIn(await _clipboardText());
  if (!context.mounted) return;
  if (link != null) {
    unawaited(
      ref.read(profilesActionProvider.notifier).addProfileFromLink(link),
    );
  } else {
    await AddProfileMenu.addByLink(context, ref);
  }
}

Future<void> showNekoNeedSubscription(BuildContext context) {
  return showSheet<void>(
    context: context,
    builder: (_) => const NekoNeedSubscriptionSheet(),
  );
}

class NekoNeedSubscriptionSheet extends ConsumerWidget {
  const NekoNeedSubscriptionSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mail = ref.watch(nekoMailProvider).value;
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      title: nekoNeedSubscription,
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.contentTopPadding,
          bottom: 20 + context.bottomInset,
        ),
        children: [
          Text(
            nekoNeedSubscriptionText,
            style: AppTextStyle.body
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          CommonPopupBox(
            targetBuilder: (open) => TonalButton(
              size: TonalButtonSize.bar,
              glyph: AppGlyphs.addCircle,
              label: nekoAddSubscription,
              onPressed: open,
            ),
            popupBuilder: (_) => CommonPopupMenu(
              items: [
                CommonPopupMenuItem(
                  glyph: AppGlyphs.cloudDownload,
                  label: appLocalizations.link,
                  onPressed: () => AddProfileMenu.addByLink(context, ref),
                ),
                CommonPopupMenuItem(
                  glyph: AppGlyphs.qrCode,
                  label: appLocalizations.qrcode,
                  onPressed: () => AddProfileMenu.scan(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TonalButton(
            size: TonalButtonSize.bar,
            glyph: AppGlyphs.send,
            label: nekoRequestTelegram,
            onPressed: () => nekoOpen(ref, Uri.parse(nekoBotAppUrl)),
          ),
          if (mail != null) ...[
            const SizedBox(height: 8),
            TonalButton(
              size: TonalButtonSize.bar,
              glyph: AppGlyphs.compose,
              label: nekoRequestMail,
              onPressed: () =>
                  nekoOpen(ref, nekoMailto(mail, nekoMailRequestSubject)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Over the subscriptions on NekoVPN's layout: paste one, or ask the bot for
/// one in Telegram or by mail. FlClash's view gets [child] alone.
class NekoSubscriptionsHeader extends ConsumerWidget {
  const NekoSubscriptionsHeader({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled || ref.watch(nekoViewProvider) == NekoView.flclash) {
      return child;
    }
    final mail = ref.watch(nekoMailProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ).copyWith(top: context.contentTopPadding),
          child: generateGroup([
            ListItem(
              leading: const GlyphIcon(AppGlyphs.paste),
              title: Text(nekoPasteFromClipboard),
              onTap: () => nekoPasteSubscription(context, ref),
            ),
            ListItem(
              leading: const GlyphIcon(AppGlyphs.send),
              title: Text(nekoAskBot),
              trailing: const GlyphIcon(AppGlyphs.openExternal),
              onTap: () => nekoOpen(ref, Uri.parse(nekoBotAppUrl)),
            ),
            if (mail != null)
              ListItem(
                leading: const GlyphIcon(AppGlyphs.compose),
                title: Text(nekoAskMail),
                trailing: const GlyphIcon(AppGlyphs.openExternal),
                onTap: () =>
                    nekoOpen(ref, nekoMailto(mail, nekoMailRequestSubject)),
              ),
          ]),
        ),
        // The list under the rows starts where they end, not under the bar.
        Expanded(child: TopInsetScope(inset: 16, child: child)),
      ],
    );
  }
}

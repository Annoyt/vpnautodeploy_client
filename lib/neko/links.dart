import 'package:fl_clash/common/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'remote_settings.dart';

typedef NekoLaunch = Future<bool> Function(Uri uri);

Future<bool> _launchOutside(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

final nekoLaunchProvider = Provider<NekoLaunch>((ref) => _launchOutside);

Future<void> nekoOpen(WidgetRef ref, Uri uri) async {
  final launch = ref.read(nekoLaunchProvider);
  var opened = false;
  try {
    opened = await launch(uri);
  } on Exception {
    opened = false;
  }
  if (!opened) {
    final target = uri.scheme == 'mailto' ? uri.path : uri.toString();
    dialogs.showBanner(nekoCannotOpen(target));
  }
}

/// `%20` for a space, as RFC 6068 asks: a `+` reaches the subject as is.
Uri nekoMailto(String address, String subject) {
  return Uri(
    scheme: 'mailto',
    path: address,
    query: 'subject=${Uri.encodeComponent(subject)}',
  );
}

final _mailbox = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? nekoMailOf(Object? raw) {
  return raw is String && _mailbox.hasMatch(raw) ? raw : null;
}

Future<String?> nekoServiceMail({
  String publicKey = nekoSettingsPublicKey,
}) async {
  try {
    return (await NekoSettingsStore.current(publicKey: publicKey))?.mail;
  } on Exception {
    return null;
  }
}

final nekoMailProvider = FutureProvider.autoDispose<String?>(
  (ref) => nekoServiceMail(),
);

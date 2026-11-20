import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

/// How often a subscription asks to be fetched again: its
/// `profile-update-interval` header, in hours (the Clash convention; the
/// NekoVPN bot sends 6). FlClash ignores the header and fetches once a day,
/// so a server change reached a loaded profile only the next day.
///
/// Null when the header is missing or is not a positive number of hours:
/// the profile keeps the interval it has. Bounded to one hour .. one week,
/// so that no subscription can make the app fetch it every few minutes.
Duration? nekoUpdateInterval(String? header) {
  final hours = double.tryParse(header?.trim() ?? '');
  if (hours == null || !hours.isFinite || hours <= 0) return null;
  final minutes = (hours * 60).round().clamp(_minMinutes, _maxMinutes);
  return Duration(minutes: minutes);
}

const _minMinutes = 60;
const _maxMinutes = 7 * 24 * 60;

/// An edit made during the download stands unless the answer changes it.
Duration nekoIntervalAfterUpdate({
  required Duration started,
  required Duration fetched,
  required Duration now,
}) => fetched == started ? now : fetched;

String nekoSubscriptionKey(String url) {
  final text = url.trim();
  final uri = text.webUri;
  if (uri == null) return text;
  final path = uri.path.replaceFirst(_trailingSlashes, '');
  return uri.replace(path: path).toString();
}

final _trailingSlashes = RegExp(r'/+$');

extension NekoSubscriptions on List<Profile> {
  Profile? nekoSubscription(String url, {int? currentId}) {
    final key = nekoSubscriptionKey(url);
    final same = where(
      (profile) =>
          profile.type == ProfileType.url &&
          nekoSubscriptionKey(profile.url) == key,
    );
    return same.where((profile) => profile.id == currentId).firstOrNull ??
        same.firstOrNull;
  }
}

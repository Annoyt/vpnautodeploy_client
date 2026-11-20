import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart';

/// Apps that stay out of the VPN by default: the services on Russia's white
/// lists. Their traffic keeps the phone's own connection, so they never see
/// the service's servers and do not break on a foreign address. The list
/// comes in the signed remote settings (`bypass_apps`) and goes into
/// «Приложения без VPN», upstream's access control in reject mode.
///
/// NekoVPN remembers what it put there. An app the user took back into the
/// VPN stays in the VPN. An app the list drops leaves the exclusions only if
/// NekoVPN added it. Access control is switched on once, the first time there
/// is something to exclude; switched off later, it stays off.
const nekoBypassFile = 'neko_bypass.json';

class NekoBypassState {
  const NekoBypassState({
    this.listed = const {},
    this.added = const {},
    this.kept = const {},
    this.switchedOn = false,
  });

  /// The list as last applied.
  final Set<String> listed;

  /// What NekoVPN put into the exclusions itself.
  final Set<String> added;

  /// What the user took back into the VPN.
  final Set<String> kept;

  /// Access control was switched on once.
  final bool switchedOn;

  Map<String, Object> toJson() => {
    'listed': listed.toList()..sort(),
    'added': added.toList()..sort(),
    'kept': kept.toList()..sort(),
    'switched_on': switchedOn,
  };

  /// What was saved; nothing remembered for junk.
  static NekoBypassState fromJson(Object? raw) {
    if (raw is! Map) return const NekoBypassState();
    Set<String> names(Object? value) {
      return value is List ? value.whereType<String>().toSet() : {};
    }

    return NekoBypassState(
      listed: names(raw['listed']),
      added: names(raw['added']),
      kept: names(raw['kept']),
      switchedOn: raw['switched_on'] == true,
    );
  }
}

typedef NekoBypassResult = ({AccessControlProps access, NekoBypassState state});

/// [access] with [list] applied over what [state] remembers. Only reject
/// mode is touched: in accept mode the user named the apps that use the VPN.
NekoBypassResult nekoMergeBypass(
  AccessControlProps access,
  List<String> list,
  NekoBypassState state,
) {
  if (access.mode != AccessControlMode.rejectSelected) {
    return (access: access, state: state);
  }
  final wanted = list.toSet();
  final excluded = access.rejectList.toSet();
  final dropped = state.added.difference(wanted).intersection(excluded);
  final toAdd = wanted.difference(state.kept).difference(excluded);
  final switchOn =
      !state.switchedOn && wanted.difference(state.kept).isNotEmpty;
  final rejectList = [
    for (final name in access.rejectList)
      if (!dropped.contains(name)) name,
    ...toAdd.toList()..sort(),
  ];
  return (
    access: access.copyWith(
      enable: switchOn || access.enable,
      rejectList: rejectList,
    ),
    state: NekoBypassState(
      listed: wanted,
      added: {
        ...state.added.intersection(wanted).difference(state.kept),
        ...toAdd,
      },
      kept: state.kept,
      switchedOn: state.switchedOn || switchOn,
    ),
  );
}

/// The user saved «Приложения без VPN» as [access], with [visible] the apps
/// that were on the screen. An app of the list that was on the screen and is
/// no longer excluded was taken back into the VPN; one excluded again is the
/// list's once more. Apps not on the screen, not installed or hidden by a
/// filter, say nothing: the screen drops them from what it saves.
NekoBypassState nekoBypassSaved(
  NekoBypassState state, {
  required AccessControlProps access,
  required Set<String> visible,
}) {
  if (access.mode != AccessControlMode.rejectSelected) return state;
  final excluded = access.rejectList.toSet();
  final ours = {...state.listed, ...state.added, ...state.kept};
  final takenBack = ours.intersection(visible).difference(excluded);
  final putBack = state.kept.intersection(excluded);
  return NekoBypassState(
    listed: state.listed,
    added: state.added.difference(takenBack),
    kept: {...state.kept.difference(putBack), ...takenBack},
    switchedOn: state.switchedOn,
  );
}

Future<File> _file() async {
  return File(join(await appPath.homeDirPath, nekoBypassFile));
}

Future<NekoBypassState> nekoReadBypassState() async {
  try {
    final file = await _file();
    if (!await file.exists()) return const NekoBypassState();
    return NekoBypassState.fromJson(jsonDecode(await file.readAsString()));
  } on Exception {
    return const NekoBypassState();
  }
}

/// Saves [state] in one step.
Future<void> nekoWriteBypassState(NekoBypassState state) async {
  final file = await _file();
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(jsonEncode(state.toJson()));
  await temp.rename(file.path);
}

/// Applies [list] to the access control [read] returns and hands the result
/// to [write] when it changed. True when it did.
Future<bool> nekoApplyBypass({
  required List<String> list,
  required AccessControlProps Function() read,
  required void Function(AccessControlProps access) write,
  Future<NekoBypassState> Function() load = nekoReadBypassState,
  Future<void> Function(NekoBypassState state) save = nekoWriteBypassState,
}) async {
  final current = read();
  final merged = nekoMergeBypass(current, list, await load());
  final changed = merged.access != current;
  if (changed) write(merged.access);
  await save(merged.state);
  return changed;
}

/// Notes what the user did on «Приложения без VPN» ([nekoBypassSaved]). The
/// screen does not wait for it, so a failure is only logged.
Future<void> nekoRecordBypassSave({
  required AccessControlProps access,
  required Set<String> visible,
  Future<NekoBypassState> Function() load = nekoReadBypassState,
  Future<void> Function(NekoBypassState state) save = nekoWriteBypassState,
}) async {
  try {
    final state = await load();
    await save(nekoBypassSaved(state, access: access, visible: visible));
  } on Exception catch (error) {
    commonPrint.log(
      'white-list apps: ${compactError(error)}',
      logLevel: LogLevel.warning,
    );
  }
}

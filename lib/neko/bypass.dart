import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart';

// The white-list services' apps stay out of the VPN (signed settings
// `bypass_apps`); NekoVPN remembers what it added and what the user took back.
const nekoBypassFile = 'neko_bypass.json';

class NekoBypassState {
  const NekoBypassState({
    this.listed = const {},
    this.added = const {},
    this.kept = const {},
    this.switchedOn = false,
  });

  final Set<String> listed;
  final Set<String> added;
  final Set<String> kept;
  final bool switchedOn;

  Map<String, Object> toJson() => {
    'listed': listed.toList()..sort(),
    'added': added.toList()..sort(),
    'kept': kept.toList()..sort(),
    'switched_on': switchedOn,
  };

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

NekoBypassState nekoBypassSaved(
  NekoBypassState state, {
  required AccessControlProps access,
  required Set<String> visible,
}) {
  if (access.mode != AccessControlMode.rejectSelected) return state;
  // The screen saves only the apps it shows, so an app missing from the
  // saved list was taken back only if it was on the screen.
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

Future<void> nekoWriteBypassState(NekoBypassState state) async {
  final file = await _file();
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(jsonEncode(state.toJson()));
  await temp.rename(file.path);
}

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

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'network_memory.dart';
import 'quota.dart';

/// What [NekoNetworkMemoryRunner] needs from the app; the manager below
/// wires it to the providers, tests to fakes.
class NekoNetworkMemoryHooks {
  const NekoNetworkMemoryHooks({
    required this.profileId,
    required this.groups,
    required this.delays,
    required this.changeProxy,
    required this.testGroups,
    required this.refreshGroups,
  });

  /// Our profile's id while the VPN runs it and memory is on; else null.
  final Future<int?> Function() profileId;
  final List<Group> Function() groups;
  final DelayMap Function() delays;
  final Future<void> Function(String group, String proxy) changeProxy;
  final Future<void> Function(List<Group> groups) testGroups;
  final Future<void> Function() refreshGroups;
}

/// On arrival in a network: the fallback groups go back to what worked
/// there, every automatic group is tested at once, and what then runs alive
/// is remembered. While the phone stays, what runs alive is remembered
/// again from time to time.
class NekoNetworkMemoryRunner {
  NekoNetworkMemoryRunner(this.hooks);

  final NekoNetworkMemoryHooks hooks;
  String? _network;
  bool _busy = false;

  String? get network => _network;

  Future<void> arrive(String? network) async {
    if (network == null || network == _network) return;
    _network = network;
    if (_busy) return;
    final profileId = await hooks.profileId();
    if (profileId == null) return;
    _busy = true;
    try {
      final remembered = await NekoNetworkMemory.of(profileId, network);
      final restore = nekoPicksToRestore(hooks.groups(), remembered);
      for (final MapEntry(key: group, value: proxy) in restore.entries) {
        await hooks.changeProxy(group, proxy);
      }
      await hooks.testGroups(nekoAutoGroups(hooks.groups()));
      await hooks.refreshGroups();
      await _remember(profileId, network);
    } finally {
      _busy = false;
    }
  }

  Future<void> rememberNow() async {
    final network = _network;
    if (network == null || _busy) return;
    final profileId = await hooks.profileId();
    if (profileId == null) return;
    await _remember(profileId, network);
  }

  Future<void> _remember(int profileId, String network) {
    final picks = nekoAlivePicks(hooks.groups(), hooks.delays());
    return NekoNetworkMemory.remember(profileId, network, picks);
  }
}

/// `ref.read` of a widget or `read` of a container.
typedef NekoRead = T Function<T>(ProviderListenable<T> provider);

/// Our profile's id while the VPN runs it and memory is on; else null.
/// Ours = the bot named its plan with the last profile download.
Future<int?> nekoOurProfileId(NekoRead read) async {
  if (!read(isStartProvider)) return null;
  final profile = read(currentProfileProvider);
  if (profile == null) return null;
  if (await NekoPlanStore.of(profile.id) == null) return null;
  if (!await NekoNetworkMemory.enabled()) return null;
  return profile.id;
}

/// The runner's hooks wired to the app's providers.
NekoNetworkMemoryHooks nekoNetworkMemoryHooks(NekoRead read) {
  return NekoNetworkMemoryHooks(
    profileId: () => nekoOurProfileId(read),
    groups: () => read(groupsProvider),
    delays: () => read(delayDataSourceProvider),
    changeProxy: (group, proxy) => read(
      proxiesActionProvider.notifier,
    ).changeProxy(groupName: group, proxyName: proxy),
    testGroups: (groups) =>
        read(proxiesActionProvider.notifier).delayTestGroups(groups),
    refreshGroups: () => read(proxiesActionProvider.notifier).updateGroups(),
  );
}

/// The network the phone is on now, by [nekoNetworkKey].
Future<String?> nekoCurrentNetwork(
  NekoRead read,
  List<ConnectivityResult> results,
  Future<List<NetworkInterface>> Function() interfaces,
) async {
  List<NetworkInterface> list;
  try {
    list = await interfaces();
  } on Exception {
    list = const [];
  }
  return nekoNetworkKey(
    results,
    ssid: read(currentSSIDProvider),
    interfaces: list,
  );
}

/// Feeds network changes to a [NekoNetworkMemoryRunner].
class NekoNetworkMemoryManager extends ConsumerStatefulWidget {
  const NekoNetworkMemoryManager({
    super.key,
    required this.child,
    this.connectivityStream,
    this.interfaces,
    this.rememberEvery = const Duration(minutes: 10),
  });

  final Widget child;

  /// Replaced in tests; the platform's by default.
  final Stream<List<ConnectivityResult>>? connectivityStream;
  final Future<List<NetworkInterface>> Function()? interfaces;
  final Duration rememberEvery;

  @override
  ConsumerState<NekoNetworkMemoryManager> createState() =>
      _NekoNetworkMemoryManagerState();
}

class _NekoNetworkMemoryManagerState
    extends ConsumerState<NekoNetworkMemoryManager> {
  late final _runner = NekoNetworkMemoryRunner(
    nekoNetworkMemoryHooks(ref.read),
  );
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final stream =
        widget.connectivityStream ?? Connectivity().onConnectivityChanged;
    _subscription = stream.listen((results) => unawaited(_changed(results)));
    _timer = Timer.periodic(widget.rememberEvery, (_) {
      if (mounted) unawaited(_runner.rememberNow());
    });
  }

  Future<void> _changed(List<ConnectivityResult> results) async {
    final network = await nekoCurrentNetwork(
      ref.read,
      results,
      widget.interfaces ?? NetworkInterface.list,
    );
    if (mounted) await _runner.arrive(network);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The Tools switch; on unless switched off.
class NekoNetworkMemoryItem extends StatefulWidget {
  const NekoNetworkMemoryItem({super.key, this.read, this.write});

  /// Replaced in tests; the memory file by default.
  final Future<bool> Function()? read;
  final Future<void> Function(bool enabled)? write;

  @override
  State<NekoNetworkMemoryItem> createState() => _NekoNetworkMemoryItemState();
}

class _NekoNetworkMemoryItemState extends State<NekoNetworkMemoryItem> {
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final enabled = await (widget.read ?? NekoNetworkMemory.enabled)();
    if (mounted) setState(() => _enabled = enabled);
  }

  Future<void> _change(bool enabled) async {
    setState(() => _enabled = enabled);
    await (widget.write ?? NekoNetworkMemory.setEnabled)(enabled);
  }

  @override
  Widget build(BuildContext context) {
    return ListItem.toggle(
      leading: const GlyphIcon(AppGlyphs.locate),
      title: Text(nekoNetworkMemoryTitle),
      subtitle: Text(nekoNetworkMemorySubtitle),
      value: _enabled,
      onChanged: (enabled) => unawaited(_change(enabled)),
    );
  }
}

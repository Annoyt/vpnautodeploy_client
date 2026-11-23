import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'netstat.dart';
import 'quota.dart';
import 'remote_settings.dart';

const _oursPath = '/neko/settings';
const _uploadPath = '/api/neko/netstat';
const _oursTimeout = Duration(seconds: 10);
const _ruTimeout = Duration(seconds: 15);
const _nativeTimeout = Duration(seconds: 10);
const _uploadTimeout = Duration(seconds: 30);

/// NekoNetstatPlugin.kt.
class NekoNetstatNative {
  const NekoNetstatNative();

  static const _channel = MethodChannel('$packageName/neko_netstat');

  Future<NekoNetstatSnapshot?> snapshot({required bool cell}) async {
    final raw = await _channel.invokeMethod<Object?>('snapshot', {
      'cell': cell,
    });
    return NekoNetstatSnapshot.fromNative(raw);
  }

  /// A Russian site outside the tunnel; null with no network under the VPN.
  Future<bool?> probeRu() => _channel.invokeMethod<bool>('probeRu');

  Future<bool> hasLocation() async {
    return await _channel.invokeMethod<bool>('hasLocation') ?? false;
  }

  /// Fine and coarse location while in use; never in the background.
  Future<bool> requestLocation() async {
    return await _channel.invokeMethod<bool>('requestLocation') ?? false;
  }
}

class NekoNetstatHooks {
  const NekoNetstatHooks({
    required this.running,
    required this.settings,
    required this.token,
    required this.subscription,
    required this.probeOurs,
    required this.snapshot,
    required this.probeRu,
    required this.cellEnabled,
    required this.post,
    required this.app,
    required this.now,
  });

  final bool Function() running;
  final Future<NekoSettings?> Function() settings;
  final Future<String?> Function() token;
  final SubscriptionInfo? Function() subscription;

  /// Null when the request would not have gone through the tunnel.
  final Future<bool?> Function(String url) probeOurs;
  final Future<NekoNetstatSnapshot?> Function(bool cell) snapshot;
  final Future<bool?> Function() probeRu;
  final Future<bool> Function() cellEnabled;
  final NekoNetstatPost post;
  final String Function() app;
  final DateTime Function() now;
}

class NekoNetstatRunner {
  NekoNetstatRunner(this.hooks);

  final NekoNetstatHooks hooks;
  bool _busy = false;

  /// Never throws: a failed check only waits for the next one.
  Future<void> check() async {
    if (_busy) return;
    _busy = true;
    try {
      await _check();
    } catch (error) {
      commonPrint.log(
        'netstat: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> _check() async {
    if (!hooks.running()) return;
    final settings = await hooks.settings();
    if (!nekoNetstatAllowed(settings)) return;
    final token = await hooks.token();
    if (token == null) return;
    final endpoint = nekoNetstatEndpoint(settings);
    final ours = await hooks.probeOurs('$endpoint$_oursPath');
    if (ours == null || !hooks.running()) return;
    final time = hooks.now();
    final ts = nekoNetstatTs(time);
    final now = time.millisecondsSinceEpoch ~/ 1000;
    final kept = await NekoNetstatStore.read();
    var state = kept;
    final kind = nekoNetstatKindDue(
      ours: ours,
      ts: ts,
      lastOk: kept.lastOk,
      lapsed: nekoNetstatLapsed(hooks.subscription(), now),
    );
    if (kind != null) {
      final cell = kind == NekoNetstatKind.drop && await hooks.cellEnabled();
      final snapshot = await hooks.snapshot(cell);
      if (snapshot != null) {
        state = state.add(
          NekoNetstatEvent.of(
            ts: ts,
            kind: kind,
            snapshot: snapshot,
            ru: await hooks.probeRu(),
            ours: ours,
          ),
        );
      }
    }
    if (!identical(state, kept)) await NekoNetstatStore.write(state);
    if (!ours || !hooks.running()) return;
    final app = hooks.app();
    if (!nekoNetstatApp(app) || !nekoNetstatUploadDue(state, now)) return;
    final sent = await nekoNetstatUpload(
      state,
      url: '$endpoint$_uploadPath',
      token: token,
      app: app,
      now: now,
      post: hooks.post,
    );
    await NekoNetstatStore.write(sent);
  }
}

Future<T> _bounded<T>(
  Duration limit,
  Future<T> Function(CancelToken cancel) send,
) async {
  final cancel = CancelToken();
  try {
    return await send(cancel).timeout(limit);
  } on TimeoutException {
    cancel.cancel();
    rethrow;
  }
}

Options _anyStatus([Map<String, String>? headers]) {
  return Options(headers: headers, validateStatus: (_) => true);
}

Future<String?> _token(ProviderReader read) async {
  final profile = read(currentProfileProvider);
  if (profile == null) return null;
  final kept = await NekoSettingsStore.current();
  return nekoNetstatToken(
    profile.url,
    planned: await NekoPlanStore.of(profile.id) != null,
    origins: {...?kept?.endpoints, ...nekoSettingsEndpoints},
  );
}

/// The app's requests, through the core's local proxy while the VPN runs
/// (FlClashHttpOverrides): never sent the other way.
NekoNetstatHooks nekoNetstatHooks(
  ProviderReader read, {
  Dio? dio,
  NekoNetstatNative native = const NekoNetstatNative(),
}) {
  final client = dio ?? request.dio;
  bool running() => read(isStartProvider) && !read(suspendProvider);
  return NekoNetstatHooks(
    running: running,
    settings: NekoSettingsStore.current,
    token: () => _token(read),
    subscription: () => read(currentProfileProvider)?.subscriptionInfo,
    probeOurs: (url) async {
      if (!running()) return null;
      try {
        await _bounded(
          _oursTimeout,
          (cancel) => client.head<void>(
            url,
            options: _anyStatus(),
            cancelToken: cancel,
          ),
        );
        return true;
      } on Exception {
        return false;
      }
    },
    snapshot: (cell) async {
      try {
        return await native.snapshot(cell: cell).timeout(_nativeTimeout);
      } on Exception {
        return null;
      }
    },
    probeRu: () async {
      try {
        return await native.probeRu().timeout(_ruTimeout);
      } on TimeoutException {
        return false;
      } on Exception {
        return null;
      }
    },
    cellEnabled: nekoReadNetstatCell,
    post: (url, headers, body) async {
      if (!running()) throw const HttpException('netstat goes by the VPN only');
      final response = await _bounded(
        _uploadTimeout,
        (cancel) => client.post<void>(
          url,
          data: body,
          options: _anyStatus(headers),
          cancelToken: cancel,
        ),
      );
      final retryAfter = response.headers['retry-after']?.firstOrNull;
      return (
        status: response.statusCode ?? 0,
        retryAfter: nekoRetryAfter(retryAfter),
      );
    },
    app: () => globalState.packageInfo.version,
    now: DateTime.now,
  );
}

class NekoNetstatManager extends ConsumerStatefulWidget {
  const NekoNetstatManager({
    super.key,
    required this.child,
    this.hooks,
    this.enabled,
    this.first = const Duration(minutes: 1),
    this.every = const Duration(minutes: 10),
  });

  final Widget child;
  final NekoNetstatHooks? hooks;
  final bool? enabled;
  final Duration first;
  final Duration every;

  @override
  ConsumerState<NekoNetstatManager> createState() => _NekoNetstatManagerState();
}

class _NekoNetstatManagerState extends ConsumerState<NekoNetstatManager> {
  late final _runner = NekoNetstatRunner(
    widget.hooks ?? nekoNetstatHooks(ref.read),
  );
  Timer? _first;
  Timer? _every;

  @override
  void initState() {
    super.initState();
    if (!(widget.enabled ?? system.isAndroid)) return;
    ref.listenManual(
      isStartProvider,
      (_, running) => _schedule(running),
      fireImmediately: true,
    );
  }

  void _schedule(bool running) {
    _cancel();
    if (!running) return;
    _first = Timer(widget.first, _check);
    _every = Timer.periodic(widget.every, (_) => _check());
  }

  void _check() {
    if (mounted) unawaited(_runner.check());
  }

  void _cancel() {
    _first?.cancel();
    _every?.cancel();
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

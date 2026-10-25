import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Upstream's release build as neko-release.yaml was last compared with it.
/// A step added, removed or renamed upstream fails here: compare the two
/// workflows, carry over what the Android build needs, then update the list.
const _upstreamBuildSteps = [
  'Setup rust',
  'Checkout',
  'Setup Android Signing',
  'Setup Go',
  'Setup Gradle',
  'Enable git long paths (Windows)',
  'Setup Flutter',
  'Setup Xcode',
  'Setup NDK',
  'Get Flutter Dependency',
  'Disable Impeller on Intel macOS',
  'Fetch CA certificates',
  'Setup',
  'Upload',
];

/// What neko-release.yaml reads from build.yaml instead of pinning it.
const _toolchain = ['FLUTTER_VERSION', 'GO_VERSION', 'NDK_VERSION'];

YamlMap _workflow(String name) {
  final file = File('.github/workflows/$name');
  return loadYaml(file.readAsStringSync()) as YamlMap;
}

List<YamlMap> _steps(YamlMap workflow, String job) {
  final jobs = workflow['jobs'] as YamlMap;
  final steps = (jobs[job] as YamlMap)['steps'] as YamlList;
  return steps.cast<YamlMap>().toList();
}

YamlMap _step(List<YamlMap> steps, String name) {
  return steps.firstWhere((step) => step['name'] == name);
}

/// Runs tool/neko/upstream_base.sh in a copy of the repository root that
/// has only a pubspec, with a `gh` that answers [tag] for upstream's latest
/// release, or fails when [tag] is null.
Future<ProcessResult> _upstreamBase(String version, String? tag) async {
  final root = await Directory.systemTemp.createTemp('neko_upstream');
  addTearDown(() => root.delete(recursive: true));
  final pubspec = File('${root.path}/pubspec.yaml');
  pubspec.writeAsStringSync('name: fl_clash\nversion: $version\n');
  final bin = Directory('${root.path}/bin')..createSync();
  final gh = File('${bin.path}/gh');
  gh.writeAsStringSync(
    '#!/usr/bin/env bash\n'
    '[ "\$*" = "api repos/chen08209/FlClash/releases/latest '
    '--jq .tag_name" ] || exit 9\n'
    '${tag == null ? 'exit 1' : 'echo $tag'}\n',
  );
  await Process.run('chmod', ['+x', gh.path]);
  final script = File('tool/neko/upstream_base.sh').absolute.path;
  return Process.run(
    'bash',
    [script],
    workingDirectory: root.path,
    environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
  );
}

void main() {
  final upstream = _workflow('build.yaml');
  final ours = _workflow('neko-release.yaml');
  final upstreamSteps = _steps(upstream, 'build');
  final ourSteps = _steps(ours, 'android');
  final ourNames = [for (final step in ourSteps) step['name']];

  test('upstream release build is the one ours was compared with', () {
    final names = [for (final step in upstreamSteps) step['name']];
    expect(names, _upstreamBuildSteps);
  });

  test('the toolchain neko-release.yaml reads is in build.yaml', () {
    final env = upstream['env'] as YamlMap;
    for (final key in _toolchain) {
      expect(env[key], isA<String>(), reason: key);
    }
    final ca = _step(upstreamSteps, 'Fetch CA certificates')['env'] as YamlMap;
    expect(ca['CA_BUNDLE'], matches(RegExp(r'^cacert-[\d-]+\.pem$')));
    expect(ca['CA_BUNDLE_SHA256'], matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('neko-release.yaml pins no toolchain of its own', () {
    final env = ours['env'] as YamlMap;
    for (final key in [..._toolchain, 'CA_BUNDLE', 'CA_BUNDLE_SHA256']) {
      expect(env.containsKey(key), isFalse, reason: key);
    }
    final read = _step(ourSteps, "Toolchain from upstream's build.yaml");
    for (final key in [..._toolchain, 'CA_BUNDLE', 'CA_BUNDLE_SHA256']) {
      expect(read['run'], contains('pin $key '), reason: key);
    }
  });

  test('the core gets the CA bundle exactly as upstream fetches it', () {
    final theirs = _step(upstreamSteps, 'Fetch CA certificates');
    final mine = _step(ourSteps, 'Fetch CA certificates');
    expect(mine['run'], theirs['run']);
    final fetch = ourNames.indexOf('Fetch CA certificates');
    expect(fetch, lessThan(ourNames.indexOf('Build')));
  });

  test('a build checks its upstream base before anything else', () {
    final check = ourNames.indexOf('Based on the latest upstream release');
    expect(check, isNonNegative);
    expect(check, lessThan(ourNames.indexOf('Setup signing')));
  });

  group('upstream_base.sh', () {
    test('our base is upstream latest release', () async {
      final result = await _upstreamBase('0.9.2-neko.1+1', 'v0.9.2');
      expect(result.exitCode, 0);
      expect('${result.stdout}'.trim(), '0.9.2 0.9.2');
    });

    test('an older upstream release is no reason to stop', () async {
      final result = await _upstreamBase('0.9.2-neko.3+1', 'v0.9.1');
      expect(result.exitCode, 0);
    });

    test('a newer upstream release, compared part by part', () async {
      expect((await _upstreamBase('0.9.2-neko.1+1', 'v0.9.3')).exitCode, 10);
      expect((await _upstreamBase('0.9.2-neko.1+1', 'v0.9.10')).exitCode, 10);
      expect((await _upstreamBase('0.9.2-neko.1+1', 'v1.0.0')).exitCode, 10);
    });

    test('no answer, or no fork version, is not "current"', () async {
      final noAnswer = await _upstreamBase('0.9.2-neko.1+1', null);
      expect(noAnswer.exitCode, isNot(anyOf(0, 10)));
      final noFork = await _upstreamBase('0.9.2+1', 'v0.9.2');
      expect(noFork.exitCode, isNot(anyOf(0, 10)));
    });
  });
}

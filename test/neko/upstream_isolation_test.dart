import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Steps that publish: a GitHub release, a Pages site, a push to another
/// repository, a post to upstream's Telegram channel. Upstream's workflows
/// run in this repository too; only their repository gate keeps a merge
/// from publishing FlClash builds and tags next to ours.
final _publishes = RegExp(
  'action-gh-release|deploy-pages|push-to-another-repository|'
  'release_telegram',
);

const _gate = "github.repository == 'chen08209/FlClash'";

String _fileName(File file) => file.uri.pathSegments.last;

List<File> _upstreamWorkflows() {
  final all = Directory('.github/workflows').listSync().whereType<File>();
  return all.where((file) => !_fileName(file).startsWith('neko-')).toList();
}

List<String> _needs(Object? needs) {
  if (needs is String) return [needs];
  if (needs is YamlList) return needs.cast<String>().toList();
  return [];
}

/// Held back: its own `if` carries the gate, or it needs a job that does.
bool _gated(YamlMap jobs, String name) {
  final job = jobs[name] as YamlMap;
  if ('${job['if'] ?? ''}'.contains(_gate)) return true;
  return _needs(job['needs']).any((need) => _gated(jobs, need));
}

bool _publishing(YamlMap job) {
  final steps = job['steps'];
  if (steps is! YamlList) return false;
  for (final step in steps.whereType<YamlMap>()) {
    final text = '${step['uses'] ?? ''} ${step['run'] ?? ''}';
    if (_publishes.hasMatch(text)) return true;
  }
  return false;
}

YamlMap _jobs(String source) {
  final doc = loadYaml(source) as YamlMap;
  return doc['jobs'] as YamlMap;
}

const _sample = '''
jobs:
  build:
    if: github.repository == 'chen08209/FlClash'
    runs-on: ubuntu-latest
    steps:
      - run: echo build
  upload:
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - uses: softprops/action-gh-release@v2
  rogue:
    runs-on: ubuntu-latest
    steps:
      - uses: softprops/action-gh-release@v2
''';

void main() {
  test('the check tells a gated publisher from an ungated one', () {
    final jobs = _jobs(_sample);
    expect(_publishing(jobs['upload'] as YamlMap), isTrue);
    expect(_gated(jobs, 'upload'), isTrue);
    expect(_gated(jobs, 'rogue'), isFalse);
  });

  test('upstream workflows are there to check', () {
    final names = _upstreamWorkflows().map(_fileName);
    expect(names, containsAll(['build.yaml', 'pages.yaml']));
  });

  for (final file in _upstreamWorkflows()) {
    final name = _fileName(file);
    test('$name publishes only from chen08209/FlClash', () {
      final jobs = _jobs(file.readAsStringSync());
      for (final job in jobs.keys.cast<String>()) {
        if (!_publishing(jobs[job] as YamlMap)) continue;
        expect(_gated(jobs, job), isTrue, reason: '$name: job $job');
      }
    });
  }
}

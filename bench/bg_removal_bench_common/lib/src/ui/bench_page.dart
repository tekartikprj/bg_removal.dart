import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';

import '../bench/bench_host.dart';
import '../bench/bench_method.dart';
import '../bench/bench_runner.dart';

/// Runs the bench at start (`--dart-define=BENCH_AUTORUN=true`).
const benchAutorun = bool.fromEnvironment('BENCH_AUTORUN');

/// Methods of an autorun, comma separated (default: all supported but
/// IS-Net).
const benchMethodsDefine = String.fromEnvironment('BENCH_METHODS');

/// Engine provider of an autorun (the app's names: CPU, XNNPACK, wasm,
/// webgpu...), empty for the app's first.
const benchProviderDefine = String.fromEnvironment('BENCH_PROVIDER');

/// Engine threads of an autorun, 0 for the default.
const benchThreadsDefine = int.fromEnvironment('BENCH_THREADS');

/// A timing pass on one photo of this size after the fixtures
/// (`BENCH_TIMING=1600x1200`), empty for none.
const benchTimingDefine = String.fromEnvironment('BENCH_TIMING');

/// The pipeline options as json (`BgRemovalOptions.fromJson`), to fine
/// tune: `BENCH_OPTIONS={"minRegion":0.005,"feather":1}`.
const benchOptionsDefine = String.fromEnvironment('BENCH_OPTIONS');

/// What an app brings to the bench: its engines and its platform side.
class BenchSetup {
  /// The engine ids this app has (`mlkit`, `modnet`, `u2netp`, `isnet`).
  final Set<String> models;

  /// The provider names for the engines, the first is the default.
  final List<String> providers;

  /// Builds the engines for a provider and a thread count (null: default).
  final Map<String, BgRemover> Function(String provider, int? threads) engines;

  /// The platform side of a run (`stamp`: the run's folder name).
  final Future<BenchHost> Function(String stamp) host;

  /// A setup.
  BenchSetup({
    required this.models,
    required this.providers,
    required this.engines,
    required this.host,
  });
}

/// The bench: every method on every fixture, scored.
class BenchPage extends StatefulWidget {
  /// The app's engines and platform side.
  final BenchSetup setup;

  /// The bench page.
  const BenchPage({super.key, required this.setup});

  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<BenchPage> {
  final _selected = <String>{};
  late String _provider;
  int? _threads = benchThreadsDefine == 0 ? null : benchThreadsDefine;
  var _running = false;
  var _status = '';
  BenchReport? _report;
  final _cells = <BenchCell>[];
  List<BenchFixture> _fixtures = [];

  BenchSetup get _setup => widget.setup;

  bool _supported(BenchMethod m) => m.models.every(_setup.models.contains);

  @override
  void initState() {
    super.initState();
    _provider = _setup.providers.contains(benchProviderDefine)
        ? benchProviderDefine
        : _setup.providers.first;
    final wanted = benchMethodsDefine.isEmpty
        ? null
        : benchMethodsDefine.split(',').toSet();
    for (final m in benchMethods) {
      if (!_supported(m)) continue;
      // IS-Net (179 MB) only when asked.
      if (wanted == null
          ? m.models.contains('isnet')
          : !wanted.contains(m.id)) {
        continue;
      }
      _selected.add(m.id);
    }
    unawaited(_init());
  }

  Future<void> _init() async {
    final fixtures = await benchLoadFixtures(rootBundle);
    setState(() => _fixtures = fixtures);
    if (benchAutorun) {
      await _run();
    }
  }

  (int, int)? _timingSize() {
    final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(benchTimingDefine);
    return match == null
        ? null
        : (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _cells.clear();
      _report = null;
    });
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(RegExp('[-:]'), '')
        .replaceAll('T', '_');
    final host = await _setup.host(stamp);
    try {
      final options = benchOptionsDefine.isEmpty
          ? const BgRemovalOptions()
          : BgRemovalOptions.fromJson(
              jsonDecode(benchOptionsDefine) as Map<String, Object?>,
            );
      final runner = BenchRunner(
        engines: _setup.engines(_provider, _threads),
        methods: [
          for (final m in benchMethods)
            if (_selected.contains(m.id)) m,
        ],
        fixtures: _fixtures,
        bundle: rootBundle,
        host: host,
        options: options,
        timingSize: _timingSize(),
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
        onCell: (cell) {
          if (mounted) setState(() => _cells.add(cell));
        },
      );
      final report = await runner.run();
      await host.publish(report.toMarkdown());
      if (mounted) setState(() => _report = report);
    } catch (e, st) {
      await host.publish('error: $e\n$st');
      if (mounted) setState(() => _status = 'error: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = [
      'original',
      for (final m in benchMethods)
        if (_selected.contains(m.id)) m.id,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Background removal bench')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in benchMethods)
                FilterChip(
                  label: Text(m.id),
                  selected: _selected.contains(m.id),
                  onSelected: _running || !_supported(m)
                      ? null
                      : (on) => setState(
                          () =>
                              on ? _selected.add(m.id) : _selected.remove(m.id),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: _provider,
                onChanged: _running
                    ? null
                    : (p) => setState(() => _provider = p!),
                items: [
                  for (final p in _setup.providers)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
              ),
              DropdownButton<int?>(
                value: _threads,
                onChanged: _running
                    ? null
                    : (t) => setState(() => _threads = t),
                items: [
                  for (final t in {null, 1, 2, 4, 8, _threads})
                    DropdownMenuItem(
                      value: t,
                      child: Text(
                        t == null ? 'threads: default' : '$t threads',
                      ),
                    ),
                ],
              ),
              FilledButton(
                onPressed: _running || _fixtures.isEmpty ? null : _run,
                child: Text(_running ? 'Running...' : 'Run'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_status, style: Theme.of(context).textTheme.bodySmall),
          if (_report != null) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                _report!.toMarkdown(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (final fixture in _fixtures)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final method in methods)
                    _CellView(method: method, cell: _cell(method, fixture.id)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  BenchCell? _cell(String method, String fixture) {
    for (final c in _cells) {
      if (c.method == method && c.fixture == fixture) return c;
    }
    return null;
  }
}

class _CellView extends StatelessWidget {
  final String method;
  final BenchCell? cell;

  const _CellView({required this.method, required this.cell});

  @override
  Widget build(BuildContext context) {
    final cell = this.cell;
    final score = cell?.score;
    final small = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 160,
            child: cell == null
                ? const SizedBox(width: 100)
                : BgRgbaImageView(
                    cell.thumbnail,
                    key: ValueKey(cell),
                    checkerboard: false,
                  ),
          ),
          Text(
            cell?.method == 'original' ? cell!.fixture : method,
            style: small,
          ),
          if (score != null)
            Text(
              'iou ${score.iou.toStringAsFixed(2)}'
              ' bag ${score.bag?.toStringAsFixed(2) ?? '-'}'
              ' ${cell!.time.inMilliseconds} ms',
              style: small,
            ),
        ],
      ),
    );
  }
}

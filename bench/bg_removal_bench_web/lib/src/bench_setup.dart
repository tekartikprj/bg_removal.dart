import 'dart:js_interop';
import 'dart:typed_data';

import 'package:bg_removal_bench_common/bg_removal_bench_common.dart';
import 'package:tekartik_bg_removal_web/bg_removal_web.dart';
import 'package:web/web.dart' as web;

/// Where the report goes after a run (`BENCH_REPORT_URL`, set by
/// `tool/bench.dart`): POSTed as markdown.
const benchReportUrl = String.fromEnvironment('BENCH_REPORT_URL');

/// The models' base URL (`BENCH_MODELS_URL`), empty for their own hosts.
const benchModelsUrl = String.fromEnvironment('BENCH_MODELS_URL');

/// The bench in the browser: the ONNX models on onnxruntime-web.
BenchSetup webBenchSetup() => BenchSetup(
  models: {'modnet', 'u2netp', 'isnet'},
  providers: ['wasm', 'webgpu'],
  engines: (provider, threads) {
    final loader = BgWebModelLoader(
      baseUrl: benchModelsUrl.isEmpty ? null : benchModelsUrl,
    );
    BgOnnxWebRemover onnx({BgOnnxModel? person, BgOnnxModel? salient}) =>
        BgOnnxWebRemover(
          person: person,
          salient: salient,
          loader: loader,
          executionProviders: [if (provider == 'webgpu') 'webgpu', 'wasm'],
          numThreads: threads,
        );
    return {
      'modnet': onnx(person: bgOnnxModnetFp16),
      'u2netp': onnx(salient: bgOnnxU2netp),
      'isnet': onnx(salient: bgOnnxIsnet),
    };
  },
  host: (stamp) async => BenchWebHost(),
);

/// The bench in a browser: no files; the report is printed, and POSTed to
/// [benchReportUrl] when set.
class BenchWebHost implements BenchHost {
  @override
  String get platform {
    final navigator = web.window.navigator;
    return 'web, ${navigator.userAgent}, '
        '${navigator.hardwareConcurrency} cpus, '
        'cross-origin isolated: ${web.window.crossOriginIsolated}';
  }

  @override
  int? get maxRssMb => null;

  @override
  String? get outDir => null;

  @override
  Future<String?> tempFile(String name, Uint8List bytes) async => null;

  @override
  Future<void> save(String path, Uint8List bytes) async {}

  @override
  Future<void> publish(String markdown) async {
    for (final line in markdown.split('\n')) {
      // ignore: avoid_print
      print('BENCH| $line');
    }
    if (benchReportUrl.isNotEmpty) {
      await web.window
          .fetch(
            benchReportUrl.toJS,
            web.RequestInit(method: 'POST', body: markdown.toJS),
          )
          .toDart;
    }
  }
}

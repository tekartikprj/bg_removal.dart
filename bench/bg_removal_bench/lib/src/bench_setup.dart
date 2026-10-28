import 'dart:io';
import 'dart:typed_data';

import 'package:bg_removal_bench_common/bg_removal_bench_common.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tekartik_bg_removal_mlkit/bg_removal_mlkit.dart';
import 'package:tekartik_bg_removal_onnx/bg_removal_onnx.dart';

/// Exits after an autorun, desktop only (`BENCH_EXIT=true`).
const benchExit = bool.fromEnvironment('BENCH_EXIT');

/// Tries ML Kit again after it crashed the app (`BENCH_MLKIT_RETRY=true`).
const benchMlKitRetry = bool.fromEnvironment('BENCH_MLKIT_RETRY');

/// The bench on Android (ML Kit + ONNX) and Linux (ONNX).
///
/// The ONNX models are cached in `<support>/models`; on Linux,
/// `BG_REMOVAL_MODELS=<dir>` uses local files instead.
BenchSetup appBenchSetup() => BenchSetup(
  models: {if (Platform.isAndroid) 'mlkit', 'modnet', 'u2netp', 'isnet'},
  providers: ['CPU', 'XNNPACK', if (Platform.isAndroid) 'NNAPI'],
  engines: (provider, threads) {
    final support = _support!;
    final cache = BgOnnxModelCache(
      dir: join(support, 'models'),
      localDirs: [?Platform.environment['BG_REMOVAL_MODELS']],
    );
    BgOnnxRemover onnx({BgOnnxModel? person, BgOnnxModel? salient}) =>
        BgOnnxRemover(
          person: person,
          salient: salient,
          cache: cache,
          providers: [OrtProvider.values.byName(provider)],
          threads: threads,
        );
    return {
      'mlkit': BgMlKitRemover(
        guardDir: support,
        retryAfterCrash: benchMlKitRetry,
      ),
      'modnet': onnx(person: bgOnnxModnetFp16),
      'u2netp': onnx(salient: bgOnnxU2netp),
      'isnet': onnx(salient: bgOnnxIsnet),
    };
  },
  host: (stamp) async {
    final support = _support = (await getApplicationSupportDirectory()).path;
    return BenchIoHost(
      outDir: join(support, 'bench', stamp),
      tmpDir: join((await getTemporaryDirectory()).path, 'bench'),
    );
  },
);

// Set by the host, before the engines are built.
String? _support;

/// The bench's files on Android and Linux: masks and report in [outDir],
/// the report printed as `BENCH|` lines (logcat, stdout) for
/// `tool/bench.dart`.
class BenchIoHost implements BenchHost {
  @override
  final String outDir;

  /// Temporary files (ML Kit reads a file).
  final String tmpDir;

  /// A host.
  BenchIoHost({required this.outDir, required this.tmpDir});

  @override
  String get platform =>
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}, '
      '${Platform.numberOfProcessors} cpus';

  @override
  int? get maxRssMb => ProcessInfo.maxRss ~/ (1024 * 1024);

  @override
  Future<String?> tempFile(String name, Uint8List bytes) async {
    final file = File(join(tmpDir, name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  @override
  Future<void> save(String path, Uint8List bytes) async {
    final file = File(join(outDir, path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> publish(String markdown) async {
    // Greppable in `flutter run`, stdout and logcat.
    for (final line in markdown.split('\n')) {
      // ignore: avoid_print
      print('BENCH| $line');
    }
    if (!markdown.startsWith('error: ')) {
      // ignore: avoid_print
      print('BENCH| out: $outDir');
    }
    if (benchExit && !Platform.isAndroid) {
      exit(0);
    }
  }
}

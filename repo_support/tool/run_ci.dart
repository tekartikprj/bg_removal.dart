import 'package:dev_build/package.dart';
import 'package:path/path.dart';

/// Every package and app of the repository: format, analyze, test.
Future<void> main() async {
  for (final dir in [
    'packages/bg_removal',
    'packages/bg_removal_flutter',
    'packages/bg_removal_mlkit',
    'packages/bg_removal_onnx',
    'packages/bg_removal_web',
    'bench/bg_removal_bench_common',
    // The apps resolve their own dependencies (not workspace members).
    'example/bg_removal_example',
    'bench/bg_removal_bench',
    'bench/bg_removal_bench_web',
  ]) {
    await packageRunCi(join('..', dir));
  }
}

/// Shared by the picture background removal apps: the bench (runner,
/// report, fixtures, page). No engine here: each app brings its own
/// through [BenchSetup].
library;

export 'src/bench/bench_host.dart';
export 'src/bench/bench_method.dart';
export 'src/bench/bench_runner.dart';
export 'src/bench/thumbnail.dart';
export 'src/ui/bench_page.dart';

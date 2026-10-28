import 'package:bg_removal_bench_common/bg_removal_bench_common.dart';
import 'package:material_ui/material_ui.dart';

import 'src/bench_setup.dart';

/// The bench: the engines on the fixtures, scored against the reference
/// masks.
///
/// Autorun from the command line:
/// `flutter run -t lib/main_bench.dart --dart-define=BENCH_AUTORUN=true`
/// (see the README for the other defines).
void main() {
  runApp(
    MaterialApp(
      title: 'Background removal bench',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: BenchPage(setup: appBenchSetup()),
    ),
  );
}

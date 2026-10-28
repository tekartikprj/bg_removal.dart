import 'package:bg_removal_bench_common/bg_removal_bench_common.dart';
import 'package:flutter/material.dart';

import 'src/bench_setup.dart';

/// The bench in the browser: the web engine on the fixtures, scored against
/// the reference masks (`dart run tool/bench.dart` runs it in headless
/// Chrome).
void main() {
  runApp(
    MaterialApp(
      title: 'Background removal bench (web)',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: BenchPage(setup: webBenchSetup()),
    ),
  );
}

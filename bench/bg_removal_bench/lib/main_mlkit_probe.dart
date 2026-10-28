import 'package:flutter/material.dart';

import 'src/probe/mlkit_probe_page.dart';

/// Tries ML Kit Subject Segmentation with several inputs and options, to
/// find a way that does not crash (run it with `tool/mlkit_probe.dart`).
void main() {
  runApp(
    MaterialApp(
      title: 'ML Kit probe',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const MlKitProbePage(),
    ),
  );
}

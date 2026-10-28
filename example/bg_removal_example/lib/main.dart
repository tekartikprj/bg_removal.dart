import 'dart:async';

import 'package:bg_removal_example_common/bg_removal_example_common.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';
import 'package:tekartik_bg_removal_mlkit/bg_removal_mlkit.dart';
import 'package:tekartik_bg_removal_onnx/bg_removal_onnx.dart';

/// Opens the sample photo at start, without system bars
/// (`--dart-define=EXAMPLE_SAMPLE=true`): `tool/screenshot.dart`.
const exampleSample = bool.fromEnvironment('EXAMPLE_SAMPLE');

/// Takes or picks a photo, removes its background (the person and what they
/// carry stay), shows both, and saves the cut-out.
void main() {
  if (exampleSample) {
    // Screenshots: no notification icons.
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive));
  }
  runApp(
    MaterialApp(
      title: 'Background removal',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: BgRemovalExamplePage(
        // ML Kit where Google Play services exist, MODNet + u2netp on ONNX
        // Runtime otherwise (or after ML Kit crashed the app).
        remover: BgRemoverFallback([BgMlKitRemover(), BgOnnxRemover()]),
        openSample: exampleSample,
        onDone: (result, time) {
          // For tool/screenshot.dart.
          // ignore: avoid_print
          print('EXAMPLE| done ${result.engine} ${time.inMilliseconds} ms');
        },
      ),
    ),
  );
}

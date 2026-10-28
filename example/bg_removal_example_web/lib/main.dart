import 'dart:js_interop';

import 'package:bg_removal_example_common/bg_removal_example_common.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tekartik_bg_removal_web/bg_removal_web.dart';
import 'package:web/web.dart' as web;

/// Opens the sample photo at start (`--dart-define=EXAMPLE_SAMPLE=true`):
/// `tool/screenshot.dart`.
const exampleSample = bool.fromEnvironment('EXAMPLE_SAMPLE');

/// Where to POST once the cut-out is shown (`EXAMPLE_DONE_URL`, set by
/// `tool/screenshot.dart`).
const exampleDoneUrl = String.fromEnvironment('EXAMPLE_DONE_URL');

/// Opens a photo, removes its background in the browser (the person and
/// what they carry stay), shows both, and downloads the cut-out.
void main() {
  runApp(
    MaterialApp(
      title: 'Background removal',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: BgRemovalExamplePage(
        // MODNet + u2netp on onnxruntime-web (wasm), models fetched once and
        // kept in the browser.
        remover: BgOnnxWebRemover(),
        camera: false,
        openSample: exampleSample,
        onDone: (result, time) {
          if (exampleDoneUrl.isNotEmpty) {
            web.window.fetch(
              exampleDoneUrl.toJS,
              web.RequestInit(
                method: 'POST',
                body: '${result.engine} ${time.inMilliseconds} ms'.toJS,
              ),
            );
          }
        },
      ),
    ),
  );
}

---
name: tekartik-bg-removal-web-setup
description: >-
  Use when removing photo backgrounds in a browser with
  package:tekartik_bg_removal_web (BgOnnxWebRemover, BgWebModelLoader,
  bgOrtWebLoad, bgOrtWebWasmScriptUrl, bgOrtWebAllScriptUrl,
  bgOrtWebVersion): MODNet and u2netp (or IS-Net) on onnxruntime-web
  through js interop, in a Flutter web app or a pure Dart web page. Covers
  loading onnxruntime-web (no index.html change), the wasm and WebGPU
  providers, wasm threads and cross-origin isolation (COOP and COEP
  headers), where the models come from (CORS, Hugging Face, self hosting),
  the sha256 check and the browser cache, dart2js and dart2wasm, and the
  measured speed.
---

# tekartik_bg_removal_web setup

`BgOnnxWebRemover` is the ONNX engine of `tekartik_bg_removal_onnx` for the
browser: same models, same masks, same scores (MODNet + u2netp: IoU 0.87 on
the fixtures). It loads onnxruntime-web from jsdelivr, fetches the models
once (checked by size and sha256, kept in the Cache API), and runs them on
wasm (or WebGPU). Web only (it imports `package:web` and `dart:js_interop`).

```dart
import 'package:tekartik_bg_removal/bg_removal.dart';
import 'package:tekartik_bg_removal_web/bg_removal_web.dart';

Future<BgRemovalResult> cutOut(BgRgbaImage image) async {
  final remover = BgOnnxWebRemover();
  await remover.prepare(onStatus: print); // script + 18 MB of models, once
  return bgRemoveBackground(remover, BgPhoto(image), run: bgRunInIsolate);
}
```

## Guidelines

### onnxruntime-web

* Nothing to add to `index.html`: `prepare` injects the script
  (`bgOrtWebWasmScriptUrl`, onnxruntime-web `bgOrtWebVersion` 1.30.0, 14 MB
  of wasm). A page that already loads `ort` keeps its own.
* `executionProviders: ['webgpu', 'wasm']` tries WebGPU first; it needs the
  full build (`bgOrtWebAllScriptUrl`, 28 MB of wasm), chosen by default
  when `webgpu` is in the list. Only one onnxruntime-web per page: the
  first engine to prepare decides the script.
* wasm threads need a cross-origin isolated page. Serve it with
  `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: credentialless` (jsdelivr and Hugging Face
  send what these need). Without them onnxruntime-web runs one thread.
  `numThreads` sets the count (before the first session), null keeps
  onnxruntime-web's default (half the cores, 4 at most).
* `flutter run -d chrome` is not cross-origin isolated: one thread. Measure
  with a server that sends the headers (the repository's
  `bench/bg_removal_bench_web/tool/bench.dart` does, in headless Chrome).

### Models

* By default u2netp and IS-Net come from a Hugging Face copy of the rembg
  files (`BgOnnxModel.webUrl`: same sha256), MODNet from `Xenova/modnet`:
  GitHub release files (the rembg originals) send no CORS header, a page
  cannot fetch them.
* For production, host the files with the app:
  `BgOnnxWebRemover(loader: BgWebModelLoader(baseUrl: '/models/'))` fetches
  `/models/<fileName>` (`modnet_fp16.onnx`, `u2netp.onnx`,
  `isnet-general-use.onnx`). Serve them with a long cache.
* Each file is checked by size and sha256 (WebCrypto) before use and kept
  in the Cache API (`bgWebModelCacheName`): the second visit downloads
  nothing. The Cache API needs https or localhost; elsewhere every visit
  downloads.

### Speed

* The pipeline steps run on the page's thread (no isolates on the web;
  `bgRunInIsolate` runs inline): show a progress indicator, the page does
  not repaint during a removal.
* Measured in Chrome 155 on an i9 desktop, cross-origin isolated, one
  1600x1200 photo: MODNet + u2netp 0.76 s (native Linux: 0.59 s); PNG of
  the cut-out 0.75 s, WebP 2.8 s (dart2js). dart2wasm: 0.79 s, PNG 1.3 s,
  WebP 2.2 s: no gain overall. Phones are several times slower: prefer a
  smaller output (`maxOutputSize`) before encoding.
* IS-Net (179 MB) is too big for most pages; keep it for desktops.

## Examples

### Your own hosting, WebGPU first

```dart
import 'package:tekartik_bg_removal_web/bg_removal_web.dart';

final remover = BgOnnxWebRemover(
  loader: const BgWebModelLoader(baseUrl: '/models/'),
  executionProviders: ['webgpu', 'wasm'],
);
```

### Is a download coming?

```dart
import 'package:tekartik_bg_removal_web/bg_removal_web.dart';

Future<bool> needsDownload(BgOnnxWebRemover remover) async {
  for (final model in [?remover.person, ?remover.salient]) {
    if (!await remover.loader.isCached(model)) return true;
  }
  return false;
}
```

### Headers (Firebase Hosting)

```json
{
  "hosting": {
    "headers": [
      {
        "source": "**",
        "headers": [
          {"key": "Cross-Origin-Opener-Policy", "value": "same-origin"},
          {"key": "Cross-Origin-Embedder-Policy", "value": "credentialless"}
        ]
      }
    ]
  }
}
```

## Common mistakes

* `StateError: 403 for https://github.com/...` or a CORS error: a model
  URL without CORS; use `webUrl` (the default) or your own hosting.
* One thread, slow: the page is not cross-origin isolated
  (`window.crossOriginIsolated` is false).
* WebGPU asked but wasm used: the wasm-only script was loaded first by
  another engine of the page.
* `Unsupported operation: RawReceivePort` in a dart2wasm build: an
  `Isolate.run` that does not test the web with `dart.library.js_interop`
  (`bgRunInIsolate` does).

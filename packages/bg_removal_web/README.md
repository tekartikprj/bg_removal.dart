# tekartik_bg_removal_web

The web engine of `tekartik_bg_removal`: MODNet and u2netp (or IS-Net) on
onnxruntime-web, through `dart:js_interop`. The same models, masks and
scores as `tekartik_bg_removal_onnx` (MODNet + u2netp: mean IoU 0.87 on the
fixtures), 0.76 s for a 1600x1200 photo in desktop Chrome. Web only.

## Setup

```yaml
dependencies:
  tekartik_bg_removal_web:
    git:
      url: https://github.com/tekartikprj/bg_removal.dart
      path: packages/bg_removal_web
```

- Nothing to add to `index.html`: the engine loads onnxruntime-web
  (`bgOrtWebVersion`, from jsdelivr) on `prepare`.
- For wasm threads, serve the page cross-origin isolated:
  `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: credentialless`. Without them it runs on
  one thread.
- The models are fetched once (Hugging Face by default: GitHub release files
  have no CORS), checked by sha256 and kept in the browser's Cache API. Host
  them with your app for production: `BgWebModelLoader(baseUrl: '/models/')`.

## Usage

```dart
import 'dart:typed_data';

import 'package:tekartik_bg_removal/bg_removal.dart';
import 'package:tekartik_bg_removal_web/bg_removal_web.dart';

Future<Uint8List> cutOut(BgRgbaImage image) async {
  final remover = BgOnnxWebRemover(
    // executionProviders: ['webgpu', 'wasm'], // WebGPU when there is one
  );
  await remover.prepare(onStatus: print);
  final result = await bgRemoveBackground(remover, BgPhoto(image));
  return result.toPng();
}
```

In Flutter, use it with `tekartik_bg_removal_flutter`
(`bgRemoveBackgroundFromBytes`). The pipeline steps run on the page's thread
(no isolates on the web): show a progress indicator.

## Agent skills

`skills/tekartik-bg-removal-web-setup` (onnxruntime-web, providers,
headers, models, speed), per https://dart.dev/ai/package-skills.

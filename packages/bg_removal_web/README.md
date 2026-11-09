# tekartik_bg_removal_web

The web engine of `tekartik_bg_removal`: MODNet and u2netp (or IS-Net) on
onnxruntime-web, through `dart:js_interop`. The same models, masks and
scores as `tekartik_bg_removal_onnx` (MODNet + u2netp: mean IoU 0.87 on the
fixtures), 0.76 s for a 1600x1200 photo in desktop Chrome. Web only
(dart2js and dart2wasm, in a Flutter web app or a plain Dart web page).

Try it: <https://bg_removal.surge.sh/>.

## Getting started

Not on pub.dev, add it as a git dependency:

```yaml
dependencies:
  tekartik_bg_removal_web:
    git:
      url: https://github.com/tekartikprj/bg_removal.dart
      path: packages/bg_removal_web
```

```dart
import 'dart:typed_data';

import 'package:tekartik_bg_removal/bg_removal.dart';
import 'package:tekartik_bg_removal_web/bg_removal_web.dart';

Future<Uint8List> cutOut(BgRgbaImage image) async {
  final remover = BgOnnxWebRemover(
    // executionProviders: ['webgpu', 'wasm'], // WebGPU when there is one
  );
  await remover.prepare(onStatus: print); // script + 18 MB of models, once
  final result = await bgRemoveBackground(remover, BgPhoto(image));
  return result.toPng();
}
```

In Flutter, use it with `tekartik_bg_removal_flutter`
(`bgRemoveBackgroundFromBytes`). The pipeline steps run on the page's thread
(no isolates on the web): show a progress indicator.

## What the page needs

- Nothing in `index.html`: the engine loads onnxruntime-web
  (`bgOrtWebVersion`, from jsdelivr) on `prepare`. If that fails (offline),
  the next `prepare` tries again.
- For wasm threads, serve the page cross-origin isolated:
  `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: credentialless`. Without them it runs on
  one thread.
- The models are fetched once (Hugging Face by default: GitHub release files
  have no CORS), checked by size and sha256 and kept in the browser's Cache
  API. Host them with your app for production:
  `BgWebModelLoader(baseUrl: '/models/')`.
- https or localhost to keep the models: on a plain http page (a phone on
  the LAN) there is no Cache API, so each visit downloads them, and the
  sha256 is computed in Dart (slower than WebCrypto).

## Common mistakes

- `StateError: 403 for https://github.com/...` or a CORS error: a model
  URL without CORS; use `webUrl` (the default) or your own hosting.
- One thread, slow: the page is not cross-origin isolated
  (`window.crossOriginIsolated` is false); `flutter run -d chrome` is not.
- WebGPU asked but wasm used: the wasm-only script was loaded first by
  another engine of the page (one onnxruntime-web per page).

## Agent skills

`skills/tekartik-bg-removal-web-setup` (onnxruntime-web, providers,
headers, models, speed), per https://dart.dev/ai/package-skills.

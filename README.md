# bg_removal.dart

Background removal for Dart and Flutter that keeps a person **and what they
carry**: a bag, an umbrella, a phone. On the device, no server: ML Kit
Subject Segmentation on Android, ONNX models (MODNet + u2netp) on Android,
Linux and the web.

**Try it in your browser: <https://bg_removal.surge.sh/>** (the web example:
nothing leaves the browser; the 18 MB of models are downloaded once).

| Android (ML Kit, 0.9 s) | [Web](https://bg_removal.surge.sh/) (onnxruntime-web, 1.1 s) |
|---|---|
| <img src="doc/screenshots/example.png" alt="The Android example: the sample photo with and without its background" width="300"> | <img src="doc/screenshots/example_web.png" alt="The web example: the sample photo with and without its background" width="520"> |

*The examples: the sample photo, and the same without its background. On
Android ML Kit (Pixel 7a); in Chrome MODNet + u2netp, which keep a bit of the
wall touching her hair. Photo: John Benson, CC BY 2.0.*

## Packages

| Package | What | Platforms |
|---|---|---|
| [`tekartik_bg_removal`](packages/bg_removal) | pure Dart: images and masks, the engine interface, the pipeline and its options, PNG and WebP encoding | everywhere |
| [`tekartik_bg_removal_flutter`](packages/bg_removal_flutter) | photos from a file, bytes or `ui.Image`, the removal in an isolate, a cut-out view | Flutter |
| [`tekartik_bg_removal_mlkit`](packages/bg_removal_mlkit) | ML Kit Subject Segmentation (Google Play services), with a crash guard | Android |
| [`tekartik_bg_removal_onnx`](packages/bg_removal_onnx) | MODNet + u2netp (or IS-Net) on ONNX Runtime, models downloaded once | Android, Linux |
| [`tekartik_bg_removal_web`](packages/bg_removal_web) | the same models on onnxruntime-web (wasm or WebGPU) | web |

An app takes the engines of its platforms only: ML Kit never reaches a web
build, onnxruntime never reaches an app that only wants ML Kit.

Each package has a README and agent skills (`skills/`, per
[package skills](https://dart.dev/ai/package-skills)): how to use it, and
for Android what the app's project needs.

## Quick start (Flutter, Android)

```yaml
dependencies:
  tekartik_bg_removal_flutter:
    git:
      url: https://github.com/tekartikprj/bg_removal.dart
      path: packages/bg_removal_flutter
  tekartik_bg_removal_mlkit:
    git:
      url: https://github.com/tekartikprj/bg_removal.dart
      path: packages/bg_removal_mlkit
  tekartik_bg_removal_onnx:
    git:
      url: https://github.com/tekartikprj/bg_removal.dart
      path: packages/bg_removal_onnx
```

```dart
import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';
import 'package:tekartik_bg_removal_mlkit/bg_removal_mlkit.dart';
import 'package:tekartik_bg_removal_onnx/bg_removal_onnx.dart';

// ML Kit where Google Play services exist, MODNet + u2netp otherwise.
final remover = BgRemoverFallback([BgMlKitRemover(), BgOnnxRemover()]);

Future<void> cutOut(String path) async {
  await remover.prepare(onStatus: print); // at start: downloads, once
  final result = await bgRemoveBackgroundFromFile(
    remover,
    path,
    options: const BgRemovalOptions(crop: true, maxOutputSize: 1024),
  );
  // result.cutout (RGBA), BgRgbaImageView(result.cutout), result.toWebp()...
}
```

The photo can be a file, encoded bytes (`bgRemoveBackgroundFromBytes`) or
image data (`bgRemoveBackgroundFromImage`). `BgRemovalOptions` fine tunes
the result (what to keep, how far a carried thing can be, edge levels,
specks, holes, feather, working size, crop, output size); the defaults are
the measured ones.

The Android project needs a manifest entry (ML Kit's model) and R8 rules
(release builds): see `example/bg_removal_example/android` and the skill
`tekartik-bg-removal-mlkit-android-setup`.

## Measured

7 photos with hand-made reference masks; "bags kept": mean alpha of at least
0.8 inside a box drawn inside the bag.

| Engine | Where | Mean IoU | Bags kept | One 1600x1200 photo |
|---|---|---|---|---|
| ML Kit, foreground mask | Pixel 7a, Android 17 | **0.97** | **7/7** | 0.93 s |
| MODNet + u2netp | Pixel 7a, CPU | 0.87 | 6/7 | 1.8 s |
| MODNet + u2netp | Linux, i9-12900K | 0.87 | 6/7 | 0.59 s |
| MODNet + u2netp | Chrome, wasm, same i9 | 0.87 | 6/7 | 0.76 s |
| MODNet + IS-Net | Linux | 0.88 | 7/7 | 1.3 s |

Encoding a 1600x1200 cut-out in pure Dart on Linux: PNG 0.3 s (2.3 MB), WebP
q80 1.0 s (170 KB).

## Repository

- `packages/`: the packages (a pub workspace with the two shared packages,
  `example/bg_removal_example_common` and `bench/bg_removal_bench_common`,
  and `repo_support`).
- `example/`: the examples, `bg_removal_example` (Android: camera,
  gallery, sample, download) and `bg_removal_example_web` (the browser:
  open a photo, sample, download). They never depend on each other and
  share their page through `bg_removal_example_common` (no engine).
- `bench/`: the benches that produced the numbers above, on Android and Linux
  (`bg_removal_bench`) and in the browser (`bg_removal_bench_web`). The apps
  resolve their own dependencies (not workspace members), so that one
  platform's never hold back another's.
- `repo_support`: the CI (`dart run tool/run_ci.dart`).

```sh
dart pub get                      # the workspace
cd repo_support && dart run tool/run_ci.dart
```

## Models and licences

The code is under the BSD 2-Clause licence. The models are downloaded at run
time, not stored here: MODNet (Apache 2.0, `Xenova/modnet` on Hugging Face),
u2netp and IS-Net (Apache 2.0, from rembg). The bench photos come from
Wikimedia Commons under their own licences (CC BY, CC BY-SA, public domain),
listed in `bench/bg_removal_bench_common/assets/fixtures/ATTRIBUTION.md`.

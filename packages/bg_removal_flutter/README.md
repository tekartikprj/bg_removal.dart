# tekartik_bg_removal_flutter

Background removal in a Flutter app: a photo from a file, encoded bytes, a
`ui.Image` or raw pixels in, a cut-out out (the person and what they carry),
with the heavy steps in an isolate, and a view that shows the cut-out over a
checkerboard. Exports `tekartik_bg_removal`.

Try the web example: <https://bg_removal.surge.sh/>.

## Getting started

This package does not segment by itself: add the engines of your platforms.

| Platform | Engine | Package | The app needs |
|---|---|---|---|
| Android | `BgRemoverFallback([BgMlKitRemover(), BgOnnxRemover()])` | `tekartik_bg_removal_mlkit` + `tekartik_bg_removal_onnx` | a manifest entry, `INTERNET` and R8 rules (see their READMEs) |
| Linux | `BgOnnxRemover()` | `tekartik_bg_removal_onnx` | network at the first build (flutter_onnxruntime downloads ONNX Runtime) |
| Web | `BgOnnxWebRemover()` | `tekartik_bg_removal_web` | nothing; COOP/COEP headers for wasm threads |

The packages are not on pub.dev: add them as git dependencies (Android
here).

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

Prepare the engine once at start (it downloads models or waits for Play
services), then remove backgrounds:

```dart
import 'package:flutter/widgets.dart';
import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';
import 'package:tekartik_bg_removal_mlkit/bg_removal_mlkit.dart';
import 'package:tekartik_bg_removal_onnx/bg_removal_onnx.dart';

final remover = BgRemoverFallback([BgMlKitRemover(), BgOnnxRemover()]);

Future<void> prepareEngine() =>
    remover.prepare(onStatus: print); // at start: model download, once

Future<Widget> cutOutView(String path) async {
  final result = await bgRemoveBackgroundFromFile(remover, path);
  return BgRgbaImageView(result.cutout); // over a checkerboard
}
```

## Which function

- `bgRemoveBackgroundFromFile(remover, path)`: a JPEG, PNG or WebP file
  (its path also goes to ML Kit, which reads files). Not on the web.
- `bgRemoveBackgroundFromBytes(remover, bytes)`: encoded bytes, what
  `image_picker`'s `XFile.readAsBytes()` gives; the web's only input.
- `bgRemoveBackgroundFromImage(remover, image)`: image data, a
  `BgRgbaImage` (RGBA); `bgRgbaImageFromUiImage` gets one from a `ui.Image`.
- `bgPhotoFromFile` / `bgPhotoFromBytes` + `bgRemoveBackground`: decode
  once, then try several engines or options on the same photo.
- `options:` fine tunes the pipeline (`BgRemovalOptions`: what to keep,
  edges, crop, sizes), see `tekartik_bg_removal`.
- `result.toWebp()` / `result.toPng()` to save it; run them in an isolate
  (`bgRunInIsolate(() => bgEncodeWebp(image))` from a top-level function).
- `BgRgbaImageView(image, checkerboard: false)` for a plain view,
  `bgRgbaImageToUiImage` to paint it yourself (dispose the `ui.Image`).

The example app (`example/bg_removal_example`) does all of it: camera,
gallery, the cut-out next to the original, and a download.

## Common mistakes

- The first photo takes a minute: `prepare` was not called at start.
- `UnsupportedError` from `File` on the web: use the bytes functions.
- One app imports every engine: the web build then pulls Android plugins,
  the Android build `package:web`. Keep a web app and a mobile app apart.
- An `Isolate.run` closure created in a method captures `this` and fails
  to send: build it in a top-level function, as this package does.
- `BgRgbaImageView` keeps the image's aspect ratio: give it a bounded box
  (`Expanded`, `SizedBox`).

## Agent skills

`skills/tekartik-bg-removal-flutter-usage`, per
https://dart.dev/ai/package-skills.

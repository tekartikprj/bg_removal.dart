# tekartik_bg_removal_flutter

Background removal in a Flutter app: a photo from a file, encoded bytes, a
`ui.Image` or raw pixels in, a cut-out out (the person and what they carry),
with the heavy steps in an isolate, and a view that shows the cut-out over a
checkerboard. Exports `tekartik_bg_removal`.

Add the engines of your platforms:

| Platform | Engine | Package |
|---|---|---|
| Android | `BgRemoverFallback([BgMlKitRemover(), BgOnnxRemover()])` | `tekartik_bg_removal_mlkit` + `tekartik_bg_removal_onnx` |
| Linux | `BgOnnxRemover()` | `tekartik_bg_removal_onnx` |
| Web | `BgOnnxWebRemover()` | `tekartik_bg_removal_web` |

## Setup

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

On Android, the app's project needs a manifest entry and R8 rules: see the
skills of `tekartik_bg_removal_mlkit` and `tekartik_bg_removal_onnx`.

## Usage

```dart
import 'package:flutter/widgets.dart';
import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';
import 'package:tekartik_bg_removal_mlkit/bg_removal_mlkit.dart';
import 'package:tekartik_bg_removal_onnx/bg_removal_onnx.dart';

final remover = BgRemoverFallback([BgMlKitRemover(), BgOnnxRemover()]);

Future<Widget> cutOutView(String path) async {
  await remover.prepare(onStatus: print); // at start: model download, once
  final result = await bgRemoveBackgroundFromFile(remover, path);
  return BgRgbaImageView(result.cutout); // over a checkerboard
}
```

- `bgRemoveBackgroundFromFile(remover, path)`: a JPEG, PNG or WebP file
  (its path also goes to ML Kit, which reads files). Not on the web.
- `bgRemoveBackgroundFromBytes(remover, bytes)`: encoded bytes, what
  `image_picker`'s `XFile.readAsBytes()` gives.
- `bgRemoveBackgroundFromImage(remover, image)`: image data, a
  `BgRgbaImage` (RGBA); `bgRgbaImageFromUiImage` gets one from a `ui.Image`.
- `options:` fine tunes the pipeline (`BgRemovalOptions`: what to keep,
  edges, crop, sizes), see `tekartik_bg_removal`.
- `result.toWebp()` / `result.toPng()` to save it; run them in an isolate
  (`bgRunInIsolate(() => bgEncodeWebp(image))` from a top-level function).
- `BgRgbaImageView(image, checkerboard: false)` for a plain view,
  `bgRgbaImageToUiImage` to paint it yourself.

The example app (`example/bg_removal_example`) does all of it: camera,
gallery, the cut-out next to the original, and a download.

## Agent skills

`skills/tekartik-bg-removal-flutter-usage`, per
https://dart.dev/ai/package-skills.

---
name: tekartik-bg-removal-engines
description: >-
  Use when choosing, combining, testing or writing background removal
  engines with package:tekartik_bg_removal (BgRemover, getStatus, prepare,
  segment, close, BgRemoverStatus, BgEngineMasks, BgRemoverFallback,
  BgRemoverMerge, BgRemoverFake, the ONNX model manifest of models.dart:
  BgOnnxModel, bgOnnxModnetFp16, bgOnnxU2netp, bgOnnxIsnet, withBaseUrl,
  and the tensor helpers of tensor.dart: BgTensorSpec, bgRgbaImageTensor,
  bgOutputMask). Covers which engine per platform and why, a fallback
  chain, merging a person engine with a foreground engine, fakes for tests
  and UI work, implementing a new engine, and the mask operations. Running
  the pipeline itself is in tekartik-bg-removal-pipeline.
---

# tekartik_bg_removal engines

A `BgRemover` turns a `BgPhoto` into `BgEngineMasks`: a `person` mask
(portrait models), a `foreground` mask (salient objects, or "all subjects"),
or both, at the photo's size. The pipeline (`bgRemoveBackground`) does the
rest. Engines are in their own packages, so an app pulls only what it runs.

| Engine | Package | Platforms | Gives | Measured |
|---|---|---|---|---|
| `BgMlKitRemover` | `tekartik_bg_removal_mlkit` | Android (Play services) | foreground | best: IoU 0.97, 0.9 s on a Pixel 7a |
| `BgOnnxRemover` | `tekartik_bg_removal_onnx` | Android, Linux | person (MODNet) + foreground (u2netp / IS-Net) | IoU 0.87 (0.88 with IS-Net) |
| `BgOnnxWebRemover` | `tekartik_bg_removal_web` | web | the same as ONNX | the same scores |
| `BgRemoverFake` | here | everywhere | given masks | tests |

```dart
import 'package:tekartik_bg_removal/bg_removal.dart';

/// The best engine that can run here, the next ones after a failure.
BgRemover androidRemover(BgRemover mlkit, BgRemover onnx) =>
    BgRemoverFallback([mlkit, onnx]);
```

## Guidelines

### Lifecycle

* `getStatus()`: `ready`, `needsPrepare` (a download or a load to do), or
  `unsupported` (wrong platform, or the engine crashed the app before).
  Show it in an "engines" screen; it never downloads.
* `prepare(onStatus:)`: downloads and loads, throws when the engine cannot
  run. Call it once, early. `segment` prepares lazily if you forgot.
* `segment(photo, options:)`: the masks. Engines skip a model the options do
  not need (`BgKeep.person` does not run the salient model).
* `close()`: frees native sessions. A closed engine prepares again on the
  next call.

### Combining

* `BgRemoverFallback([a, b])`: `prepare` takes the first engine that is not
  unsupported and prepares; a failing `segment` moves on to the next one
  (prepared on the spot). `current` is the engine in use, `name` its name.
* `BgRemoverMerge(person: a, foreground: b)`: the person mask of one engine
  with the foreground of the other, so that the pipeline anchors the
  foreground on the person (`mlkit+modnet`: ML Kit's subjects that touch
  MODNet's person; drops another person standing apart).
* Prefer ML Kit alone on Android: it keeps the person and what they carry
  by itself, and merging with MODNet scored lower (0.94).

### Tests and UI work

* `BgRemoverFake(person:, foreground:)` returns the given masks resized to
  the photo: tests of the pipeline and of screens need no model.
* Masks for a fake: `BgMask(width, height, alpha)`, `BgMask.empty`,
  `BgMask.fromUnit(width, height, values0to1)`.

### Writing an engine

* Implement the 5 members of `BgRemover`. Masks must have the photo's size
  (`photo.width` x `photo.height`); resize with `mask.resized`.
* Put timings in `BgEngineMasks.timings` as `<model>.prepare`,
  `<model>.infer`, `<model>.post`: the benches read these keys.
* An ONNX-like model: `package:tekartik_bg_removal/models.dart` has the
  manifest (url, size, sha256, licence, input and output) and
  `bgRgbaImageTensor` / `bgOutputMask` build the NCHW input and read the
  output back as a mask.
* `BgOnnxModel.withBaseUrl` points a model at your own hosting (same file,
  same sha256 check); `webUrl` is the CORS-enabled copy browsers use.
* Mask operations for engines and editors: `bgCombineAnchored`,
  `bgDilate`, `bgLabel`, `bgRemoveSmallRegions`, `bgFillHoles`,
  `bgFeather`, `bgAlphaLevels`, `BgMask.bounds`, `BgMask.crop`.

## Examples

### A test without a model

```dart
import 'dart:typed_data';

import 'package:tekartik_bg_removal/bg_removal.dart';

Future<void> main() async {
  // 4 x 1 photo: a person on the left half.
  final photo = BgPhoto(BgRgbaImage(4, 1, Uint8List(16)));
  final remover = BgRemoverFake(
    person: BgMask(4, 1, Uint8List.fromList([255, 255, 0, 0])),
  );
  final result = await bgRemoveBackground(remover, photo);
  assert(result.mask.alpha[0] == 255 && result.mask.alpha[3] == 0);
}
```

### A new engine

```dart
import 'package:tekartik_bg_removal/bg_removal.dart';

/// Keeps the center third of the photo: a stand-in for a real model.
class CenterRemover implements BgRemover {
  @override
  String get name => 'center';

  @override
  Future<BgRemoverStatus> getStatus() async => BgRemoverStatus.ready;

  @override
  Future<void> prepare({void Function(String status)? onStatus}) async {}

  @override
  Future<BgEngineMasks> segment(
    BgPhoto photo, {
    BgRemovalOptions options = const BgRemovalOptions(),
  }) async {
    final sw = Stopwatch()..start();
    final mask = BgMask.empty(photo.width, photo.height);
    for (var y = 0; y < photo.height; y++) {
      for (var x = photo.width ~/ 3; x < photo.width * 2 ~/ 3; x++) {
        mask.alpha[y * photo.width + x] = 255;
      }
    }
    return BgEngineMasks(
      foreground: mask,
      timings: {'center.infer': sw.elapsed},
    );
  }

  @override
  Future<void> close() async {}
}
```

### A model from your own hosting

```dart
import 'package:tekartik_bg_removal/models.dart';

final models = [
  for (final model in bgOnnxModels)
    model.withBaseUrl('https://example.com/models/'),
];
```

## Common mistakes

* `ArgumentError: an engine gives a person or a foreground mask`:
  `BgEngineMasks` needs at least one of them.
* A cut-out offset or stretched: the engine returned a mask of another
  size than the photo (its own input size): resize it to `photo.width` x
  `photo.height`.
* After a native crash, `BgRemoverFallback` keeps using the crashed engine:
  it only moves on when `getStatus` says `unsupported` or `prepare` /
  `segment` throws; a crash guard (as in `BgMlKitRemover`) makes the next
  start say so.

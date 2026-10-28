# tekartik_bg_removal

Background removal that keeps a person and what they carry (a bag, an
umbrella, a phone): the images, the engine interface and the pipeline, in
pure Dart. The engines are in `tekartik_bg_removal_mlkit` (Android),
`tekartik_bg_removal_onnx` (Android, Linux) and `tekartik_bg_removal_web`
(web); Flutter apps start with `tekartik_bg_removal_flutter`.

## Setup

```yaml
dependencies:
  tekartik_bg_removal:
    git:
      url: https://github.com/tekartikprj/bg_removal.dart
      path: packages/bg_removal
```

## Usage

```dart
import 'package:tekartik_bg_removal/bg_removal.dart';

Future<void> cutOut(BgRemover remover, BgRgbaImage image) async {
  await remover.prepare(); // downloads or loads the models, once
  final result = await bgRemoveBackground(
    remover,
    BgPhoto(image), // RGBA pixels (+ filePath when there is a file)
    options: const BgRemovalOptions(crop: true, maxOutputSize: 1024),
    run: bgRunInIsolate, // the heavy steps off the calling isolate
  );
  final webp = result.toWebp(quality: 80); // or toPng(), result.cutout
  print('${result.engine}: ${webp.length} bytes, ${result.timings}');
}
```

- `BgRgbaImage`: RGBA bytes, straight alpha, `width * height * 4`.
- `BgMask`: one byte per pixel, 0 removed, 255 kept.
- `BgRemover`: an engine (`getStatus`, `prepare`, `segment`, `close`);
  `BgRemoverFallback` chains them (ML Kit, then ONNX), `BgRemoverMerge`
  takes the person of one and the foreground of another, `BgRemoverFake`
  returns given masks (tests).
- `bgRemoveBackground`: keeps the person and the foreground regions
  touching them, cleans the mask as the options ask, and makes the cut-out.
- `BgRemovalResult`: `cutout`, `mask` (photo size), `box` (the crop),
  `engine`, `timings`, `toPng()`, `toWebp()` (lossy colour, lossless alpha).

### Fine tuning (`BgRemovalOptions`)

The defaults are the measured ones; change them only when a photo needs it.

| Option | Default | What it does |
|---|---|---|
| `keep` | `personAndCarried` | `personAndCarried`, `person` (needs a person mask), `foreground` (every subject) |
| `anchorGrow` | 0.01 | how far (share of the long side) a carried thing can be from the person |
| `threshold` | 128 | the alpha from which a pixel counts in the region steps |
| `transparentBelow` / `opaqueAbove` | 0 / 255 | alpha levels: a faint halo goes, a nearly solid subject becomes solid |
| `minRegion` | 0 (off) | removes regions smaller than this share of the photo (0.005: specks) |
| `fillHoles` | 0 (off) | fills enclosed holes smaller than this share |
| `feather` | 0 (off) | softens the edge by N pixels |
| `maxSegmentSize` | null | the engine works on the photo scaled down to this long side |
| `crop`, `cropMargin` | false, 16 | crops the cut-out to the subject |
| `maxOutputSize` | null | scales the cut-out down |

`BgRemovalOptions.fromJson` / `toJson` / `copyWith` make them easy to store
or to expose in a settings screen.

### Libraries

- `package:tekartik_bg_removal/bg_removal.dart`: everything above.
- `package:tekartik_bg_removal/models.dart`: the ONNX model manifest (url,
  size, sha256, licence, input, output) and the tensor helpers.
- `package:tekartik_bg_removal/score.dart`: IoU and bag score against a
  reference mask (the benches).

## Agent skills

`skills/tekartik-bg-removal-pipeline` (using the pipeline and its options)
and `skills/tekartik-bg-removal-engines` (choosing, combining, testing and
writing engines), per https://dart.dev/ai/package-skills.

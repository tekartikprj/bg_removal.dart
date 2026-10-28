---
name: tekartik-bg-removal-pipeline
description: >-
  Use when removing the background of a photo with package:tekartik_bg_removal
  (bgRemoveBackground, BgPhoto, BgRgbaImage, BgMask, BgBox,
  BgRemovalOptions, BgKeep, BgRemovalResult, toPng, toWebp, bgEncodePng,
  bgEncodeWebp, bgEncodeMaskPng, bgRunInline, bgRunInIsolate, BgRunner).
  Covers the pipeline (engine masks, keep person and carried things,
  combine, clean, cut-out), fine tuning with the options (anchorGrow,
  threshold, transparentBelow, opaqueAbove, minRegion, fillHoles, feather,
  maxSegmentSize, crop, maxOutputSize), the result and its timings,
  encoding, and running the heavy steps in an isolate. Choosing, combining
  or writing engines is in tekartik-bg-removal-engines.
---

# tekartik_bg_removal pipeline

`bgRemoveBackground(remover, photo)` turns a photo into a cut-out: the
engine (`BgRemover`) gives a person mask and/or a foreground mask, the
pipeline keeps the person and what they carry, cleans the mask, and puts it
as the alpha of the photo. Pure Dart: images are RGBA bytes
(`BgRgbaImage`), masks are one byte per pixel (`BgMask`, 0 removed, 255
kept).

```dart
import 'dart:typed_data';

import 'package:tekartik_bg_removal/bg_removal.dart';

Future<Uint8List> cutOut(BgRemover remover, BgRgbaImage image) async {
  await remover.prepare();
  final result = await bgRemoveBackground(
    remover,
    BgPhoto(image),
    run: bgRunInIsolate,
  );
  return result.toWebp(quality: 80);
}
```

## Guidelines

### The photo and the engine

* A `BgPhoto` is the decoded pixels (`BgRgbaImage`, orientation already
  applied) and, when there is one, the encoded file (`filePath`): engines
  that read files (ML Kit) use it, the others use the pixels.
* In Flutter, prefer `tekartik_bg_removal_flutter`
  (`bgRemoveBackgroundFromFile`, `...FromBytes`, `...FromImage`): it decodes
  and runs in an isolate for you.
* Always `await remover.prepare()` before the first photo, early (it can
  download models or wait for a Play services module): `bgRemoveBackground`
  calls `segment`, which prepares lazily, but then the first photo waits.
* The engines live in other packages: `tekartik_bg_removal_mlkit` (Android),
  `tekartik_bg_removal_onnx` (Android, Linux), `tekartik_bg_removal_web`
  (web). Tests use `BgRemoverFake`.

### Running off the UI isolate

* Pass `run: bgRunInIsolate` from a Flutter app: the mask and cut-out steps
  are pure Dart loops over every pixel (tens to hundreds of ms on a phone).
  `bgRunInIsolate` uses `Isolate.run` natively and runs inline on the web
  (dart2js and dart2wasm have no isolates to run in).
* The default `bgRunInline` is for tests and command line tools.
* When you write your own `BgRunner` computation, build the closure in a
  top-level function: a closure made inside a method captures `this`, which
  may not be sendable to an isolate.

### Options (`BgRemovalOptions`), the defaults are the measured ones

* `keep`: `BgKeep.personAndCarried` (default) keeps the person mask plus
  the foreground regions touching it (a bag, an umbrella); with only one
  mask (ML Kit gives a foreground only) that mask is the result.
  `BgKeep.person` needs a person mask (MODNet) or throws
  `UnsupportedError`. `BgKeep.foreground` keeps every subject.
* `anchorGrow` (0.01 of the long side): how far a carried thing can be from
  the person. Raise it for a bag held at arm's length.
* `threshold` (128): the alpha from which a pixel counts in the region
  steps (anchoring, small regions, holes, crop box).
* `transparentBelow` / `opaqueAbove` (0 / 255, off): alpha levels. 24 / 230
  remove a faint halo and make a nearly solid subject solid.
* `minRegion` (0, off): drop regions smaller than this share of the photo
  (0.005 removes specks; mind small people far away).
* `fillHoles` (0, off): fill enclosed holes smaller than this share (0.01
  fills a see-through spot in a bag, not the gap between an arm and the
  body, which touches the background).
* `feather` (0, off): blur the edge by N pixels (1 or 2 for a soft edge).
* `maxSegmentSize` (null): the engine sees the photo scaled down to this
  long side; the mask is scaled back up. 1600 keeps a phone under a second.
* `crop` + `cropMargin` (false, 16): crop the cut-out to the subject;
  `result.box` is the crop in photo pixels.
* `maxOutputSize` (null): scale the cut-out down (colour and alpha are
  scaled apart, no background colour bleeds into the edge).
* Options round-trip through json (`toJson`, `BgRemovalOptions.fromJson`,
  missing keys keep their default) and `copyWith`.

### The result

* `result.cutout`: the RGBA cut-out (cropped and scaled as asked).
* `result.mask`: the final mask at the photo size (before crop and scale),
  to edit or to apply elsewhere.
* `result.engine`: the engine that made it (with a fallback, the one that
  ran). `result.timings`: the engine's steps (`<model>.prepare`,
  `<model>.infer`, `<model>.post`) then `downscale`, `segment`, `mask`,
  `cutout`.
* `toWebp(quality: 80)`: lossy colour, lossless alpha, about 170 KB for
  1600x1200, but 1 s of pure Dart on a desktop (more on a phone, run it in
  an isolate). `toPng()`: lossless, about 2.3 MB, faster. `bgEncodeMaskPng`
  writes a mask as a grey PNG.

## Examples

### Fine tuning

```dart
import 'package:tekartik_bg_removal/bg_removal.dart';

Future<BgRemovalResult> portrait(BgRemover remover, BgPhoto photo) =>
    bgRemoveBackground(
      remover,
      photo,
      options: const BgRemovalOptions(
        // A bag held at arm's length, a soft clean edge.
        anchorGrow: 0.03,
        transparentBelow: 24,
        opaqueAbove: 230,
        minRegion: 0.005,
        feather: 1,
        // Fast on big photos, a cropped and small output.
        maxSegmentSize: 1600,
        crop: true,
        maxOutputSize: 1024,
      ),
      run: bgRunInIsolate,
    );
```

### Options from json (a settings screen, a command line)

```dart
import 'dart:convert';

import 'package:tekartik_bg_removal/bg_removal.dart';

BgRemovalOptions optionsFrom(String json) => BgRemovalOptions.fromJson(
  jsonDecode(json) as Map<String, Object?>,
).copyWith(keep: BgKeep.personAndCarried);
```

### Applying a mask yourself

```dart
import 'package:tekartik_bg_removal/bg_removal.dart';

/// [mask] edited by the user (brush), applied to the photo again.
BgRgbaImage applyMask(BgRgbaImage photo, BgMask mask) {
  final (cutout, _) = bgCutOut(
    photo,
    bgFeather(mask, 1),
    const BgRemovalOptions(),
  );
  return cutout;
}
```

## Common mistakes

* The UI freezes during a removal: `run: bgRunInIsolate` was not passed.
* `UnsupportedError: keep person`: `BgKeep.person` with an engine that has
  no person mask (ML Kit alone): use `BgRemoverMerge` with MODNet, see
  tekartik-bg-removal-engines.
* `ArgumentError: rgba length ... does not match`: a `BgRgbaImage` needs
  exactly `width * height * 4` bytes, RGBA (not BGRA, not RGB).

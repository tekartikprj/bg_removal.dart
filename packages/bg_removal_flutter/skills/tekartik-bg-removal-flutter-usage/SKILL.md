---
name: tekartik-bg-removal-flutter-usage
description: >-
  Use when adding background removal (keep the person and what they carry)
  to a Flutter app with package:tekartik_bg_removal_flutter
  (bgRemoveBackgroundFromFile, bgRemoveBackgroundFromBytes,
  bgRemoveBackgroundFromImage, bgPhotoFromFile, bgPhotoFromBytes,
  bgDecodeImage, bgRgbaImageFromUiImage, bgRgbaImageToUiImage,
  BgRgbaImageView). Covers the input (file, encoded bytes, image data,
  ui.Image, camera or gallery), choosing the engine per platform (ML Kit and
  ONNX on Android, ONNX on Linux, onnxruntime-web on the web), preparing it
  with a status, showing and saving the cut-out, and keeping the UI fluid.
  The options are detailed in tekartik_bg_removal's skills, the Android
  project setup in the mlkit and onnx packages' skills.
---

# tekartik_bg_removal_flutter usage

This package exports `tekartik_bg_removal` (the pipeline) and adds what a
Flutter app needs: photos from a file, bytes or a `ui.Image`, the removal in
an isolate, and a view of the cut-out over a checkerboard. Add the engines
of your platforms: `tekartik_bg_removal_mlkit`, `tekartik_bg_removal_onnx`,
`tekartik_bg_removal_web`.

```dart
import 'dart:typed_data';

import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';

/// [remover]: `BgRemoverFallback([BgMlKitRemover(), BgOnnxRemover()])` on
/// Android, `BgOnnxWebRemover()` on the web.
Future<Uint8List> cutOutFile(BgRemover remover, String path) async {
  final result = await bgRemoveBackgroundFromFile(remover, path);
  return result.toPng();
}
```

## Guidelines

### Input

* A file (`bgRemoveBackgroundFromFile`): decoded by Flutter (EXIF
  orientation applied), and its path goes to the engines that read files
  (ML Kit). Not on the web (no files): use bytes there.
* Encoded bytes (`bgRemoveBackgroundFromBytes`): JPEG, PNG, WebP; what
  `image_picker`'s `XFile.readAsBytes()` and the web give.
* Image data (`bgRemoveBackgroundFromImage`): a `BgRgbaImage` (RGBA bytes,
  `width * height * 4`); `bgRgbaImageFromUiImage` gets one from a
  `ui.Image` (a camera frame, a `RepaintBoundary`).
* `bgPhotoFromFile` / `bgPhotoFromBytes` + `bgRemoveBackground` when you
  need the `BgPhoto` too (several engines or options on one photo: decode
  once).
* Ask the picker for at most 1600 px (`maxWidth`, `maxHeight` of
  `image_picker`): a 12 Mpx photo costs memory and time for no better
  cut-out; or set `BgRemovalOptions(maxSegmentSize: 1600)`.

### Engines per platform

* Android: `BgRemoverFallback([BgMlKitRemover(), BgOnnxRemover()])`. ML Kit
  is the best and fastest where Google Play services exist; ONNX takes over
  without them, or after ML Kit crashed the app (it has a crash guard).
* Linux (and the other desktops with onnxruntime): `BgOnnxRemover()`.
* Web: `BgOnnxWebRemover()` (`tekartik_bg_removal_web`), imported only by
  the web app: keep the web and the Android apps apart (separate apps or
  conditional imports) so that each builds only its engines.

### Prepare, then remove

* Call `remover.prepare(onStatus: ...)` at start and show the status: the
  first run downloads models (18 MB for ONNX) or waits for the Play
  services module (ML Kit, after an install). A photo picked meanwhile
  waits for it.
* The `...From*` functions run the pipeline steps in an isolate
  (`bgRunInIsolate`, inline on the web); the engines run natively. Encode
  in an isolate too: `bgRunInIsolate(() => bgEncodeWebp(image))` from a
  top-level function.
* `close()` the engine when the screen goes (frees native sessions).

### Show and save

* `BgRgbaImageView(result.cutout)` draws the cut-out over a checkerboard
  (`checkerboard: false` for a plain one), keeping its aspect ratio; give it
  a bounded box (`Expanded`, `SizedBox`).
* `bgRgbaImageToUiImage` for your own painting (dispose the `ui.Image`).
* Save `result.toWebp()` (about 170 KB for 1600x1200, lossless alpha) or
  `result.toPng()` (2.3 MB, faster to encode); on Android a "save as"
  dialog (`tekaly_file_download`'s `downloadFile`, or `file_picker`'s
  `saveFile`) needs no storage permission.

## Examples

### A screen: pick, remove, show

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';

class CutOutPage extends StatefulWidget {
  final BgRemover remover;
  final Future<Uint8List?> Function() pickPhoto;

  const CutOutPage({super.key, required this.remover, required this.pickPhoto});

  @override
  State<CutOutPage> createState() => _CutOutPageState();
}

class _CutOutPageState extends State<CutOutPage> {
  var _status = 'Preparing...';
  BgRemovalResult? _result;

  @override
  void initState() {
    super.initState();
    widget.remover
        .prepare(onStatus: (s) => setState(() => _status = s))
        .then((_) => setState(() => _status = 'Ready'))
        .catchError((Object e) => setState(() => _status = 'Error: $e'));
  }

  Future<void> _pick() async {
    final bytes = await widget.pickPhoto();
    if (bytes == null) return;
    setState(() => _status = 'Removing the background...');
    final result = await bgRemoveBackgroundFromBytes(
      widget.remover,
      bytes,
      options: const BgRemovalOptions(crop: true),
    );
    setState(() {
      _result = result;
      _status = '${result.engine}, done';
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: Text(_status)),
      body: result == null
          ? const SizedBox.expand()
          : Center(child: BgRgbaImageView(result.cutout)),
      floatingActionButton: FloatingActionButton(
        onPressed: _pick,
        child: const Icon(Icons.photo),
      ),
    );
  }
}
```

### From a ui.Image

```dart
import 'dart:ui' as ui;

import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';

Future<ui.Image> cutOutUiImage(BgRemover remover, ui.Image image) async {
  final result = await bgRemoveBackgroundFromImage(
    remover,
    await bgRgbaImageFromUiImage(image),
  );
  return bgRgbaImageToUiImage(result.cutout);
}
```

## Common mistakes

* The first photo takes a minute: `prepare` was not called at start (model
  download, Play services module).
* `UnsupportedError` from `File` on the web: use the bytes functions.
* A web build pulls ML Kit or onnxruntime Android code, or an Android build
  pulls `package:web`: one app imports every engine; split the apps.
* Release builds fail on Android while debug works: the R8 rules and the
  manifest entries are missing, see the skills of
  `tekartik_bg_removal_mlkit` and `tekartik_bg_removal_onnx`.

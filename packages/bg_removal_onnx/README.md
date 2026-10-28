# tekartik_bg_removal_onnx

The ONNX engine of `tekartik_bg_removal`, on Android and Linux (through
`flutter_onnxruntime`): MODNet fp16 for the person (13 MB) and u2netp for the
salient objects (4.6 MB), or IS-Net (179 MB) for hard photos. The pipeline
keeps the person and the objects touching them. The models are downloaded
once and checked by size and sha256.

Measured on the fixtures: MODNet + u2netp mean IoU 0.87 (6 bags of 7), 1.8 s
for a 1600x1200 photo on a Pixel 7a, 0.59 s on a desktop; MODNet + IS-Net
0.88 (7 of 7). On Android prefer ML Kit (`tekartik_bg_removal_mlkit`) and
keep this engine as the fallback.

## Setup

```yaml
dependencies:
  tekartik_bg_removal_onnx:
    git:
      url: https://github.com/tekartikprj/bg_removal.dart
      path: packages/bg_removal_onnx
```

On Android: the `INTERNET` permission in the main manifest, and
`-keep class ai.onnxruntime.** { *; }` in `android/app/proguard-rules.pro`
(skill below). Ship an app bundle or `--split-per-abi` APKs:
`libonnxruntime.so` is 28.6 MB per ABI.

## Usage

```dart
import 'package:tekartik_bg_removal/bg_removal.dart';
import 'package:tekartik_bg_removal_onnx/bg_removal_onnx.dart';

Future<BgRemovalResult> cutOut(BgRgbaImage image) async {
  final remover = BgOnnxRemover(); // MODNet + u2netp
  // BgOnnxRemover(salient: bgOnnxIsnet): better on hard photos, 5x slower.
  // BgOnnxRemover(salient: null): MODNet alone, the person only.
  await remover.prepare(onStatus: print); // 18 MB downloaded once
  return bgRemoveBackground(remover, BgPhoto(image), run: bgRunInIsolate);
}
```

- `BgOnnxModelCache(dir:, localDirs:)`: where the models go (default: the
  app's support folder), and folders to use without a download.
- `bgOnnxU2netp.withBaseUrl('https://example.com/models/')`: the models
  from your own hosting (same sha256 check).
- `providers: [OrtProvider.XNNPACK]` or `NNAPI` (Android) to try a
  delegate, `threads:` to set the thread count; the CPU is the measured
  default.

## Agent skills

`skills/tekartik-bg-removal-onnx-android-setup`, per
https://dart.dev/ai/package-skills.

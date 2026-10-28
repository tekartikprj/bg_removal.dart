---
name: tekartik-bg-removal-onnx-android-setup
description: >-
  Use when setting up, building or debugging the Android (or Linux)
  project of a Flutter app that removes photo backgrounds with
  package:tekartik_bg_removal_onnx (BgOnnxRemover, BgOnnxModelCache,
  bgOnnxModnetFp16, bgOnnxU2netp, bgOnnxIsnet, OrtProvider) on
  flutter_onnxruntime. Covers the INTERNET permission for the model
  download, the ai.onnxruntime R8 keep rule of release builds, APK size and
  split-per-abi, where models are cached and how to self-host them,
  providers and threads, and the measured speed on a phone. For ML Kit see
  the skill of tekartik_bg_removal_mlkit.
---

# tekartik_bg_removal_onnx Android setup

`BgOnnxRemover` runs MODNet (the person, 13 MB) and u2netp (salient objects,
4.6 MB) or IS-Net (179 MB) on ONNX Runtime. The models are downloaded on
first use and checked by size and sha256. The Android project needs the
permission and the R8 rule below.

## Guidelines

* Always add `android.permission.INTERNET` to the main manifest
  (`android/app/src/main/AndroidManifest.xml`): the debug and profile
  manifests have it, so a missing permission only breaks release builds.
* Always keep ONNX Runtime from R8 in `android/app/proguard-rules.pro`
  (`-keep class ai.onnxruntime.** { *; }`): its Java classes are called
  from native code. The Flutter Gradle plugin applies the file to release
  builds by itself.
* Ship an app bundle or `--split-per-abi` APKs: `libonnxruntime.so` is
  28.6 MB per ABI (onnxruntime-android 1.28.0 through flutter_onnxruntime
  1.9.0); a fat APK carries every ABI.
* Prefer models from your own hosting for an app in production
  (`bgOnnxU2netp.withBaseUrl('https://...')`): the defaults are a GitHub
  release (rembg) and Hugging Face, which can change. The sha256 check stays.
* The cache is `tekartik_bg_removal/models` in the app's support folder;
  pass `BgOnnxModelCache(dir: ...)` to choose, `localDirs` to use files
  already on disk (Linux) without a download. `isCached` tells whether
  `prepare` will download.
* Call `prepare` before the first photo: it downloads (progress through
  `onStatus`) and loads the sessions.
* The CPU provider is the default and the measured one. XNNPACK and NNAPI
  are options (`providers:`), the CPU is always added last as a fallback.
* `BgRemovalOptions.keep` skips the model the result does not use
  (`BgKeep.person` runs MODNet only).
* Measured on a Pixel 7a, release, CPU, 1600x1200 photo: MODNet 0.84 s,
  u2netp 0.80 s, the pair with the combination 1.8 s; IS-Net 5 s. On the
  7 fixtures MODNet + u2netp keeps 6 bags of 7 (mean IoU 0.87), MODNet +
  IS-Net 7 of 7 (0.88). ML Kit (tekartik_bg_removal_mlkit) is better and
  faster where Google Play services exist: keep ONNX as the fallback.

## Examples

### Manifest and R8

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application ...>
```

```
# android/app/proguard-rules.pro
-keep class ai.onnxruntime.** { *; }
```

### Prepare with progress, then remove a background

```dart
import 'package:tekartik_bg_removal/bg_removal.dart';
import 'package:tekartik_bg_removal_onnx/bg_removal_onnx.dart';

Future<BgRemovalResult> removeBackground(BgRgbaImage image) async {
  final remover = BgOnnxRemover(
    // The models from your own hosting (same files, same sha256).
    person: bgOnnxModnetFp16.withBaseUrl('https://example.com/models/'),
    salient: bgOnnxU2netp.withBaseUrl('https://example.com/models/'),
  );
  if (!await remover.cache.isCached(bgOnnxModnetFp16)) {
    // About 18 MB to download once.
  }
  await remover.prepare(onStatus: print);
  try {
    return await bgRemoveBackground(
      remover,
      BgPhoto(image),
      run: bgRunInIsolate,
    );
  } finally {
    await remover.close();
  }
}
```

## Common mistakes

* Downloads work in debug, fail in release: `INTERNET` is missing from the
  main manifest.
* Release build crashes or fails to create a session: the
  `ai.onnxruntime` keep rule is missing.
* A 100+ MB APK: built without `--split-per-abi` (every ABI's
  onnxruntime).

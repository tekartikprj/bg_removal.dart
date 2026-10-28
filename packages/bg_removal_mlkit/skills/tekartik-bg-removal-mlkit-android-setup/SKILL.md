---
name: tekartik-bg-removal-mlkit-android-setup
description: >-
  Use when setting up, building or debugging the Android project of a
  Flutter app that removes photo backgrounds with
  package:tekartik_bg_removal_mlkit (BgMlKitRemover, ML Kit Subject
  Segmentation from Google Play services), alone or with the ONNX fallback
  of tekartik_bg_removal_onnx (BgOnnxRemover, flutter_onnxruntime).
  Covers AndroidManifest.xml (com.google.mlkit.vision.DEPENDENCIES
  subject_segment, INTERNET), the R8 keep rules of
  android/app/proguard-rules.pro that release builds need, minSdk, APK
  size and split-per-abi, the Play services module download, the native
  crash of the per-subject masks and the crash guard, BgRemoverFallback,
  emulators, and checking a release build on a phone over adb.
---

# tekartik_bg_removal_mlkit Android setup

`BgMlKitRemover` runs ML Kit Subject Segmentation: its model is not in the
APK, Google Play services downloads it. A package cannot add Android
manifest entries or R8 rules to the app (it has no Android module), so the
app's Android project needs the few lines below, or release builds fail at
once and the first photos wait for a download.

Measured on a Pixel 7a (Android 17): mean IoU 0.97 and every bag kept on
the fixtures, 0.93 s for a 1600x1200 photo; the best Android engine.

## Guidelines

### AndroidManifest.xml (`android/app/src/main/AndroidManifest.xml`)

* Always add the ML Kit dependency meta-data inside `<application>`: Play
  services then downloads the model at install time (from the Play Store).
  Without it, the download starts on the first call.
* After an `adb install` (not from the Play Store) the module is not there
  either: the first calls fail with "Waiting for the subject segmentation
  optional module to be downloaded". `BgMlKitRemover.prepare` waits for it
  (`moduleWait`, 3 minutes by default); call `prepare` early (a splash, an
  "engines" screen), not on the first photo.
* Add `android.permission.INTERNET` to the main manifest when the app also
  uses the ONNX engine: its models are downloaded on first use. Flutter's
  debug and profile manifests already have it, so a missing permission only
  shows in release builds.

### R8 rules (release builds)

* Always keep ML Kit in `android/app/proguard-rules.pro`. With AGP 9 R8,
  every ML Kit call of a release build fails at once with
  `NullPointerException: Attempt to invoke virtual method
  'java.lang.Class java.lang.Object.getClass()' on a null object reference`
  thrown from `com.google.android.gms.internal.mlkit_vision_common` when the
  `InputImage` is built. Debug builds are fine, so test a release build.
* With the ONNX engine, keep `ai.onnxruntime.**` too.
* The Flutter Gradle plugin applies `android/app/proguard-rules.pro` to
  release builds by itself when the file exists: no Gradle change.

### SDK and Gradle

* `minSdk` 24 or more (ML Kit Subject Segmentation needs API 24; it is
  `flutter.minSdkVersion` today).
* The device needs Google Play services. Without them `prepare` throws:
  put the ONNX engine after ML Kit in a `BgRemoverFallback`.
* Verified with AGP 9.1.0, Kotlin 2.4.0, Gradle wrapper of the Flutter
  template and its `gradle.properties` flags (`android.newDsl=false`,
  `android.builtInKotlin=false`). `flutter_onnxruntime` triggers the
  "plugins that apply Kotlin Gradle Plugin" warning: harmless for now.

### Size

* ML Kit adds almost nothing to the APK (the model is in Play services).
* ONNX Runtime does: `libonnxruntime.so` is 28.6 MB per ABI (the arm64
  release APK of the bench is 48.5 MB). Ship an app bundle, or build APKs
  with `--split-per-abi`. An app without the ONNX fallback does not depend
  on `tekartik_bg_removal_onnx` and has no onnxruntime at all.

### Native crashes

* Never ask ML Kit for each subject's mask (`enableMultipleSubjects` with
  `enableConfidenceMask` in `google_mlkit_subject_segmentation`): the Play
  services module (264131100400) dies in a `memcpy` (SIGSEGV), whatever the
  input (file, bitmap, NV21). `BgMlKitRemover` only asks for the foreground
  mask; do not call the plugin directly with per-subject options.
* A native crash kills the process, no Dart `catch` sees it. Before each
  call `BgMlKitRemover` writes a guard file
  (`tekartik_bg_removal_mlkit_guard.txt` in the support folder, or
  `guardDir`); after a crash `getStatus()` answers `unsupported`, `prepare`
  throws, and a `BgRemoverFallback` moves on to the next engine.
  `lastCrash()` tells what was running, `clearCrash()` or
  `retryAfterCrash: true` tries ML Kit again.
* Test on a real arm64 phone: on x86_64 emulators ML Kit crashed in its GL
  thread (`drishti_gl_runn`), with the software GPU and the host GPU.

## Examples

### The manifest

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Only with the ONNX engine: its models are downloaded once. -->
    <uses-permission android:name="android.permission.INTERNET" />
    <application ...>
        <!-- ML Kit Subject Segmentation: Play services downloads the model
             at install time, not on the first photo. -->
        <meta-data
            android:name="com.google.mlkit.vision.DEPENDENCIES"
            android:value="subject_segment" />
        <activity ...>
    </application>
</manifest>
```

### `android/app/proguard-rules.pro`

```
# ML Kit: R8 (AGP 9) breaks InputImage in release ("getClass() on a null
# object reference" in mlkit_vision_common), keep ML Kit as is.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
# Only with the ONNX engine (tekartik_bg_removal_onnx).
-keep class ai.onnxruntime.** { *; }
```

### ML Kit first, a fallback engine after a crash

```dart
import 'package:tekartik_bg_removal/bg_removal.dart';
import 'package:tekartik_bg_removal_mlkit/bg_removal_mlkit.dart';

/// ML Kit when it can run, else [fallback] (`BgOnnxRemover()` of
/// tekartik_bg_removal_onnx): no Play services, or ML Kit crashed the app
/// last time.
Future<BgRemover> prepareRemover(
  BgRemover fallback, {
  void Function(String status)? onStatus,
}) async {
  final mlkit = BgMlKitRemover();
  final crash = await mlkit.lastCrash();
  if (crash != null) {
    onStatus?.call('ML Kit crashed last time ($crash), using the fallback');
  }
  final remover = BgRemoverFallback([mlkit, fallback]);
  // Waits for the Play services module after an install.
  await remover.prepare(onStatus: onStatus);
  return remover;
}
```

### Check a release build on a phone

```sh
flutter build apk --release --split-per-abi --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# Dart prints, then native crashes (signal, top frames):
adb logcat -v raw flutter:I '*:S'
adb logcat -b crash -d
```

## Common mistakes

* Release build only, every ML Kit call fails with "getClass() on a null
  object reference": the R8 keep rules are missing.
* The app dies on the first photo with `Fatal signal 11 (SIGSEGV)` in
  `dl-MlkitSubjectSegmentation.optional_*.apk`: per-subject masks were
  asked (direct plugin use), or an emulator.
* The first photos after an install fail with "Waiting for the subject
  segmentation optional module to be downloaded": `prepare` was not
  awaited first, or the manifest meta-data is missing.
* ONNX models download in debug but not in release: `INTERNET` is missing
  from the main manifest.

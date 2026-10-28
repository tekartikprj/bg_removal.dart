# tekartik_bg_removal_mlkit

The ML Kit engine of `tekartik_bg_removal`: Subject Segmentation on Android,
its model delivered by Google Play services. It keeps the person and what
they carry by itself, and it is the best engine measured: mean IoU 0.97 and
every bag kept on the fixtures, 0.9 s for a 1600x1200 photo on a Pixel 7a.

## Setup

```yaml
dependencies:
  tekartik_bg_removal_mlkit:
    git:
      url: https://github.com/tekartikprj/bg_removal.dart
      path: packages/bg_removal_mlkit
```

The app's Android project needs (details in the skill below):

- in `android/app/src/main/AndroidManifest.xml`, inside `<application>`:

  ```xml
  <meta-data
      android:name="com.google.mlkit.vision.DEPENDENCIES"
      android:value="subject_segment" />
  ```

- in `android/app/proguard-rules.pro` (release builds fail without it):

  ```
  -keep class com.google.mlkit.** { *; }
  -keep class com.google.android.gms.internal.mlkit_** { *; }
  ```

- `minSdk` 24 or more, and a device with Google Play services.

## Usage

```dart
import 'package:tekartik_bg_removal/bg_removal.dart';
import 'package:tekartik_bg_removal_mlkit/bg_removal_mlkit.dart';

/// ML Kit, or [fallback] (an ONNX engine) when it cannot run.
Future<BgRemover> androidEngine(BgRemover fallback) async {
  final remover = BgRemoverFallback([BgMlKitRemover(), fallback]);
  await remover.prepare(onStatus: print); // waits for the Play services module
  return remover;
}
```

- Only the foreground mask is asked: ML Kit's per-subject masks crash the
  app in native code (Android 17, Play services module 264131100400).
- A native crash cannot be caught: each call is written to a guard file
  first, and after a crash `getStatus()` says `unsupported`, so a
  `BgRemoverFallback` moves on to the next engine. `lastCrash()`,
  `clearCrash()`, `retryAfterCrash: true`.
- After an install, the module may still be downloading: `prepare` waits
  (`moduleWait`, 3 minutes).
- ML Kit gives a foreground (every subject) but no person mask: for
  `BgKeep.person`, merge it with MODNet (`BgRemoverMerge`).

## Agent skills

`skills/tekartik-bg-removal-mlkit-android-setup` (the Android project, the
crash guard, release builds), per https://dart.dev/ai/package-skills.

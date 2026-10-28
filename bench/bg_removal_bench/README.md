# bg_removal_bench

The bench of the engines on Android and Linux: every method on the fixtures
(7 photos with hand-made reference masks), scored, plus a timing pass on one
photo of a given size through the public API. The web bench is
`../bg_removal_bench_web`; the two apps do not depend on each other (one
platform's dependencies never hold back the other's) and share
`../bg_removal_bench_common`.

This app only holds what is Android and Linux: the engines
(`lib/src/bench_setup.dart`: ML Kit, ONNX), the files of a run
(`BenchIoHost`), the ML Kit probe and the tools. The ONNX models are
downloaded on first use into the app's support folder (`models/`), checked
by size and sha256. On Linux, `BG_REMOVAL_MODELS=<dir>` uses local files
instead.

## On Android

What runs, all of it on the phone (no server):

- **ML Kit Subject Segmentation**: `google_mlkit_subject_segmentation`
  0.2.1 → `play-services-mlkit-subject-segmentation` 16.0.0-beta1. The
  model is not in the APK: Play services downloads it (the manifest asks
  for it at install, `com.google.mlkit.vision.DEPENDENCIES`). Only the
  foreground confidence mask is used: asking for each subject's mask
  crashes the app (see Known).
- **ONNX Runtime**: `flutter_onnxruntime` 1.9.0 → `onnxruntime-android`
  1.28.0, CPU provider by default (XNNPACK and NNAPI can be chosen). It is
  most of the APK: `libonnxruntime.so` is 28.6 MB of the 48.5 MB arm64
  release APK.
- **The models**, downloaded on first use and checked by sha256:
  MODNet fp16 (13 MB, person matting, Hugging Face `Xenova/modnet`),
  u2netp (4.6 MB, salient object, rembg release), IS-Net general use
  (179 MB, salient object, rembg release, only when asked).
- **The pipeline** (`tekartik_bg_removal`, pure Dart, in isolates): for
  each model the photo is resized and normalized into a tensor, the model
  runs (native), and its output is resized back to a mask the size of the
  photo. The combination keeps the person mask and the salient regions
  that touch it.
- **Release builds** need the R8 rules of `android/app/proguard-rules.pro`
  (skill `tekartik-bg-removal-mlkit-android-setup`).

### Pixel 7a, one 1600x1200 photo

Release build, Android 17, ONNX on the CPU provider, 2026-10-28
(`dart run tool/bench.dart android --timing 1600x1200`). Median of 5 runs
after a warm-up, in ms:

| Method | Models | Combine | Total | Fixtures: mean IoU, bags ≥ 0.8 |
|---|---|---|---|---|
| `mlkit` | 926 | - | **927** | **0.97, 7/7** |
| `mlkit+modnet` | 926 + 839 | 146 | 1,923 | 0.94, 7/7 |
| `u2netp` | 797 | - | 778 | 0.71, 5/7 |
| `modnet` | 839 | - | 838 | 0.84, 6/7 |
| `modnet+u2netp` | 839 + 797 | 149 | 1,792 | 0.87, 6/7 |
| `modnet+isnet` | 839 + 5,041 | 147 | 6,038 | 0.88, 7/7 |

- A model's time is: building its input, the inference, then resizing its
  output to a 1600x1200 mask. MODNet runs at 672x512, u2netp at 320x320,
  IS-Net at 1024x1024. For ML Kit, nearly all of it (875 ms) is the call:
  ML Kit reads the JPEG itself, and its 1.9 million confidence values come
  back through the platform channel.
- Not counted above: decoding the JPEG (105 ms) and encoding the cut-out
  as PNG with `package:image` (938 ms).
- The ONNX inference times include copying the tensors through the plugin.
- Each column is a median of its own, so a total can be a little below
  its model's time.
- ML Kit's foreground mask holds every subject: another person in the
  photo stays in the cut-out. Separating them needs the per-subject masks,
  which crash (see Known).

### Linux, one 1600x1200 photo

i9-12900K, CPU, release build: MODNet + u2netp 0.59 s, MODNet + IS-Net
1.26 s; the cut-out as PNG 0.31 s (2.3 MB), as WebP q80 1.0 s (168 KB).

## Run the bench

```sh
# The phone on adb (release build for its abi, report + screenshot):
dart run tool/bench.dart android
dart run tool/bench.dart android --provider XNNPACK --threads 4
dart run tool/bench.dart android --methods mlkit,modnet+u2netp,modnet+isnet
# Two devices on adb: --device <serial> (or ANDROID_SERIAL).
# A timing pass on one 1600x1200 photo after the fixtures:
dart run tool/bench.dart android --timing 1600x1200
# Fine tuning: the pipeline options as json (BgRemovalOptions).
dart run tool/bench.dart android --options '{"minRegion":0.005,"feather":1}'

# Linux, headless (xvfb-run):
dart run tool/bench.dart linux --models ~/path/to/onnx/files
```

The reports go to `.local/bench/<stamp>_<target>.md`, together with a
screenshot on Android. The app also writes `report.md`, `report.json` and
every mask (`masks/<method>/<fixture>.png`) to its support folder:
`~/.local/share/com.tekartik.bg_removal_bench/bench/` on Linux.

By hand: `flutter run -t lib/main_bench.dart`, choose the methods and the
provider, then press Run. The defines (`BENCH_AUTORUN`, `BENCH_METHODS`,
`BENCH_PROVIDER`, `BENCH_THREADS`, `BENCH_TIMING`, `BENCH_OPTIONS`) are in
`bg_removal_bench_common`'s `bench_page.dart`; `BENCH_EXIT` and
`BENCH_MLKIT_RETRY` in `lib/src/bench_setup.dart`.

## Known

- **ML Kit crashes the app when asked for each subject's mask**
  (`enableMultipleSubjects` with a confidence mask). It is a SIGSEGV in a
  `memcpy` of the Play services module, so the app dies, with every kind of
  input (file, bitmap, NV21): Pixel 7a, Android 17, module 264131100400.
  The foreground mask alone works. `dart run tool/mlkit_probe.dart` tries
  each way again (it restarts the app after each crash) and writes
  `.local/bench/<stamp>_mlkit_probe.md`.
- **The engine remembers an ML Kit crash.** Each ML Kit call is written to
  a guard file first. If the app dies, the next run skips ML Kit and says
  why. `--dart-define=BENCH_MLKIT_RETRY=true` tries again.
- **ML Kit also crashed on an x86_64 emulator** (SIGSEGV in its
  `drishti_gl_runn` thread), with the per-subject masks asked then: test on
  an arm64 phone.
- **The ML Kit module is not there right after an `adb install`.** The
  manifest asks Play services for it, but the first calls fail with
  "Waiting for the subject segmentation optional module to be downloaded"
  until the download ends. The engine waits for it in `prepare`, for 3
  minutes at most.
- **The debug APK is big** (about 110 MB, every ABI of onnxruntime): an
  emulator needs a few GB of free data space.

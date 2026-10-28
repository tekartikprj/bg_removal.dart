# bg_removal_bench_web

The bench in the browser: the web engine on the fixtures, scored against the
reference masks, plus a timing pass. The web version of `../bg_removal_bench`,
but independent of it: the two share `../bg_removal_bench_common`, never
each other's dependencies.

The web engine is `tekartik_bg_removal_web`
(`../../packages/bg_removal_web`): MODNet + u2netp (or IS-Net) on
onnxruntime-web 1.30.0. ML Kit is Android only.

- The engine loads onnxruntime-web itself from jsdelivr (no change to
  `web/index.html`): `ort.wasm.min.js` (14 MB of wasm), or `ort.min.js` for
  WebGPU (28 MB).
- The models come from Hugging Face (MODNet: `Xenova/modnet`, u2netp and
  IS-Net: `tomjackson2023/rembg`, the rembg files, same sha256: GitHub
  release files cannot be fetched by a page, no CORS). They are checked by
  size and sha256 (WebCrypto) and kept in the browser (Cache API). In
  production, host them with the app (`BENCH_MODELS_URL`, `BgWebModelLoader`).
- wasm threads need a cross-origin isolated page: serve it with
  `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: credentialless`.

## Run the bench

```sh
# Headless Chrome, report in .local/bench/<stamp>_web.md:
dart run tool/bench.dart
dart run tool/bench.dart --timing 1600x1200
dart run tool/bench.dart --wasm                 # dart2wasm instead of dart2js
dart run tool/bench.dart --provider webgpu
dart run tool/bench.dart --models ~/path/to/onnx/files   # no download
dart run tool/bench.dart --options '{"feather":1}'
dart run tool/bench.dart --no-isolation         # single-threaded wasm
```

The tool builds the app (`lib/main_bench.dart`), serves it with the
cross-origin isolation headers, runs Chrome headless, and receives the
report (the page POSTs it to `/report`). Chrome's log goes to
`.local/bench/<stamp>_web_chrome.log`.

By hand: `flutter run -d chrome -t lib/main_bench.dart`, choose the methods,
then Run (the Flutter dev server is not cross-origin isolated: one wasm
thread).

## Measured (2026-10-28, i9-12900K, Chrome 155 headless)

The scores are the native ones (same models, same pipeline): MODNet +
u2netp mean IoU 0.87, 6 bags of 7.

One 1600x1200 photo, median of 5, cross-origin isolated:

| | dart2js | dart2wasm |
|---|---|---|
| MODNet + u2netp, in all | 759 ms | 791 ms |
| JPEG decode | 40 ms | 49 ms |
| PNG of the cut-out (2.2 MB) | 749 ms | 1,260 ms |
| WebP q80 of the cut-out (169 KB) | 2,834 ms | 2,166 ms |

The models themselves (onnxruntime-web, wasm): MODNet 364 ms, u2netp
273 ms. dart2wasm is no faster overall; the encoders are the slow part.

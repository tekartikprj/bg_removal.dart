# bg_removal_bench_common

Shared by the two bench apps: `../bg_removal_bench` (Android, Linux) and
`../bg_removal_bench_web` (web). The apps do not depend on each other, so
that the web's dependencies never hold back Android's (and the reverse);
they share this package instead.

It depends on no engine: only `tekartik_bg_removal` and
`tekartik_bg_removal_flutter` (`../../packages/`). Each app gives its engines
and its platform side through a `BenchSetup`:

```dart
BenchPage(
  setup: BenchSetup(
    models: {'modnet', 'u2netp'},          // the engines this app has
    providers: ['CPU', 'XNNPACK'],         // the first is the default
    engines: (provider, threads) => {...}, // id -> BgRemover
    host: (stamp) async => MyHost(),       // files or not, where the report goes
  ),
);
```

## The bench

- `BenchRunner`: every method on every fixture, scored against the
  reference masks (IoU, bag score, extra), then an optional timing pass on
  one photo of a given size through the public API (`bgRemoveBackground`,
  PNG and WebP encoding included).
- `BenchPage`: the method chips, provider and threads, the report and the
  thumbnails (magenta and green behind the cut-out: a lost bag shows at
  once). It reads the defines `BENCH_AUTORUN`, `BENCH_METHODS`,
  `BENCH_PROVIDER`, `BENCH_THREADS`, `BENCH_TIMING` (`1600x1200`) and
  `BENCH_OPTIONS` (the `BgRemovalOptions` json, to fine tune).
- `BenchHost`: what a platform does with a run (temporary files for ML
  Kit, the report and masks, where the report is published).

### Methods

| Method | Engines | Where |
|---|---|---|
| `mlkit` | ML Kit Subject Segmentation, foreground mask (every subject) | Android |
| `mlkit+modnet` | the MODNet person + the ML Kit regions touching it | Android |
| `u2netp` | u2netp alone (salient, 4.6 MB) | everywhere |
| `modnet` | MODNet fp16 alone (person matting, 13 MB) | everywhere |
| `modnet+u2netp` | the person + the salient regions touching it | everywhere |
| `modnet+isnet` | the same with IS-Net (179 MB) | everywhere, off by default |

## Fixtures

`assets/fixtures/`: 7 Wikimedia Commons photos with their reference masks
and the boxes inside their bags (`fixtures.json`). Authors and licences are
in `ATTRIBUTION.md` (CC BY, CC BY-SA, public domain): they are not under the
licence of the code. To add one: `<id>.jpg` + `<id>_ref.png` (white = kept),
plus a line in `fixtures.json`.

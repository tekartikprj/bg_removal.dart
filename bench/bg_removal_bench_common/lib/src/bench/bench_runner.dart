import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tekartik_bg_removal/score.dart';
import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';

import 'bench_host.dart';
import 'bench_method.dart';
import 'thumbnail.dart';

/// A fixture photo with its reference mask.
class BenchFixture {
  /// Id, also the asset names (`<id>.jpg`, `<id>_ref.png`).
  final String id;

  /// What makes it hard.
  final String hard;

  /// Boxes inside the bags.
  final List<BgBox> bags;

  /// A fixture.
  BenchFixture(this.id, this.hard, this.bags);
}

/// The asset folder of the fixtures.
const benchFixturesAssetDir =
    'packages/bg_removal_bench_common/assets/fixtures';

/// Reads `fixtures.json`.
Future<List<BenchFixture>> benchLoadFixtures(AssetBundle bundle) async {
  final data = await bundle.load('$benchFixturesAssetDir/fixtures.json');
  final json =
      jsonDecode(utf8.decode(data.buffer.asUint8List()))
          as Map<String, Object?>;
  return [
    for (final f in (json['fixtures'] as List).cast<Map<String, Object?>>())
      BenchFixture(f['id'] as String, f['hard'] as String, [
        for (final b in f['bags'] as List) BgBox.fromList(b as List),
      ]),
  ];
}

/// The bytes of a fixture asset (`<id>.jpg`, `<id>_ref.png`).
Future<Uint8List> benchFixtureBytes(AssetBundle bundle, String name) async =>
    (await bundle.load('$benchFixturesAssetDir/$name')).buffer.asUint8List();

/// One method on one fixture.
class BenchCell {
  /// Method id ('original' for the photo itself).
  final String method;

  /// Fixture id.
  final String fixture;

  /// The score, null for the original.
  final BgScore? score;

  /// The engines' time plus the pipeline.
  final Duration time;

  /// A small cut-out to show.
  final BgRgbaImage thumbnail;

  /// A cell.
  BenchCell({
    required this.method,
    required this.fixture,
    required this.score,
    required this.time,
    required this.thumbnail,
  });
}

/// What one engine did over the fixtures.
class BenchModelStat {
  /// The engine id.
  final String id;

  /// What it is.
  final String description;

  /// Inference times, in fixture order.
  final infer = <Duration>[];

  /// Total times (input, inference, output).
  final total = <Duration>[];

  /// Max resident memory of the process after the engine ran, MB.
  int? maxRssMb;

  /// Why it did not run.
  String? error;

  /// Errors per fixture.
  final errors = <String, String>{};

  /// A stat.
  BenchModelStat(this.id, this.description);
}

/// The steps of one engine: `<id>.prepare`, `<id>.infer`, `<id>.post`.
typedef BenchSteps = ({
  List<Duration> prepare,
  List<Duration> infer,
  List<Duration> post,
});

/// Where the time goes for one photo of a given size, through the public
/// API (`bgRemoveBackground`), median of the runs.
class BenchTiming {
  /// The photo size.
  final int width;

  /// The photo size.
  final int height;

  /// The fixture it was cropped from.
  final String fixture;

  /// Runs after the warm-up.
  final int runs;

  /// Decoding the JPEG (`dart:ui`).
  final decode = <Duration>[];

  /// Per model.
  final models = <String, BenchSteps>{};

  /// Per method: the engine(s), the mask steps, the cut-out, in all.
  final methods =
      <
        String,
        ({
          List<Duration> segment,
          List<Duration> mask,
          List<Duration> cutout,
          List<Duration> total,
        })
      >{};

  /// The cut-out as PNG (`package:image`).
  final png = <Duration>[];

  /// The cut-out as WebP (`tekartik_app_image_webp`, quality 80).
  final webp = <Duration>[];

  /// The WebP size, bytes.
  int webpSize = 0;

  /// The PNG size, bytes.
  int pngSize = 0;

  /// A timing.
  BenchTiming(this.width, this.height, this.fixture, this.runs);
}

/// A bench run.
class BenchReport {
  /// When it started.
  final DateTime start = DateTime.now();

  /// The device.
  final String platform;

  /// The options of the pipeline.
  final BgRemovalOptions options;

  /// The engines.
  final models = <String, BenchModelStat>{};

  /// The methods run.
  final methods = <String>[];

  /// The fixtures.
  final fixtures = <BenchFixture>[];

  /// The cells.
  final cells = <BenchCell>[];

  /// Where the masks and the report were written, if anywhere.
  String? outDir;

  /// The timing pass, when asked.
  BenchTiming? timing;

  /// A report.
  BenchReport({required this.platform, required this.options});

  /// The cell of [method] on [fixture].
  BenchCell? cell(String method, String fixture) {
    for (final c in cells) {
      if (c.method == method && c.fixture == fixture) {
        return c;
      }
    }
    return null;
  }

  /// The report as markdown.
  String toMarkdown() {
    String ms(Duration d) => '${d.inMilliseconds}';
    String pc(double v) => v.toStringAsFixed(2);
    Duration median(List<Duration> list) {
      if (list.isEmpty) return Duration.zero;
      final sorted = [...list]..sort();
      return sorted[sorted.length ~/ 2];
    }

    String modelLine(BenchModelStat m) {
      if (m.error != null) {
        return '| ${m.id} | ${m.description} | ${m.error} | | | |';
      }
      final first = m.total.isEmpty ? '' : ms(m.total.first);
      return '| ${m.id} | ${m.description} | $first | '
          '${ms(median(m.infer))} | ${ms(median(m.total))} | '
          '${m.maxRssMb ?? '-'} |';
    }

    final defaultOptions =
        jsonEncode(options.toJson()) ==
        jsonEncode(const BgRemovalOptions().toJson());
    const legend =
        'Per fixture: IoU / bag score (mean alpha in the bag boxes) / extra '
        '(background kept, share of the reference).';
    final title = start.toIso8601String().substring(0, 19);
    final lines = <String>[
      '# Picture background removal bench, $title',
      '',
      platform,
      '',
      if (!defaultOptions) ...[
        'Options: `${jsonEncode(options.toJson())}`',
        '',
      ],
      '| Engine | Description | First (ms) | Median infer (ms) | Median total (ms) | Max RSS (MB) |',
      '|---|---|---|---|---|---|',
      for (final m in models.values) modelLine(m),
      '',
      legend,
      '',
      '| Method | ${fixtures.map((f) => f.id).join(' | ')} | Mean IoU | Bags ≥ 0.8 | Median time (ms) |',
      '|---|${fixtures.map((_) => '---|').join()}---|---|---|',
    ];
    for (final method in methods) {
      final row = <String>[];
      var iouSum = 0.0, n = 0, bagsOk = 0, bagsN = 0;
      final times = <Duration>[];
      for (final f in fixtures) {
        final c = cell(method, f.id);
        final s = c?.score;
        if (c == null || s == null) {
          row.add('-');
          continue;
        }
        iouSum += s.iou;
        n++;
        times.add(c.time);
        final bag = s.bag;
        if (bag != null) {
          bagsN++;
          if (bag >= 0.8) bagsOk++;
        }
        row.add(
          '${pc(s.iou)} / ${bag == null ? '-' : pc(bag)} / ${pc(s.extra)}',
        );
      }
      lines.add(
        '| $method | ${row.join(' | ')} | '
        '${n == 0 ? '-' : pc(iouSum / n)} | $bagsOk/$bagsN | '
        '${ms(median(times))} |',
      );
    }
    final errors = [
      for (final m in models.values)
        for (final e in m.errors.entries) '- ${m.id} ${e.key}: ${e.value}',
    ];
    if (errors.isNotEmpty) {
      lines
        ..add('')
        ..addAll(errors);
    }
    final timing = this.timing;
    if (timing != null) {
      String modelRow(String id, BenchSteps m) {
        final (prepare, infer, post) = (
          median(m.prepare),
          median(m.infer),
          median(m.post),
        );
        return '| $id | ${ms(prepare)} | ${ms(infer)} | ${ms(post)} | '
            '${ms(prepare + infer + post)} |';
      }

      String methodRow(
        String id,
        ({
          List<Duration> segment,
          List<Duration> mask,
          List<Duration> cutout,
          List<Duration> total,
        })
        m,
      ) =>
          '| $id | ${ms(median(m.segment))} | ${ms(median(m.mask))} | '
          '${ms(median(m.cutout))} | ${ms(median(m.total))} |';
      final pngKb = timing.pngSize ~/ 1024;
      final webp =
          '${ms(median(timing.webp))} ms, ${timing.webpSize ~/ 1024} KB';
      final about =
          'Median of ${timing.runs} runs after a warm-up, ${timing.fixture} '
          'cropped and resized, through `bgRemoveBackground`, in ms.';
      lines.addAll([
        '',
        '## Timing, one ${timing.width}x${timing.height} photo',
        '',
        about,
        '',
        '| Model | Tensor | Inference | Mask | Total |',
        '|---|---|---|---|---|',
        for (final e in timing.models.entries) modelRow(e.key, e.value),
        '',
        '| Method | Engines | Mask steps | Cut-out | Total |',
        '|---|---|---|---|---|',
        for (final MapEntry(:key, :value) in timing.methods.entries)
          methodRow(key, value),
        '',
        '- JPEG decode: ${ms(median(timing.decode))} ms',
        '- Cut-out as PNG: ${ms(median(timing.png))} ms, $pngKb KB',
        '- Cut-out as WebP (q80, lossless alpha): $webp',
      ]);
    }
    return lines.join('\n');
  }

  /// The report as json.
  Map<String, Object?> toJson() => {
    'start': start.toIso8601String(),
    'platform': platform,
    'options': options.toJson(),
    'models': {
      for (final m in models.values)
        m.id: {
          'description': m.description,
          'error': m.error,
          'inferMs': m.infer.map((d) => d.inMilliseconds).toList(),
          'totalMs': m.total.map((d) => d.inMilliseconds).toList(),
          'maxRssMb': m.maxRssMb,
          'errors': m.errors,
        },
    },
    'cells': [
      for (final c in cells)
        if (c.score != null)
          {
            'method': c.method,
            'fixture': c.fixture,
            'timeMs': c.time.inMilliseconds,
            ...c.score!.toJson(),
          },
    ],
  };
}

/// Runs [methods] over [fixtures] with [engines].
class BenchRunner {
  /// The engines, by id (`mlkit`, `modnet`, `u2netp`, `isnet`).
  final Map<String, BgRemover> engines;

  /// The methods to run (those whose engines fail are skipped).
  final List<BenchMethod> methods;

  /// The fixtures.
  final List<BenchFixture> fixtures;

  /// The pipeline options.
  final BgRemovalOptions options;

  /// Assets.
  final AssetBundle bundle;

  /// The platform side.
  final BenchHost host;

  /// Progress.
  final void Function(String status)? onStatus;

  /// Each cell as it is ready.
  final void Function(BenchCell cell)? onCell;

  /// Thumbnail height.
  final int thumbnailHeight;

  /// The size of the timing pass photo, null for no timing pass.
  final (int, int)? timingSize;

  /// The fixture the timing photo is cropped from.
  final String timingFixture;

  /// Timed runs, after a warm-up.
  final int timingRuns;

  /// A runner.
  BenchRunner({
    required this.engines,
    required this.methods,
    required this.fixtures,
    required this.bundle,
    required this.host,
    this.options = const BgRemovalOptions(),
    this.onStatus,
    this.onCell,
    this.thumbnailHeight = 160,
    this.timingSize,
    this.timingFixture = 'old_couple',
    this.timingRuns = 5,
  });

  /// Runs the bench; the host saves `report.md`, `report.json` and the
  /// masks.
  Future<BenchReport> run() async {
    final report = BenchReport(platform: host.platform, options: options)
      ..fixtures.addAll(fixtures)
      ..outDir = host.outDir;
    final needed = {for (final m in methods) ...m.models};
    final ready = <String>{};
    for (final id in needed) {
      final engine = engines[id];
      final stat = BenchModelStat(id, engine?.name ?? id);
      report.models[id] = stat;
      if (engine == null ||
          await engine.getStatus() == BgRemoverStatus.unsupported) {
        stat.error = 'not supported here';
        continue;
      }
      try {
        await engine.prepare(onStatus: onStatus);
        ready.add(id);
      } catch (e) {
        stat.error = '$e';
      }
    }
    final runnable = [
      for (final m in methods)
        if (m.models.every(ready.contains)) m,
    ];
    report.methods.addAll(runnable.map((m) => m.id));

    for (final fixture in fixtures) {
      onStatus?.call('${fixture.id}: decoding');
      final bytes = await benchFixtureBytes(bundle, '${fixture.id}.jpg');
      final filePath = await host.tempFile('${fixture.id}.jpg', bytes);
      final image = await bgDecodeImage(bytes);
      final reference = await _referenceMask(
        await bgDecodeImage(
          await benchFixtureBytes(bundle, '${fixture.id}_ref.png'),
        ),
      );
      final photo = BgPhoto(image, filePath: filePath);
      final height = thumbnailHeight;
      _addCell(
        report,
        BenchCell(
          method: 'original',
          fixture: fixture.id,
          score: null,
          time: Duration.zero,
          thumbnail: await _thumbnail(image, height),
        ),
      );

      final masks = <String, BgMask>{};
      final totals = <String, Duration>{};
      for (final id in ready) {
        onStatus?.call('${fixture.id}: $id');
        final stat = report.models[id]!;
        try {
          final result = await engines[id]!.segment(photo);
          masks[id] = (result.person ?? result.foreground)!;
          final steps = _steps(result.timings);
          totals[id] = steps.total;
          stat.infer.add(steps.infer);
          stat.total.add(steps.total);
        } catch (e) {
          stat.errors[fixture.id] = '$e';
        }
        final rss = host.maxRssMb;
        if (rss != null && rss > (stat.maxRssMb ?? 0)) stat.maxRssMb = rss;
      }

      for (final method in runnable) {
        if (!method.models.every(masks.containsKey)) {
          continue;
        }
        onStatus?.call('${fixture.id}: ${method.id}');
        final (:combine, :score, :thumbnail, :png) = await _runMethod(
          method,
          masks,
          options,
          image,
          reference,
          fixture.bags,
          height,
        );
        await host.save('masks/${method.id}/${fixture.id}.png', png);
        var time = combine;
        for (final m in method.models) {
          time += totals[m]!;
        }
        _addCell(
          report,
          BenchCell(
            method: method.id,
            fixture: fixture.id,
            score: score,
            time: time,
            thumbnail: thumbnail,
          ),
        );
      }
    }
    final timingSize = this.timingSize;
    if (timingSize != null && runnable.isNotEmpty) {
      report.timing = await _timing(timingSize, runnable);
    }
    for (final id in ready) {
      await engines[id]!.close();
    }
    await host.save(
      'report.md',
      Uint8List.fromList(utf8.encode('${report.toMarkdown()}\n')),
    );
    await host.save(
      'report.json',
      Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent(' ').convert(report.toJson())),
      ),
    );
    onStatus?.call('done');
    return report;
  }

  Future<BenchTiming> _timing(
    (int, int) size,
    List<BenchMethod> runnable,
  ) async {
    final (width, height) = size;
    final timing = BenchTiming(width, height, timingFixture, timingRuns);
    onStatus?.call('timing ${width}x$height');
    final source = await bgDecodeImage(
      await benchFixtureBytes(bundle, '$timingFixture.jpg'),
    );
    final jpeg = await _cropJpeg(source, width, height);
    final filePath = await host.tempFile('timing_${width}x$height.jpg', jpeg);
    for (var run = 0; run <= timingRuns; run++) {
      // Run 0 is the warm-up.
      final record = run > 0;
      onStatus?.call('timing ${width}x$height: run $run/$timingRuns');
      final sw = Stopwatch()..start();
      final photo = BgPhoto(await bgDecodeImage(jpeg), filePath: filePath);
      if (record) timing.decode.add(sw.elapsed);
      BgRemovalResult? last;
      for (final method in runnable) {
        final result = await bgRemoveBackground(
          method.remover(engines),
          photo,
          options: options,
          run: bgRunInIsolate,
        );
        last = result;
        if (!record) continue;
        final t = result.timings;
        for (final id in method.models) {
          final m = timing.models.putIfAbsent(
            id,
            () => (prepare: <Duration>[], infer: <Duration>[], post: []),
          );
          final steps = _steps(t, only: id);
          m.prepare.add(steps.prepare);
          m.infer.add(steps.infer);
          m.post.add(steps.post);
        }
        final segment = t['segment']!;
        final mask = t['mask']!;
        final cutout = t['cutout']!;
        final row = timing.methods.putIfAbsent(
          method.id,
          () => (segment: [], mask: [], cutout: [], total: <Duration>[]),
        );
        row.segment.add(segment);
        row.mask.add(mask);
        row.cutout.add(cutout);
        row.total.add(segment + mask + cutout + (t['downscale'] ?? .zero));
      }
      if (last != null) {
        final (:png, :pngSize, :webp, :webpSize) = await _encode(last.cutout);
        if (record) {
          timing
            ..png.add(png)
            ..webp.add(webp)
            ..pngSize = pngSize
            ..webpSize = webpSize;
        }
      }
    }
    return timing;
  }

  void _addCell(BenchReport report, BenchCell cell) {
    report.cells.add(cell);
    onCell?.call(cell);
  }
}

/// The engine steps of [timings] (`<id>.prepare|infer|post`), of the model
/// [only] or of all.
({Duration prepare, Duration infer, Duration post, Duration total}) _steps(
  Map<String, Duration> timings, {
  String? only,
}) {
  var prepare = Duration.zero, infer = Duration.zero, post = Duration.zero;
  for (final MapEntry(:key, :value) in timings.entries) {
    final dot = key.lastIndexOf('.');
    if (dot < 0 || (only != null && key.substring(0, dot) != only)) continue;
    switch (key.substring(dot + 1)) {
      case 'prepare':
        prepare += value;
      case 'infer':
        infer += value;
      case 'post':
        post += value;
    }
  }
  return (
    prepare: prepare,
    infer: infer,
    post: post,
    total: prepare + infer + post,
  );
}

// The isolate work lives in top-level functions so that the closures only
// capture their arguments (never the runner, its bundle or its callbacks).

Future<BgMask> _referenceMask(BgRgbaImage refImage) => bgRunInIsolate(() {
  final alpha = Uint8List(refImage.width * refImage.height);
  for (var i = 0; i < alpha.length; i++) {
    alpha[i] = refImage.rgba[i * 4];
  }
  return BgMask(refImage.width, refImage.height, alpha);
});

Future<BgRgbaImage> _thumbnail(BgRgbaImage image, int height) =>
    bgRunInIsolate(() => benchThumbnail(image, null, height));

Future<
  ({Duration combine, BgScore score, BgRgbaImage thumbnail, Uint8List png})
>
_runMethod(
  BenchMethod method,
  Map<String, BgMask> masks,
  BgRemovalOptions options,
  BgRgbaImage image,
  BgMask reference,
  List<BgBox> bags,
  int height,
) => bgRunInIsolate(() {
  final sw = Stopwatch()..start();
  final mask = method.mask(masks, options);
  final combine = sw.elapsed;
  return (
    combine: combine,
    score: bgScore(mask, reference, bags: bags),
    thumbnail: benchThumbnail(image, mask, height),
    png: bgEncodeMaskPng(mask),
  );
});

Future<Uint8List> _cropJpeg(BgRgbaImage source, int width, int height) =>
    bgRunInIsolate(() {
      // Center crop to the aspect ratio, then resize.
      final image = img.Image.fromBytes(
        width: source.width,
        height: source.height,
        bytes: Uint8List.fromList(source.rgba).buffer,
        numChannels: 4,
      );
      final scale = max(width / image.width, height / image.height);
      final cropWidth = (width / scale).round();
      final cropHeight = (height / scale).round();
      final cropped = img.copyCrop(
        image,
        x: (image.width - cropWidth) ~/ 2,
        y: (image.height - cropHeight) ~/ 2,
        width: cropWidth,
        height: cropHeight,
      );
      return img.encodeJpg(
        img.copyResize(
          cropped,
          width: width,
          height: height,
          interpolation: img.Interpolation.cubic,
        ),
        quality: 90,
      );
    });

Future<({Duration png, int pngSize, Duration webp, int webpSize})> _encode(
  BgRgbaImage cutout,
) => bgRunInIsolate(() {
  final sw = Stopwatch()..start();
  final png = bgEncodePng(cutout);
  final pngTime = sw.elapsed;
  sw.reset();
  final webp = bgEncodeWebp(cutout);
  return (
    png: pngTime,
    pngSize: png.length,
    webp: sw.elapsed,
    webpSize: webp.length,
  );
});

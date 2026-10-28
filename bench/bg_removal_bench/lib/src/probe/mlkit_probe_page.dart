import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bg_removal_bench_common/bg_removal_bench_common.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';

/// The build of the probe (`--dart-define=PROBE_BUILD=<stamp>`): a new build
/// starts the cases again.
const probeBuild = String.fromEnvironment('PROBE_BUILD', defaultValue: 'dev');

/// How the image goes to ML Kit.
enum MlKitProbeInput {
  /// `InputImage.fromFilePath` on the fixture JPEG (what the bench does).
  file,

  /// `InputImage.fromBitmap`: raw RGBA, an ARGB_8888 Bitmap on Android.
  bitmap,

  /// `InputImage.fromBytes` in NV21 (the camera format).
  nv21,

  /// A blank 512 x 512 PNG file (the bench warm-up).
  blankPng,
}

/// What ML Kit is asked to return.
enum MlKitProbeOutput {
  /// The foreground confidence mask only.
  foregroundMask,

  /// The foreground bitmap only (the documented default).
  foregroundBitmap,

  /// The foreground mask and every subject's mask (the bench options).
  subjectMasks,
}

/// One way to call ML Kit.
class MlKitProbeCase {
  /// The input.
  final MlKitProbeInput input;

  /// The output.
  final MlKitProbeOutput output;

  /// A case.
  const MlKitProbeCase(this.input, this.output);

  /// Id in the results.
  String get id => '${input.name}/${output.name}';
}

/// The cases, the most likely to work first.
const mlKitProbeCases = [
  MlKitProbeCase(MlKitProbeInput.bitmap, MlKitProbeOutput.foregroundMask),
  MlKitProbeCase(MlKitProbeInput.nv21, MlKitProbeOutput.foregroundMask),
  MlKitProbeCase(MlKitProbeInput.file, MlKitProbeOutput.foregroundMask),
  MlKitProbeCase(MlKitProbeInput.file, MlKitProbeOutput.foregroundBitmap),
  MlKitProbeCase(MlKitProbeInput.bitmap, MlKitProbeOutput.subjectMasks),
  MlKitProbeCase(MlKitProbeInput.file, MlKitProbeOutput.subjectMasks),
  MlKitProbeCase(MlKitProbeInput.blankPng, MlKitProbeOutput.subjectMasks),
];

/// Tries ML Kit Subject Segmentation in several ways, one case at a time.
///
/// A native crash kills the app: each case is written to a progress file
/// before it runs, so the next start records it as a crash and goes on
/// (`tool/mlkit_probe.dart` restarts the app until it prints `PROBE| done`).
class MlKitProbePage extends StatefulWidget {
  /// The probe page.
  const MlKitProbePage({super.key});

  @override
  State<MlKitProbePage> createState() => _MlKitProbePageState();
}

class _MlKitProbePageState extends State<MlKitProbePage> {
  final _lines = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  void _log(String line) {
    // Greppable in logcat.
    // ignore: avoid_print
    print('PROBE| $line');
    if (mounted) setState(() => _lines.add(line));
  }

  Future<void> _run() async {
    final support = await getApplicationSupportDirectory();
    final file = File(join(support.path, 'mlkit_probe.json'));
    var state = <String, Object?>{};
    if (file.existsSync()) {
      state = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    }
    if (state['build'] != probeBuild) {
      state = {'build': probeBuild, 'results': <String, Object?>{}};
    }
    final results = (state['results'] as Map).cast<String, Object?>();
    final attempt = state['attempt'] as String?;
    if (attempt != null && !results.containsKey(attempt)) {
      results[attempt] = 'CRASH (the app died)';
      _log('$attempt: CRASH (the app died)');
    }
    Future<void> save() => file.writeAsString(jsonEncode(state), flush: true);

    final bytes = (await rootBundle.load('$benchFixturesAssetDir/street.jpg'))
        .buffer
        .asUint8List();
    final tmp = await getTemporaryDirectory();
    final jpg = File(join(tmp.path, 'probe_street.jpg'));
    await jpg.writeAsBytes(bytes);
    final blank = File(join(tmp.path, 'probe_blank.png'));
    await blank.writeAsBytes(img.encodePng(img.Image(width: 512, height: 512)));
    final image = await bgDecodeImage(bytes);

    for (final c in mlKitProbeCases) {
      if (results.containsKey(c.id)) continue;
      state['attempt'] = c.id;
      await save();
      _log('${c.id}: running');
      String result;
      try {
        result = await _case(c, image, jpg.path, blank.path);
      } catch (e) {
        result = 'error: $e';
      }
      results[c.id] = result;
      state['attempt'] = null;
      await save();
      _log('${c.id}: $result');
    }
    _log('results (build $probeBuild):');
    for (final c in mlKitProbeCases) {
      _log('- ${c.id}: ${results[c.id]}');
    }
    _log('done');
  }

  Future<String> _case(
    MlKitProbeCase c,
    BgRgbaImage image,
    String jpgPath,
    String blankPath,
  ) async {
    final input = switch (c.input) {
      MlKitProbeInput.file => InputImage.fromFilePath(jpgPath),
      MlKitProbeInput.blankPng => InputImage.fromFilePath(blankPath),
      MlKitProbeInput.bitmap => InputImage.fromBitmap(
        bitmap: image.rgba,
        width: image.width,
        height: image.height,
      ),
      MlKitProbeInput.nv21 => InputImage.fromBytes(
        bytes: _nv21(image),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      ),
    };
    final segmenter = SubjectSegmenter(
      options: SubjectSegmenterOptions(
        enableForegroundBitmap: c.output == MlKitProbeOutput.foregroundBitmap,
        enableForegroundConfidenceMask:
            c.output != MlKitProbeOutput.foregroundBitmap,
        enableMultipleSubjects: SubjectResultOptions(
          enableConfidenceMask: c.output == MlKitProbeOutput.subjectMasks,
          enableSubjectBitmap: false,
        ),
      ),
    );
    try {
      final times = <int>[];
      SubjectSegmentationResult? result;
      // Twice: the first call loads the model.
      for (var i = 0; i < 2; i++) {
        final sw = Stopwatch()..start();
        result = await _process(segmenter, input);
        times.add(sw.elapsedMilliseconds);
      }
      final mask = result!.foregroundConfidenceMask;
      final mean = mask == null || mask.isEmpty
          ? null
          : mask.reduce((a, b) => a + b) / mask.length;
      return 'ok ${times.join(' + ')} ms'
          '${mask == null ? '' : ', mask ${mask.length} values, mean ${mean!.toStringAsFixed(2)}'}'
          '${result.foregroundBitmap == null ? '' : ', bitmap ${result.foregroundBitmap!.length} bytes'}'
          ', ${result.subjects.length} subjects';
    } finally {
      await segmenter.close();
    }
  }

  /// Waits for the Play services module on the first call (3 minutes at
  /// most), like the bench.
  Future<SubjectSegmentationResult> _process(
    SubjectSegmenter segmenter,
    InputImage input,
  ) async {
    final sw = Stopwatch()..start();
    while (true) {
      try {
        return await segmenter.processImage(input);
      } on PlatformException catch (e) {
        if (!'${e.message}'.contains('to be downloaded') ||
            sw.elapsed > const Duration(minutes: 3)) {
          rethrow;
        }
        _log(
          'waiting for the Play services module (${sw.elapsed.inSeconds} s)',
        );
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ML Kit probe')),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final line in _lines)
          Text(line, style: const TextStyle(fontFamily: 'monospace')),
      ],
    ),
  );
}

/// RGBA to NV21 (BT.601, full plane of Y then interleaved V/U at half
/// resolution). Width and height must be even.
Uint8List _nv21(BgRgbaImage image) {
  final w = image.width;
  final h = image.height;
  final rgba = image.rgba;
  final out = Uint8List(w * h + w * h ~/ 2);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      out[y * w + x] = (((66 * r + 129 * g + 25 * b + 128) >> 8) + 16).clamp(
        0,
        255,
      );
      if (y.isEven && x.isEven) {
        final uv = w * h + (y ~/ 2) * w + x;
        out[uv] = (((112 * r - 94 * g - 18 * b + 128) >> 8) + 128).clamp(
          0,
          255,
        );
        out[uv + 1] = (((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128).clamp(
          0,
          255,
        );
      }
    }
  }
  return out;
}

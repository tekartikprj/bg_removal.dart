import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tekartik_bg_removal/bg_removal.dart';

/// The ML Kit engine: Subject Segmentation (Android only, its model comes
/// from Play services). It gives the foreground: every subject, the person
/// and what they carry (no person mask on its own).
///
/// Measured on a Pixel 7a: the best of the engines (IoU 0.97, every bag
/// kept on the fixtures), 0.9 s for a 1600x1200 photo.
///
/// - It never asks ML Kit for each subject's own mask: that crashes the
///   app in native code (SIGSEGV in the Play services module, Android 17).
/// - A native crash kills the app, so each call is written to a guard file
///   first: after a crash, [getStatus] says unsupported and [prepare]
///   throws, until [clearCrash] (or [retryAfterCrash]). With
///   [BgRemoverFallback] the next engine takes over.
/// - The first call after an install can fail while Play services
///   downloads the module: [prepare] waits for it, [moduleWait] at most.
class BgMlKitRemover implements BgRemover {
  /// Where the guard file goes, null for the app's support folder.
  final String? guardDir;

  /// Tries ML Kit again even if it crashed the app last time.
  final bool retryAfterCrash;

  /// How long [prepare] waits for the Play services module.
  final Duration moduleWait;

  /// Lets ML Kit read [BgPhoto.filePath] when there is one (it decodes the
  /// file itself), instead of sending the pixels.
  final bool useFile;

  SubjectSegmenter? _segmenter;
  File? _guard;

  /// The engine.
  BgMlKitRemover({
    this.guardDir,
    this.retryAfterCrash = false,
    this.moduleWait = const Duration(minutes: 3),
    this.useFile = true,
  });

  @override
  String get name => 'mlkit';

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<File> _guardFile() async => _guard ??= File(
    join(
      guardDir ?? (await getApplicationSupportDirectory()).path,
      'tekartik_bg_removal_mlkit_guard.txt',
    ),
  );

  /// What ML Kit was doing when it killed the app last time, or null.
  Future<String?> lastCrash() async {
    if (!_isAndroid) return null;
    final guard = await _guardFile();
    return guard.existsSync() ? guard.readAsStringSync() : null;
  }

  /// Forgets a crash: ML Kit is tried again.
  Future<void> clearCrash() async {
    final guard = await _guardFile();
    if (guard.existsSync()) {
      await guard.delete();
    }
  }

  Future<T> _guarded<T>(String what, Future<T> Function() call) async {
    final guard = await _guardFile();
    await guard.writeAsString(
      '$what, ${DateTime.now().toIso8601String()}',
      flush: true,
    );
    final result = await call();
    await guard.delete();
    return result;
  }

  @override
  Future<BgRemoverStatus> getStatus() async {
    if (!_isAndroid) {
      return BgRemoverStatus.unsupported;
    }
    if (_segmenter != null) {
      return BgRemoverStatus.ready;
    }
    if (!retryAfterCrash && await lastCrash() != null) {
      return BgRemoverStatus.unsupported;
    }
    return BgRemoverStatus.needsPrepare;
  }

  @override
  Future<void> prepare({void Function(String status)? onStatus}) async {
    if (_segmenter != null) {
      return;
    }
    if (!_isAndroid) {
      throw UnsupportedError('ML Kit Subject Segmentation is Android only');
    }
    if (retryAfterCrash) {
      await clearCrash();
    }
    final crash = await lastCrash();
    if (crash != null) {
      throw StateError('ML Kit killed the app last time ($crash)');
    }
    final segmenter = SubjectSegmenter(
      options: SubjectSegmenterOptions(
        enableForegroundBitmap: false,
        enableForegroundConfidenceMask: true,
        // Never the per-subject masks: they crash (see the class doc).
        enableMultipleSubjects: SubjectResultOptions(
          enableConfidenceMask: false,
          enableSubjectBitmap: false,
        ),
      ),
    );
    // The first call starts the Play services download of the module (if
    // the install did not) and fails until it is there: warm up on a small
    // blank image until it answers.
    const side = 64;
    final blank = InputImage.fromBitmap(
      bitmap: Uint8List(side * side * 4),
      width: side,
      height: side,
    );
    final sw = Stopwatch()..start();
    while (true) {
      try {
        await _guarded('warm-up', () => segmenter.processImage(blank));
        _segmenter = segmenter;
        return;
      } on PlatformException catch (e) {
        final waiting = '${e.message}'.contains('to be downloaded');
        if (!waiting || sw.elapsed > moduleWait) {
          await (await _guardFile()).delete();
          await segmenter.close();
          rethrow;
        }
        onStatus?.call(
          'mlkit: waiting for the Play services module '
          '(${sw.elapsed.inSeconds} s)',
        );
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }

  @override
  Future<BgEngineMasks> segment(
    BgPhoto photo, {
    BgRemovalOptions options = const BgRemovalOptions(),
  }) async {
    await prepare();
    final segmenter = _segmenter!;
    final image = photo.image;
    final filePath = useFile ? photo.filePath : null;
    final sw = Stopwatch()..start();
    var confidence = await _process(segmenter, image, filePath);
    if (filePath != null && confidence?.length != image.width * image.height) {
      // The file decodes to another size (orientation): send the pixels.
      confidence = await _process(segmenter, image, null);
    }
    final infer = sw.elapsed;
    if (confidence == null || confidence.length != image.width * image.height) {
      throw StateError(
        'mlkit: mask of ${confidence?.length} values for '
        '${image.width}x${image.height}',
      );
    }
    sw.reset();
    final mask = await _mask(
      image.width,
      image.height,
      Float32List.fromList(confidence),
    );
    return BgEngineMasks(
      foreground: mask,
      timings: {'mlkit.infer': infer, 'mlkit.post': sw.elapsed},
    );
  }

  Future<List<double>?> _process(
    SubjectSegmenter segmenter,
    BgRgbaImage image,
    String? filePath,
  ) async {
    final input = filePath != null
        ? InputImage.fromFilePath(filePath)
        : InputImage.fromBitmap(
            bitmap: image.rgba,
            width: image.width,
            height: image.height,
          );
    final result = await _guarded(
      'segment ${image.width}x${image.height}',
      () => segmenter.processImage(input),
    );
    return result.foregroundConfidenceMask;
  }

  @override
  Future<void> close() async {
    await _segmenter?.close();
    _segmenter = null;
  }
}

// Top-level: the isolate closure only captures its arguments.
Future<BgMask> _mask(int width, int height, Float32List values) =>
    bgRunInIsolate(() => BgMask.fromUnit(width, height, values));

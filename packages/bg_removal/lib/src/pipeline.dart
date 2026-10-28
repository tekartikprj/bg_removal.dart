import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tekartik_app_image_webp/webp.dart';

import 'image.dart';
import 'mask_ops.dart';
import 'options.dart';
import 'remover.dart';

/// Runs a heavy synchronous step: inline ([bgRunInline]), or in an isolate
/// (`bgRunInIsolate` of `tekartik_bg_removal_flutter`). The computation
/// only captures plain data (images, masks, options).
typedef BgRunner = Future<R> Function<R>(R Function() computation);

/// Runs [computation] here, in the calling isolate.
Future<R> bgRunInline<R>(R Function() computation) async => computation();

/// The person, the foreground, or both combined, as [BgRemovalOptions.keep]
/// asks.
BgMask bgSelectMask(BgEngineMasks masks, BgRemovalOptions options) {
  final person = masks.person;
  final foreground = masks.foreground;
  switch (options.keep) {
    case BgKeep.person:
      if (person == null) {
        throw UnsupportedError('keep person: the engine has no person mask');
      }
      return person;
    case BgKeep.foreground:
      return foreground ?? person!;
    case BgKeep.personAndCarried:
      if (person != null && foreground != null) {
        return bgCombineAnchored(
          person: person,
          salient: foreground,
          grow: options.anchorGrow,
          threshold: options.threshold,
        );
      }
      return person ?? foreground!;
  }
}

/// The clean-up steps of [options]: alpha levels, small regions, holes,
/// feather. With the default options the mask is returned as is.
BgMask bgCleanMask(BgMask mask, BgRemovalOptions options) {
  var out = bgAlphaLevels(
    mask,
    low: options.transparentBelow,
    high: options.opaqueAbove,
  );
  if (options.minRegion > 0) {
    out = bgRemoveSmallRegions(
      out,
      minShare: options.minRegion,
      threshold: options.threshold,
    );
  }
  if (options.fillHoles > 0) {
    out = bgFillHoles(
      out,
      threshold: options.threshold,
      maxShare: options.fillHoles,
    );
  }
  return bgFeather(out, options.feather);
}

/// The final mask from an engine's masks: selected, scaled to [width] x
/// [height] (the photo, when the engine saw it smaller), cleaned.
BgMask bgFinalMask(
  BgEngineMasks masks,
  BgRemovalOptions options, {
  int? width,
  int? height,
}) {
  var mask = bgSelectMask(masks, options);
  if (width != null && height != null) {
    mask = mask.resized(width, height);
  }
  return bgCleanMask(mask, options);
}

/// [image] with [mask] as alpha, cropped and scaled as [options] ask. The
/// box is the crop in [image] pixels, null without crop.
(BgRgbaImage cutout, BgBox? box) bgCutOut(
  BgRgbaImage image,
  BgMask mask,
  BgRemovalOptions options,
) {
  var photo = image;
  var alpha = mask;
  BgBox? box;
  if (options.crop) {
    box = mask
        .bounds(options.threshold)
        ?.inflate(options.cropMargin, image.width, image.height);
    if (box != null) {
      photo = photo.crop(box);
      alpha = alpha.crop(box);
    }
  }
  final maxOutput = options.maxOutputSize;
  if (maxOutput != null) {
    // The colour and the alpha are scaled apart: no background colour
    // bleeds into the edge.
    photo = photo.downscaled(maxOutput);
    alpha = alpha.resized(photo.width, photo.height);
  }
  return (photo.withAlpha(alpha), box);
}

/// Removes the background of [photo] with [remover] (prepared): the engine
/// masks, the person and what they carry kept, cleaned, then the cut-out.
///
/// [run] runs the heavy steps; pass `bgRunInIsolate` (Flutter) to keep them
/// off the UI isolate.
Future<BgRemovalResult> bgRemoveBackground(
  BgRemover remover,
  BgPhoto photo, {
  BgRemovalOptions options = const BgRemovalOptions(),
  BgRunner run = bgRunInline,
}) async {
  final timings = <String, Duration>{};
  final sw = Stopwatch()..start();
  void lap(String step) {
    timings[step] = sw.elapsed;
    sw.reset();
  }

  var enginePhoto = photo;
  final maxSegment = options.maxSegmentSize;
  if (maxSegment != null) {
    final (width, height) = bgFitSize(photo.width, photo.height, maxSegment);
    if (width != photo.width || height != photo.height) {
      enginePhoto = BgPhoto(await _downscale(run, photo.image, maxSegment));
      lap('downscale');
    }
  }
  final masks = await remover.segment(enginePhoto, options: options);
  lap('segment');
  final mask = await _finalMask(run, masks, options, photo.width, photo.height);
  lap('mask');
  final (cutout, box) = await _cutOut(run, photo.image, mask, options);
  lap('cutout');
  return BgRemovalResult(
    cutout: cutout,
    mask: mask,
    box: box,
    engine: remover.name,
    timings: {...masks.timings, ...timings},
  );
}

/// A cut-out and how it was made.
class BgRemovalResult {
  /// The photo with the mask as alpha (cropped and scaled if asked).
  final BgRgbaImage cutout;

  /// The final mask, photo size (before the crop and the scale).
  final BgMask mask;

  /// The crop in photo pixels, null without crop.
  final BgBox? box;

  /// The engine that made it.
  final String engine;

  /// Where the time went: the engine's steps, then `segment` (the engine
  /// in all), `mask`, `cutout`.
  final Map<String, Duration> timings;

  /// A result.
  BgRemovalResult({
    required this.cutout,
    required this.mask,
    required this.box,
    required this.engine,
    required this.timings,
  });

  /// The cut-out as PNG (lossless, big: about 2.5 MB at 1280x1920).
  Uint8List toPng() => bgEncodePng(cutout);

  /// The cut-out as WebP: lossy colour at [quality], lossless alpha (about
  /// 200 KB at 1280x1920, quality 80).
  Uint8List toWebp({double quality = 80}) =>
      bgEncodeWebp(cutout, quality: quality);
}

/// [image] as PNG (RGBA).
Uint8List bgEncodePng(BgRgbaImage image) => img.encodePng(
  img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: _ownBuffer(image.rgba),
    numChannels: 4,
  ),
);

/// [image] as WebP, lossy colour at [quality] with a lossless alpha.
Uint8List bgEncodeWebp(BgRgbaImage image, {double quality = 80}) => encodeWebp(
  WebpImage(image.width, image.height, image.rgba),
  options: WebpEncodeOptions(quality: quality),
);

/// [mask] as a grey PNG.
Uint8List bgEncodeMaskPng(BgMask mask) => img.encodePng(
  img.Image.fromBytes(
    width: mask.width,
    height: mask.height,
    bytes: _ownBuffer(mask.alpha),
    numChannels: 1,
  ),
);

ByteBuffer _ownBuffer(Uint8List bytes) =>
    bytes.offsetInBytes == 0 && bytes.buffer.lengthInBytes == bytes.length
    ? bytes.buffer
    : Uint8List.fromList(bytes).buffer;

// The [BgRunner] steps are top-level functions: their closures only capture
// the arguments.

Future<BgRgbaImage> _downscale(BgRunner run, BgRgbaImage image, int maxSide) =>
    run(() => image.downscaled(maxSide));

Future<BgMask> _finalMask(
  BgRunner run,
  BgEngineMasks masks,
  BgRemovalOptions options,
  int width,
  int height,
) => run(() => bgFinalMask(masks, options, width: width, height: height));

Future<(BgRgbaImage, BgBox?)> _cutOut(
  BgRunner run,
  BgRgbaImage image,
  BgMask mask,
  BgRemovalOptions options,
) => run(() => bgCutOut(image, mask, options));

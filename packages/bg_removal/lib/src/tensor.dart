import 'dart:math';
import 'dart:typed_data';

import 'image.dart';

/// How a model wants its input.
class BgTensorSpec {
  /// Fixed square side, or null when the model takes any size.
  final int? square;

  /// For any size: the short side, both sides rounded to [multiple].
  final int shortSide;

  /// Side multiple for any size.
  final int multiple;

  /// Per channel mean, after scaling to 0-1.
  final List<double> mean;

  /// Per channel std.
  final List<double> std;

  /// rembg models divide by the image max (not 255).
  final bool divideByMax;

  /// A tensor spec.
  const BgTensorSpec({
    this.square,
    this.shortSide = 512,
    this.multiple = 32,
    required this.mean,
    required this.std,
    this.divideByMax = false,
  });

  /// The model input size for an image.
  (int width, int height) sizeFor(int width, int height) {
    final square = this.square;
    if (square != null) {
      return (square, square);
    }
    final scale = shortSide / min(width, height);
    int side(int v) => max(multiple, (v * scale / multiple).round() * multiple);
    return (side(width), side(height));
  }
}

/// The ImageNet mean.
const bgImagenetMean = [0.485, 0.456, 0.406];

/// The ImageNet std.
const bgImagenetStd = [0.229, 0.224, 0.225];

/// [image] resized to [width] x [height] as an NCHW float tensor.
///
/// Downscaling averages the source pixels of each output pixel (area).
Float32List bgRgbaImageTensor(
  BgRgbaImage image,
  BgTensorSpec spec,
  int width,
  int height,
) {
  final plane = width * height;
  final out = Float32List(plane * 3);
  final sx = image.width / width;
  final sy = image.height / height;
  final src = image.rgba;
  var maxValue = 0.0;
  for (var y = 0; y < height; y++) {
    final y0 = (y * sy).floor();
    final y1 = max(y0 + 1, min(image.height, ((y + 1) * sy).floor()));
    for (var x = 0; x < width; x++) {
      final x0 = (x * sx).floor();
      final x1 = max(x0 + 1, min(image.width, ((x + 1) * sx).floor()));
      var r = 0, g = 0, b = 0;
      for (var yy = y0; yy < y1; yy++) {
        var i = (yy * image.width + x0) * 4;
        for (var xx = x0; xx < x1; xx++) {
          r += src[i];
          g += src[i + 1];
          b += src[i + 2];
          i += 4;
        }
      }
      final n = (y1 - y0) * (x1 - x0);
      final o = y * width + x;
      out[o] = r / n;
      out[plane + o] = g / n;
      out[plane * 2 + o] = b / n;
    }
  }
  if (spec.divideByMax) {
    for (final v in out) {
      if (v > maxValue) maxValue = v;
    }
    if (maxValue < 1e-6) maxValue = 1e-6;
  } else {
    maxValue = 255;
  }
  for (var c = 0; c < 3; c++) {
    final mean = spec.mean[c];
    final std = spec.std[c];
    for (var i = c * plane; i < (c + 1) * plane; i++) {
      out[i] = (out[i] / maxValue - mean) / std;
    }
  }
  return out;
}

/// How a model's output becomes a mask.
enum BgOutputKind {
  /// Min-max normalized (rembg salient models).
  minMax,

  /// Sigmoid, then min-max (BiRefNet).
  sigmoidMinMax,

  /// Already 0-1 (MODNet matte), clamped.
  unit,
}

/// A model output of [width] x [height] floats as a mask of the image size.
BgMask bgOutputMask(
  List<double> values,
  int width,
  int height,
  BgOutputKind kind,
  int imageWidth,
  int imageHeight,
) {
  final v = Float32List.fromList(values);
  if (kind == BgOutputKind.sigmoidMinMax) {
    for (var i = 0; i < v.length; i++) {
      v[i] = 1 / (1 + exp(-v[i]));
    }
  }
  if (kind != BgOutputKind.unit) {
    var lo = double.infinity, hi = -double.infinity;
    for (final x in v) {
      if (x < lo) lo = x;
      if (x > hi) hi = x;
    }
    final range = max(hi - lo, 1e-6);
    for (var i = 0; i < v.length; i++) {
      v[i] = (v[i] - lo) / range;
    }
  }
  return BgMask.fromUnit(
    imageWidth,
    imageHeight,
    bgResizeBilinear(v, width, height, imageWidth, imageHeight),
  );
}

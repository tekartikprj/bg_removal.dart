import 'dart:math';
import 'dart:typed_data';

/// An RGBA image in memory, 4 bytes per pixel, row by row.
///
/// It is the "image data" every engine and encoder takes. In Flutter,
/// `ui.Image.toByteData(format: rawRgba)` gives these bytes.
class BgRgbaImage {
  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// The pixels, `width * height * 4` bytes.
  final Uint8List rgba;

  /// An image from its pixels.
  BgRgbaImage(this.width, this.height, this.rgba) {
    if (rgba.length != width * height * 4) {
      throw ArgumentError(
        'rgba length ${rgba.length} does not match ${width}x$height*4',
      );
    }
  }

  /// The same pixels with [mask] as alpha.
  BgRgbaImage withAlpha(BgMask mask) {
    _checkSize(mask.width, mask.height);
    final out = Uint8List.fromList(rgba);
    for (var i = 0; i < mask.alpha.length; i++) {
      out[i * 4 + 3] = mask.alpha[i];
    }
    return BgRgbaImage(width, height, out);
  }

  /// The pixels inside [box].
  BgRgbaImage crop(BgBox box) {
    final out = Uint8List(box.width * box.height * 4);
    for (var y = 0; y < box.height; y++) {
      final from = ((box.top + y) * width + box.left) * 4;
      out.setRange(y * box.width * 4, (y + 1) * box.width * 4, rgba, from);
    }
    return BgRgbaImage(box.width, box.height, out);
  }

  /// This image scaled down so that its long side is at most [maxSide]
  /// (area average), or this image when it is already small enough.
  BgRgbaImage downscaled(int maxSide) {
    final (newWidth, newHeight) = bgFitSize(width, height, maxSide);
    if (newWidth == width && newHeight == height) {
      return this;
    }
    final out = Uint8List(newWidth * newHeight * 4);
    final sx = width / newWidth;
    final sy = height / newHeight;
    for (var y = 0; y < newHeight; y++) {
      final y0 = (y * sy).floor();
      final y1 = max(y0 + 1, min(height, ((y + 1) * sy).floor()));
      for (var x = 0; x < newWidth; x++) {
        final x0 = (x * sx).floor();
        final x1 = max(x0 + 1, min(width, ((x + 1) * sx).floor()));
        var r = 0, g = 0, b = 0, a = 0;
        for (var yy = y0; yy < y1; yy++) {
          var i = (yy * width + x0) * 4;
          for (var xx = x0; xx < x1; xx++) {
            r += rgba[i];
            g += rgba[i + 1];
            b += rgba[i + 2];
            a += rgba[i + 3];
            i += 4;
          }
        }
        final n = (y1 - y0) * (x1 - x0);
        final o = (y * newWidth + x) * 4;
        out[o] = (r / n).round();
        out[o + 1] = (g / n).round();
        out[o + 2] = (b / n).round();
        out[o + 3] = (a / n).round();
      }
    }
    return BgRgbaImage(newWidth, newHeight, out);
  }

  void _checkSize(int otherWidth, int otherHeight) {
    if (otherWidth != width || otherHeight != height) {
      throw ArgumentError(
        'size ${otherWidth}x$otherHeight does not match ${width}x$height',
      );
    }
  }
}

/// The size that fits [width] x [height] in [maxSide] (long side), keeping
/// the aspect ratio; the same size when it already fits.
(int width, int height) bgFitSize(int width, int height, int maxSide) {
  final long = max(width, height);
  if (long <= maxSide) {
    return (width, height);
  }
  final scale = maxSide / long;
  return (max(1, (width * scale).round()), max(1, (height * scale).round()));
}

/// An alpha mask, one byte per pixel: 0 removed, 255 kept.
class BgMask {
  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// The alpha values, `width * height` bytes.
  final Uint8List alpha;

  /// A mask from its alpha values.
  BgMask(this.width, this.height, this.alpha) {
    if (alpha.length != width * height) {
      throw ArgumentError(
        'alpha length ${alpha.length} does not match ${width}x$height',
      );
    }
  }

  /// An empty mask (everything removed).
  factory BgMask.empty(int width, int height) =>
      BgMask(width, height, Uint8List(width * height));

  /// A mask from values between 0 and 1 (clamped).
  factory BgMask.fromUnit(int width, int height, List<double> values) {
    final alpha = Uint8List(width * height);
    for (var i = 0; i < alpha.length; i++) {
      alpha[i] = (values[i].clamp(0.0, 1.0) * 255).round();
    }
    return BgMask(width, height, alpha);
  }

  /// 1 where the alpha is at least [threshold], 0 elsewhere.
  Uint8List binary([int threshold = 128]) {
    final out = Uint8List(alpha.length);
    for (var i = 0; i < alpha.length; i++) {
      if (alpha[i] >= threshold) {
        out[i] = 1;
      }
    }
    return out;
  }

  /// This mask resized to [newWidth] x [newHeight] (bilinear).
  BgMask resized(int newWidth, int newHeight) {
    if (newWidth == width && newHeight == height) {
      return this;
    }
    final values = Float32List(alpha.length);
    for (var i = 0; i < alpha.length; i++) {
      values[i] = alpha[i] / 255;
    }
    return BgMask.fromUnit(
      newWidth,
      newHeight,
      bgResizeBilinear(values, width, height, newWidth, newHeight),
    );
  }

  /// The values inside [box].
  BgMask crop(BgBox box) {
    final out = Uint8List(box.width * box.height);
    for (var y = 0; y < box.height; y++) {
      final from = (box.top + y) * width + box.left;
      out.setRange(y * box.width, (y + 1) * box.width, alpha, from);
    }
    return BgMask(box.width, box.height, out);
  }

  /// The smallest box holding every value at least [threshold], or null
  /// when there is none.
  BgBox? bounds([int threshold = 128]) {
    var left = width, top = height, right = -1, bottom = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (alpha[row + x] >= threshold) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    return right < 0 ? null : BgBox(left, top, right + 1, bottom + 1);
  }
}

/// A box in image pixels, [left, top] included, [right, bottom] excluded.
class BgBox {
  /// Left.
  final int left;

  /// Top.
  final int top;

  /// Right (excluded).
  final int right;

  /// Bottom (excluded).
  final int bottom;

  /// A box.
  const BgBox(this.left, this.top, this.right, this.bottom);

  /// From `[left, top, right, bottom]`.
  factory BgBox.fromList(List<Object?> list) => BgBox(
    (list[0] as num).toInt(),
    (list[1] as num).toInt(),
    (list[2] as num).toInt(),
    (list[3] as num).toInt(),
  );

  /// Width.
  int get width => right - left;

  /// Height.
  int get height => bottom - top;

  /// This box grown by [margin] on each side, kept inside [maxWidth] x
  /// [maxHeight].
  BgBox inflate(int margin, int maxWidth, int maxHeight) => BgBox(
    max(0, left - margin),
    max(0, top - margin),
    min(maxWidth, right + margin),
    min(maxHeight, bottom + margin),
  );

  /// `[left, top, right, bottom]`.
  List<int> toList() => [left, top, right, bottom];

  @override
  bool operator ==(Object other) =>
      other is BgBox &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'BgBox($left, $top, $right, $bottom)';
}

/// Bilinear resize of a single channel of floats (pixel centers aligned).
Float32List bgResizeBilinear(
  List<double> src,
  int srcWidth,
  int srcHeight,
  int width,
  int height,
) {
  final out = Float32List(width * height);
  final sx = srcWidth / width;
  final sy = srcHeight / height;
  for (var y = 0; y < height; y++) {
    var fy = (y + 0.5) * sy - 0.5;
    if (fy < 0) fy = 0;
    var y0 = fy.floor();
    if (y0 > srcHeight - 1) y0 = srcHeight - 1;
    final y1 = y0 + 1 < srcHeight ? y0 + 1 : y0;
    final wy = fy - y0;
    for (var x = 0; x < width; x++) {
      var fx = (x + 0.5) * sx - 0.5;
      if (fx < 0) fx = 0;
      var x0 = fx.floor();
      if (x0 > srcWidth - 1) x0 = srcWidth - 1;
      final x1 = x0 + 1 < srcWidth ? x0 + 1 : x0;
      final wx = fx - x0;
      final top =
          src[y0 * srcWidth + x0] * (1 - wx) + src[y0 * srcWidth + x1] * wx;
      final bottom =
          src[y1 * srcWidth + x0] * (1 - wx) + src[y1 * srcWidth + x1] * wx;
      out[y * width + x] = top * (1 - wy) + bottom * wy;
    }
  }
  return out;
}

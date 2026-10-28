import 'dart:math';
import 'dart:typed_data';

import 'package:tekartik_bg_removal/bg_removal.dart';

/// A small cut-out of [image] through [mask] over a magenta and green
/// checkerboard (a lost bag shows at once), [height] pixels high.
BgRgbaImage benchThumbnail(BgRgbaImage image, BgMask? mask, int height) {
  final width = max(1, (image.width * height / image.height).round());
  final out = Uint8List(width * height * 4);
  final sx = image.width / width;
  final sy = image.height / height;
  for (var y = 0; y < height; y++) {
    final srcY = min(image.height - 1, (y * sy).floor());
    for (var x = 0; x < width; x++) {
      final srcX = min(image.width - 1, (x * sx).floor());
      final s = srcY * image.width + srcX;
      final a = mask == null ? 255 : mask.alpha[s];
      final odd = ((x ~/ 8) + (y ~/ 8)).isOdd;
      final bg = odd ? const [0, 200, 0] : const [255, 0, 255];
      final o = (y * width + x) * 4;
      for (var c = 0; c < 3; c++) {
        out[o + c] = (image.rgba[s * 4 + c] * a + bg[c] * (255 - a)) ~/ 255;
      }
      out[o + 3] = 255;
    }
  }
  return BgRgbaImage(width, height, out);
}

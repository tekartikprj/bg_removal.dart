import 'dart:math';
import 'dart:typed_data';

import 'image.dart';

/// Square dilation of a 0/1 mask by [radius] pixels (two passes, O(n)).
Uint8List bgDilate(Uint8List bin, int width, int height, int radius) {
  if (radius <= 0) {
    return Uint8List.fromList(bin);
  }
  final rows = Uint8List(bin.length);
  final prefix = Int32List(max(width, height) + 1);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < width; x++) {
      prefix[x + 1] = prefix[x] + bin[row + x];
    }
    for (var x = 0; x < width; x++) {
      final from = max(0, x - radius);
      final to = min(width, x + radius + 1);
      if (prefix[to] - prefix[from] > 0) {
        rows[row + x] = 1;
      }
    }
  }
  final out = Uint8List(bin.length);
  for (var x = 0; x < width; x++) {
    for (var y = 0; y < height; y++) {
      prefix[y + 1] = prefix[y] + rows[y * width + x];
    }
    for (var y = 0; y < height; y++) {
      final from = max(0, y - radius);
      final to = min(height, y + radius + 1);
      if (prefix[to] - prefix[from] > 0) {
        out[y * width + x] = 1;
      }
    }
  }
  return out;
}

/// Connected components of a 0/1 mask (4-connectivity).
///
/// Labels start at 1, 0 is the background.
class BgLabels {
  /// One label per pixel.
  final Int32List labels;

  /// The number of components.
  final int count;

  /// Labels.
  BgLabels(this.labels, this.count);
}

/// Labels the connected components of [bin].
BgLabels bgLabel(Uint8List bin, int width, int height) {
  final labels = Int32List(bin.length);
  final stack = Int32List(bin.length);
  var count = 0;
  for (var start = 0; start < bin.length; start++) {
    if (bin[start] == 0 || labels[start] != 0) {
      continue;
    }
    count++;
    var top = 0;
    stack[top++] = start;
    labels[start] = count;
    while (top > 0) {
      final i = stack[--top];
      final x = i % width;
      void visit(int j) {
        if (bin[j] != 0 && labels[j] == 0) {
          labels[j] = count;
          stack[top++] = j;
        }
      }

      if (x > 0) visit(i - 1);
      if (x < width - 1) visit(i + 1);
      if (i >= width) visit(i - width);
      if (i + width < bin.length) visit(i + width);
    }
  }
  return BgLabels(labels, count);
}

/// Keeps the person, plus the regions of [salient] that touch the person.
///
/// [person] and [salient] have the same size. The person is grown by
/// [grow] of the image's long side, so that a bag held in the hand
/// touches it. A salient region that does not touch the person (a car, a
/// poster) is dropped. Alpha = max(person, salient inside the kept regions).
/// A pixel is "in" a mask from alpha [threshold].
BgMask bgCombineAnchored({
  required BgMask person,
  required BgMask salient,
  double grow = 0.01,
  int threshold = 128,
}) {
  assert(person.width == salient.width && person.height == salient.height);
  final width = person.width;
  final height = person.height;
  final radius = max(2, (grow * max(width, height)).round());
  final near = bgDilate(person.binary(threshold), width, height, radius);
  final components = bgLabel(salient.binary(threshold), width, height);
  final touching = Uint8List(components.count + 1);
  for (var i = 0; i < near.length; i++) {
    if (near[i] != 0) {
      touching[components.labels[i]] = 1;
    }
  }
  touching[0] = 0;
  final keep = Uint8List(near.length);
  for (var i = 0; i < keep.length; i++) {
    keep[i] = touching[components.labels[i]];
  }
  // A little margin so that the soft edge of a kept region stays.
  final keepEdge = bgDilate(keep, width, height, 3);
  final alpha = Uint8List(near.length);
  for (var i = 0; i < alpha.length; i++) {
    final s = keepEdge[i] != 0 ? salient.alpha[i] : 0;
    alpha[i] = max(person.alpha[i], s);
  }
  return BgMask(width, height, alpha);
}

/// Alpha at most [low] becomes 0, at least [high] becomes 255, and the
/// values between are stretched: a faint halo goes, a nearly solid subject
/// becomes solid.
BgMask bgAlphaLevels(BgMask mask, {int low = 0, int high = 255}) {
  if (low <= 0 && high >= 255) {
    return mask;
  }
  if (high <= low) {
    throw ArgumentError('high ($high) must be above low ($low)');
  }
  final table = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    table[v] = v <= low
        ? 0
        : v >= high
        ? 255
        : ((v - low) * 255 / (high - low)).round();
  }
  final alpha = Uint8List(mask.alpha.length);
  for (var i = 0; i < alpha.length; i++) {
    alpha[i] = table[mask.alpha[i]];
  }
  return BgMask(mask.width, mask.height, alpha);
}

/// Removes the regions (alpha at least [threshold]) smaller than
/// [minShare] of the image: specks and far away bits.
BgMask bgRemoveSmallRegions(
  BgMask mask, {
  required double minShare,
  int threshold = 128,
}) {
  if (minShare <= 0) {
    return mask;
  }
  final minArea = minShare * mask.width * mask.height;
  final components = bgLabel(mask.binary(threshold), mask.width, mask.height);
  final areas = Int32List(components.count + 1);
  for (final label in components.labels) {
    areas[label]++;
  }
  final alpha = Uint8List.fromList(mask.alpha);
  for (var i = 0; i < alpha.length; i++) {
    final label = components.labels[i];
    if (label != 0 && areas[label] < minArea) {
      alpha[i] = 0;
    }
  }
  return BgMask(mask.width, mask.height, alpha);
}

/// Makes solid the holes of the mask (alpha under [threshold]) that do not
/// reach the image border: the gap between an arm and the body stays, a
/// see-through spot inside a bag is filled.
///
/// Only holes smaller than [maxShare] of the image are filled.
BgMask bgFillHoles(BgMask mask, {int threshold = 128, double maxShare = 1}) {
  final width = mask.width;
  final height = mask.height;
  final background = Uint8List(mask.alpha.length);
  for (var i = 0; i < background.length; i++) {
    if (mask.alpha[i] < threshold) {
      background[i] = 1;
    }
  }
  final components = bgLabel(background, width, height);
  final border = Uint8List(components.count + 1);
  final areas = Int32List(components.count + 1);
  for (var i = 0; i < components.labels.length; i++) {
    areas[components.labels[i]]++;
  }
  void touch(int i) => border[components.labels[i]] = 1;
  for (var x = 0; x < width; x++) {
    touch(x);
    touch((height - 1) * width + x);
  }
  for (var y = 0; y < height; y++) {
    touch(y * width);
    touch(y * width + width - 1);
  }
  final maxArea = maxShare * width * height;
  final alpha = Uint8List.fromList(mask.alpha);
  for (var i = 0; i < alpha.length; i++) {
    final label = components.labels[i];
    if (label != 0 && border[label] == 0 && areas[label] <= maxArea) {
      alpha[i] = 255;
    }
  }
  return BgMask(width, height, alpha);
}

/// Softens the edge of the mask: a box blur of [radius] pixels.
BgMask bgFeather(BgMask mask, int radius) {
  if (radius <= 0) {
    return mask;
  }
  final width = mask.width;
  final height = mask.height;
  final size = 2 * radius + 1;
  final rows = Uint8List(mask.alpha.length);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    var sum = 0;
    for (var x = -radius; x <= radius; x++) {
      sum += mask.alpha[row + x.clamp(0, width - 1)];
    }
    for (var x = 0; x < width; x++) {
      rows[row + x] = (sum / size).round();
      sum +=
          mask.alpha[row + (x + radius + 1).clamp(0, width - 1)] -
          mask.alpha[row + (x - radius).clamp(0, width - 1)];
    }
  }
  final out = Uint8List(mask.alpha.length);
  for (var x = 0; x < width; x++) {
    var sum = 0;
    for (var y = -radius; y <= radius; y++) {
      sum += rows[y.clamp(0, height - 1) * width + x];
    }
    for (var y = 0; y < height; y++) {
      out[y * width + x] = (sum / size).round();
      sum +=
          rows[(y + radius + 1).clamp(0, height - 1) * width + x] -
          rows[(y - radius).clamp(0, height - 1) * width + x];
    }
  }
  return BgMask(width, height, out);
}

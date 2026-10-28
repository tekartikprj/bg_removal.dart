import 'image.dart';

/// How a mask compares with a reference mask.
class BgScore {
  /// Intersection over union, at alpha 128.
  final double iou;

  /// Share of the reference that is lost.
  final double missed;

  /// Kept pixels outside the reference, as a share of the reference.
  final double extra;

  /// Mean alpha (0-1) inside the bag boxes, on the reference pixels only,
  /// or null without boxes.
  final double? bag;

  /// A score.
  const BgScore({
    required this.iou,
    required this.missed,
    required this.extra,
    required this.bag,
  });

  /// As json.
  Map<String, Object?> toJson() => {
    'iou': iou,
    'missed': missed,
    'extra': extra,
    'bag': bag,
  };
}

/// Scores [mask] against [reference] (same size).
BgScore bgScore(BgMask mask, BgMask reference, {List<BgBox> bags = const []}) {
  assert(mask.width == reference.width && mask.height == reference.height);
  var inter = 0, union = 0, refCount = 0, missed = 0, extra = 0;
  for (var i = 0; i < mask.alpha.length; i++) {
    final m = mask.alpha[i] >= 128;
    final r = reference.alpha[i] >= 128;
    if (r) refCount++;
    if (m && r) inter++;
    if (m || r) union++;
    if (r && !m) missed++;
    if (m && !r) extra++;
  }
  double? bag;
  if (bags.isNotEmpty) {
    var sum = 0, n = 0;
    for (final box in bags) {
      for (var y = box.top; y < box.bottom && y < mask.height; y++) {
        for (var x = box.left; x < box.right && x < mask.width; x++) {
          final i = y * mask.width + x;
          if (reference.alpha[i] >= 128) {
            sum += mask.alpha[i];
            n++;
          }
        }
      }
    }
    bag = n == 0 ? null : sum / n / 255;
  }
  return BgScore(
    iou: union == 0 ? 1 : inter / union,
    missed: refCount == 0 ? 0 : missed / refCount,
    extra: refCount == 0 ? 0 : extra / refCount,
    bag: bag,
  );
}

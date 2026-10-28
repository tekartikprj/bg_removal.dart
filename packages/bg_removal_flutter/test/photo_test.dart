import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';

void main() {
  testWidgets('bytes in, cut-out out', (tester) async {
    await tester.runAsync(() async {
      // A 40 x 20 opaque photo, a fake person on its left half.
      final rgba = Uint8List(40 * 20 * 4)..fillRange(0, 40 * 20 * 4, 255);
      final png = bgEncodePng(BgRgbaImage(40, 20, rgba));
      final photo = await bgPhotoFromBytes(png);
      expect((photo.width, photo.height), (40, 20));
      expect(photo.image.rgba[3], 255);

      final alpha = Uint8List(40 * 20);
      for (var y = 0; y < 20; y++) {
        alpha.fillRange(y * 40, y * 40 + 20, 255);
      }
      final result = await bgRemoveBackgroundFromBytes(
        BgRemoverFake(person: BgMask(40, 20, alpha)),
        png,
        options: const BgRemovalOptions(crop: true, cropMargin: 0),
      );
      expect(result.box, const BgBox(0, 0, 20, 20));
      expect(result.cutout.width, 20);
      expect(result.timings.keys, containsAll(['segment', 'mask', 'cutout']));
    });
  });

  testWidgets('ui.Image round trip keeps straight alpha', (tester) async {
    await tester.runAsync(() async {
      // A white pixel at alpha 0, a red one at alpha 128.
      final image = BgRgbaImage(
        2,
        1,
        Uint8List.fromList([255, 255, 255, 0, 255, 0, 0, 128]),
      );
      final ui = await bgRgbaImageToUiImage(image);
      final back = await bgRgbaImageFromUiImage(ui);
      ui.dispose();
      expect(back.rgba[3], 0);
      expect(back.rgba[7], 128);
      // Straight again: red stays (about) full.
      expect(back.rgba[4], greaterThan(250));
    });
  });
}

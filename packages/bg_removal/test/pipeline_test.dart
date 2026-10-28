import 'dart:typed_data';

import 'package:tekartik_app_image_webp/webp.dart';
import 'package:tekartik_bg_removal/bg_removal.dart';
import 'package:test/test.dart';

/// A [width] x [height] mask, 255 inside the boxes.
BgMask _boxes(int width, int height, List<BgBox> boxes) {
  final alpha = Uint8List(width * height);
  for (final box in boxes) {
    for (var y = box.top; y < box.bottom; y++) {
      for (var x = box.left; x < box.right; x++) {
        alpha[y * width + x] = 255;
      }
    }
  }
  return BgMask(width, height, alpha);
}

BgRgbaImage _photo(int width, int height) {
  final rgba = Uint8List(width * height * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba[i] = 200;
    rgba[i + 1] = 100;
    rgba[i + 2] = 50;
    rgba[i + 3] = 255;
  }
  return BgRgbaImage(width, height, rgba);
}

int _count(BgMask mask) => mask.alpha.where((a) => a >= 128).length;

void main() {
  // 100 x 100: a person at 40-60 x 20-90, a bag touching it at 60-70 x
  // 60-75, a car away at 0-15 x 80-95.
  const personBox = BgBox(40, 20, 60, 90);
  const bagBox = BgBox(60, 60, 70, 75);
  const carBox = BgBox(0, 80, 15, 95);
  final person = _boxes(100, 100, [personBox]);
  final foreground = _boxes(100, 100, [personBox, bagBox, carBox]);
  final remover = BgRemoverFake(person: person, foreground: foreground);
  final photo = BgPhoto(_photo(100, 100));

  test('keep', () async {
    Future<BgMask> mask(BgKeep keep) async => (await bgRemoveBackground(
      remover,
      photo,
      options: BgRemovalOptions(keep: keep),
    )).mask;
    // Person + bag, not the car.
    expect(_count(await mask(BgKeep.personAndCarried)), 20 * 70 + 10 * 15);
    expect(_count(await mask(BgKeep.person)), 20 * 70);
    expect(_count(await mask(BgKeep.foreground)), 20 * 70 + 10 * 15 + 15 * 15);
  });

  test('keep person without a person mask', () async {
    final noPerson = BgRemoverFake(foreground: foreground);
    expect(
      () => bgRemoveBackground(
        noPerson,
        photo,
        options: const BgRemovalOptions(keep: BgKeep.person),
      ),
      throwsUnsupportedError,
    );
    // The default keeps the foreground then.
    final result = await bgRemoveBackground(noPerson, photo);
    expect(_count(result.mask), _count(foreground));
  });

  test('default options change nothing', () {
    final masks = BgEngineMasks(foreground: foreground);
    expect(
      bgFinalMask(masks, const BgRemovalOptions()).alpha,
      foreground.alpha,
    );
  });

  test('crop and output size', () async {
    final result = await bgRemoveBackground(
      remover,
      photo,
      options: const BgRemovalOptions(
        crop: true,
        cropMargin: 5,
        maxOutputSize: 50,
      ),
    );
    // Person + bag: 40-70 x 20-90, plus 5 around.
    expect(result.box, const BgBox(35, 15, 75, 95));
    expect((result.cutout.width, result.cutout.height), (25, 50));
    expect(result.mask.width, 100);
  });

  test('segment at a smaller size', () async {
    final result = await bgRemoveBackground(
      remover,
      photo,
      options: const BgRemovalOptions(maxSegmentSize: 50),
    );
    expect(result.timings.keys, contains('downscale'));
    expect(result.mask.width, 100);
    expect(_count(result.mask), closeTo(20 * 70 + 10 * 15, 200));
  });

  test('clean steps', () {
    // A speck, and a hole in a square.
    final mask = _boxes(100, 100, [
      const BgBox(10, 10, 50, 50),
      const BgBox(80, 80, 82, 82),
    ]);
    for (var y = 20; y < 25; y++) {
      for (var x = 20; x < 25; x++) {
        mask.alpha[y * 100 + x] = 0;
      }
    }
    final noSpeck = bgRemoveSmallRegions(mask, minShare: 0.001);
    expect(_count(noSpeck), 40 * 40 - 25);
    final filled = bgFillHoles(noSpeck);
    expect(_count(filled), 40 * 40);
    // A hole bigger than the limit stays.
    expect(_count(bgFillHoles(noSpeck, maxShare: 0.001)), 40 * 40 - 25);
    final feathered = bgFeather(filled, 2);
    expect(feathered.alpha[30 * 100 + 10], inInclusiveRange(1, 254));
    expect(feathered.alpha[30 * 100 + 30], 255);
    final levels = bgAlphaLevels(
      BgMask(3, 1, Uint8List.fromList([20, 128, 240])),
      low: 32,
      high: 224,
    );
    expect(levels.alpha, [0, 128, 255]);
  });

  test('options json', () {
    const options = BgRemovalOptions(
      keep: BgKeep.person,
      minRegion: 0.005,
      feather: 2,
      maxSegmentSize: 1024,
    );
    final copy = BgRemovalOptions.fromJson(options.toJson());
    expect(copy.toJson(), options.toJson());
    expect(
      BgRemovalOptions.fromJson({}).toJson(),
      const BgRemovalOptions().toJson(),
    );
  });

  test('encoders', () async {
    final result = await bgRemoveBackground(remover, photo);
    final png = result.toPng();
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    final webp = decodeWebp(result.toWebp());
    expect((webp.width, webp.height), (100, 100));
    // Alpha is lossless.
    expect(webp.rgba[(50 * 100 + 50) * 4 + 3], 255);
    expect(webp.rgba[(5 * 100 + 50) * 4 + 3], 0);
  });

  test('fallback', () async {
    final chain = BgRemoverFallback([_Failing(), remover]);
    final result = await bgRemoveBackground(chain, photo);
    expect(result.engine, 'fake');
    expect(chain.current, remover);
  });
}

class _Failing extends BgRemoverFake {
  @override
  String get name => 'failing';

  @override
  Future<BgEngineMasks> segment(
    BgPhoto photo, {
    BgRemovalOptions options = const BgRemovalOptions(),
  }) => throw StateError('native crash');
}

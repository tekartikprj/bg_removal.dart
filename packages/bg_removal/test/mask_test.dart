import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tekartik_bg_removal/bg_removal.dart';
import 'package:tekartik_bg_removal/score.dart';
import 'package:tekartik_bg_removal/tensor.dart';
import 'package:test/test.dart';

BgMask _mask(int width, int height, List<int> ones) {
  final alpha = Uint8List(width * height);
  for (final i in ones) {
    alpha[i] = 255;
  }
  return BgMask(width, height, alpha);
}

BgMask _readMask(String path) {
  final image = img.decodePng(File(path).readAsBytesSync())!;
  final alpha = Uint8List(image.width * image.height);
  var i = 0;
  for (final p in image) {
    alpha[i++] = p.r.toInt();
  }
  return BgMask(image.width, image.height, alpha);
}

void main() {
  test('dilate', () {
    final bin = Uint8List(25)..[12] = 1;
    final out = bgDilate(bin, 5, 5, 1);
    expect(out.where((v) => v == 1).length, 9);
    expect(out[6], 1);
    expect(out[18], 1);
    expect(out[0], 0);
  });

  test('label', () {
    // 0 1 0 1
    // 0 1 0 1
    final bin = Uint8List.fromList([0, 1, 0, 1, 0, 1, 0, 1]);
    final labels = bgLabel(bin, 4, 2);
    expect(labels.count, 2);
    expect(labels.labels[1], labels.labels[5]);
    expect(labels.labels[1], isNot(labels.labels[3]));
  });

  test('combine keeps what touches the person', () {
    // 10 x 1: person at 0-2, a bag at 3-4 (touching), a car at 8-9.
    final person = _mask(10, 1, [0, 1, 2]);
    final salient = _mask(10, 1, [3, 4, 8, 9]);
    final out = bgCombineAnchored(person: person, salient: salient, grow: 0);
    expect(out.alpha.sublist(0, 5), [255, 255, 255, 255, 255]);
    expect(out.alpha[8], 0);
    expect(out.alpha[9], 0);
  });

  test('combine matches the python trial', () {
    for (final name in ['handbag', 'coat']) {
      final out = bgCombineAnchored(
        person: _readMask('test/data/${name}_modnet.png'),
        salient: _readMask('test/data/${name}_u2netp.png'),
      );
      final python = _readMask('test/data/${name}_modnet_u2netp_py.png');
      // The python trial grows the person in a diamond, this in a square.
      expect(bgScore(out, python).iou, greaterThan(0.98), reason: name);
    }
  });

  test('score', () {
    final reference = _mask(4, 1, [0, 1]);
    final score = bgScore(
      _mask(4, 1, [1, 2]),
      reference,
      bags: [const BgBox(0, 0, 4, 1)],
    );
    expect(score.iou, closeTo(1 / 3, 1e-9));
    expect(score.missed, 0.5);
    expect(score.extra, 0.5);
    // Only the reference pixels of the box count: (0 + 255) / 2.
    expect(score.bag, 0.5);
  });

  test('tensor size', () {
    expect(onnxSize(512, 1280, 1920), (512, 768));
    expect(onnxSize(512, 1280, 845), (768, 512));
    const square = BgTensorSpec(square: 320, mean: [0, 0, 0], std: [1, 1, 1]);
    expect(square.sizeFor(1280, 1920), (320, 320));
  });

  test('tensor values', () {
    final rgba = Uint8List(4 * 4 * 4);
    for (var i = 0; i < 16; i++) {
      rgba.setAll(i * 4, [255, 0, 51, 255]);
    }
    const spec = BgTensorSpec(mean: [0.5, 0.5, 0.5], std: [0.5, 0.5, 0.5]);
    final t = bgRgbaImageTensor(BgRgbaImage(4, 4, rgba), spec, 2, 2);
    expect(t.length, 12);
    expect(t[0], closeTo(1, 1e-6));
    expect(t[4], closeTo(-1, 1e-6));
    expect(t[8], closeTo(-0.6, 1e-6));
  });

  test('output mask', () {
    final mask = bgOutputMask([0, 2, 2, 4], 2, 2, BgOutputKind.minMax, 2, 2);
    expect(mask.alpha, [0, 128, 128, 255]);
  });
}

(int, int) onnxSize(int shortSide, int width, int height) => BgTensorSpec(
  shortSide: shortSide,
  mean: const [0, 0, 0],
  std: const [1, 1, 1],
).sizeFor(width, height);

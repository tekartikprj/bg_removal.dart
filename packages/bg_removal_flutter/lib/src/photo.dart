import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:tekartik_bg_removal/bg_removal.dart';

/// Decodes a JPEG, PNG or WebP with the platform decoder (orientation
/// applied).
Future<BgRgbaImage> bgDecodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    try {
      return await bgRgbaImageFromUiImage(frame.image);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// The pixels of [image] (straight alpha, as [BgRgbaImage] holds them).
Future<BgRgbaImage> bgRgbaImageFromUiImage(ui.Image image) async {
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  return BgRgbaImage(
    image.width,
    image.height,
    data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

/// [image] as a `ui.Image`, to draw it (dispose it after use).
Future<ui.Image> bgRgbaImageToUiImage(BgRgbaImage image) async {
  // decodeImageFromPixels takes premultiplied alpha, BgRgbaImage is
  // straight: a transparent pixel would still add its colour.
  final pixels = await _premultiplied(image.rgba);
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    image.width,
    image.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// A photo from an encoded image file. Not on the web: use
/// [bgPhotoFromBytes].
Future<BgPhoto> bgPhotoFromFile(String path) async => BgPhoto(
  await bgDecodeImage(await File(path).readAsBytes()),
  filePath: path,
);

/// A photo from encoded bytes (JPEG, PNG, WebP).
Future<BgPhoto> bgPhotoFromBytes(Uint8List bytes) async =>
    BgPhoto(await bgDecodeImage(bytes));

/// Removes the background of the image file at [path] (see
/// [bgRemoveBackground]); the heavy steps run in an isolate.
Future<BgRemovalResult> bgRemoveBackgroundFromFile(
  BgRemover remover,
  String path, {
  BgRemovalOptions options = const BgRemovalOptions(),
}) async => bgRemoveBackground(
  remover,
  await bgPhotoFromFile(path),
  options: options,
  run: bgRunInIsolate,
);

/// Removes the background of an encoded image (JPEG, PNG, WebP); the heavy
/// steps run in an isolate.
Future<BgRemovalResult> bgRemoveBackgroundFromBytes(
  BgRemover remover,
  Uint8List bytes, {
  BgRemovalOptions options = const BgRemovalOptions(),
}) async => bgRemoveBackground(
  remover,
  await bgPhotoFromBytes(bytes),
  options: options,
  run: bgRunInIsolate,
);

/// Removes the background of image data (RGBA pixels); the heavy steps run
/// in an isolate.
Future<BgRemovalResult> bgRemoveBackgroundFromImage(
  BgRemover remover,
  BgRgbaImage image, {
  BgRemovalOptions options = const BgRemovalOptions(),
}) => bgRemoveBackground(
  remover,
  BgPhoto(image),
  options: options,
  run: bgRunInIsolate,
);

// Top-level: the isolate closure only captures the bytes.
Future<Uint8List> _premultiplied(Uint8List rgba) => bgRunInIsolate(() {
  var opaque = true;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 255) {
      opaque = false;
      break;
    }
  }
  if (opaque) {
    return rgba;
  }
  final out = Uint8List(rgba.length);
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    out[i] = (rgba[i] * a + 127) ~/ 255;
    out[i + 1] = (rgba[i + 1] * a + 127) ~/ 255;
    out[i + 2] = (rgba[i + 2] * a + 127) ~/ 255;
    out[i + 3] = a;
  }
  return out;
});

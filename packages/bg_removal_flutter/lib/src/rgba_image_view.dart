import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:tekartik_bg_removal/bg_removal.dart';

import 'photo.dart';

/// Shows a [BgRgbaImage] (a cut-out), over a checkerboard by default so that
/// the transparent parts show.
class BgRgbaImageView extends StatefulWidget {
  /// The image.
  final BgRgbaImage image;

  /// Draws a checkerboard behind the image.
  final bool checkerboard;

  /// How the image fits its box.
  final BoxFit fit;

  /// A view.
  const BgRgbaImageView(
    this.image, {
    super.key,
    this.checkerboard = true,
    this.fit = BoxFit.contain,
  });

  @override
  State<BgRgbaImageView> createState() => _BgRgbaImageViewState();
}

class _BgRgbaImageViewState extends State<BgRgbaImageView> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BgRgbaImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _load();
    }
  }

  void _load() {
    final image = widget.image;
    bgRgbaImageToUiImage(image).then((result) {
      if (!mounted || widget.image != image) {
        result.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = result;
      });
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = RawImage(image: _image, fit: widget.fit);
    return AspectRatio(
      aspectRatio: widget.image.width / widget.image.height,
      child: widget.checkerboard
          ? CustomPaint(painter: _Checkerboard(), child: image)
          : image,
    );
  }
}

class _Checkerboard extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    final light = Paint()..color = const Color(0xFFFFFFFF);
    final dark = Paint()..color = const Color(0xFFD8D8D8);
    // The last row and column of cells are cut, not drawn past the image.
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, light);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x + y) / cell).round().isOdd) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Checkerboard oldDelegate) => false;
}

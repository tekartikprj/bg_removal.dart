/// The ONNX background removal engine ([BgOnnxRemover]): MODNet for the
/// person, u2netp or IS-Net for the salient objects, on ONNX Runtime.
library;

export 'package:flutter_onnxruntime/flutter_onnxruntime.dart' show OrtProvider;

export 'package:tekartik_bg_removal/models.dart';
export 'src/model_cache.dart';
export 'src/onnx_remover.dart';

import 'tensor.dart';

/// What a model gives.
enum BgOnnxRole {
  /// A person mask (portrait matting).
  person,

  /// A salient object mask (the foreground).
  salient,
}

/// An ONNX model file and how to feed it: the model manifest, shared by
/// the native engine (`tekartik_bg_removal_onnx`) and the web one
/// (`tekartik_bg_removal_web`).
class BgOnnxModel {
  /// Short id, used in the engine name and the timings.
  final String id;

  /// What it is.
  final String description;

  /// What it gives.
  final BgOnnxRole role;

  /// File name in the cache.
  final String fileName;

  /// Where to download it (the original).
  final String url;

  /// A copy that browsers can fetch (CORS): the web engine uses it when
  /// set. Same file, same sha256.
  final String? mirrorUrl;

  /// Its size in bytes.
  final int size;

  /// Its sha256, hex.
  final String sha256;

  /// Its licence.
  final String licence;

  /// Its input.
  final BgTensorSpec tensor;

  /// Its output.
  final BgOutputKind output;

  /// A model.
  const BgOnnxModel({
    required this.id,
    required this.description,
    required this.role,
    required this.fileName,
    required this.url,
    this.mirrorUrl,
    required this.size,
    required this.sha256,
    required this.licence,
    required this.tensor,
    required this.output,
  });

  /// The URL a browser fetches: [mirrorUrl], else [url].
  String get webUrl => mirrorUrl ?? url;

  /// The same model downloaded from `<baseUrl>/<fileName>`: your own
  /// hosting (the default hosts can change; GitHub sends no CORS header).
  BgOnnxModel withBaseUrl(String baseUrl) => BgOnnxModel(
    id: id,
    description: description,
    role: role,
    fileName: fileName,
    url: '${baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'}$fileName',
    size: size,
    sha256: sha256,
    licence: licence,
    tensor: tensor,
    output: output,
  );
}

const _rembg = 'https://github.com/danielgatis/rembg/releases/download/v0.0.0';
const _modnet = 'https://huggingface.co/Xenova/modnet/resolve/main/onnx';
// A Hugging Face copy of the rembg files (same sha256), CORS enabled.
const _rembgMirror = 'https://huggingface.co/tomjackson2023/rembg/resolve/main';

/// MODNet portrait matting, fp16 weights (float32 in and out): the person,
/// 13 MB, short side 512.
const bgOnnxModnetFp16 = BgOnnxModel(
  id: 'modnet',
  description: 'MODNet fp16, person matting, short side 512',
  role: BgOnnxRole.person,
  fileName: 'modnet_fp16.onnx',
  url: '$_modnet/model_fp16.onnx',
  size: 12984781,
  sha256: '25f165da9bfd30830a575f1f0490f1acd995975cb349bc02f3d79332e1fe5cf6',
  licence: 'Apache-2.0',
  tensor: BgTensorSpec(mean: [0.5, 0.5, 0.5], std: [0.5, 0.5, 0.5]),
  output: BgOutputKind.unit,
);

/// U²-Net small, salient object, 4.6 MB, 320².
const bgOnnxU2netp = BgOnnxModel(
  id: 'u2netp',
  description: 'u2netp, salient object, 320²',
  role: BgOnnxRole.salient,
  fileName: 'u2netp.onnx',
  url: '$_rembg/u2netp.onnx',
  mirrorUrl: '$_rembgMirror/u2netp.onnx',
  size: 4574861,
  sha256: '309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8',
  licence: 'Apache-2.0',
  tensor: BgTensorSpec(
    square: 320,
    mean: bgImagenetMean,
    std: bgImagenetStd,
    divideByMax: true,
  ),
  output: BgOutputKind.minMax,
);

/// IS-Net general use, salient object, 179 MB, 1024²: better than u2netp
/// on hard photos, five times slower.
const bgOnnxIsnet = BgOnnxModel(
  id: 'isnet',
  description: 'IS-Net general use, salient object, 1024²',
  role: BgOnnxRole.salient,
  fileName: 'isnet-general-use.onnx',
  url: '$_rembg/isnet-general-use.onnx',
  mirrorUrl: '$_rembgMirror/isnet-general-use.onnx',
  size: 178648008,
  sha256: '60920e99c45464f2ba57bee2ad08c919a52bbf852739e96947fbb4358c0d964a',
  licence: 'Apache-2.0',
  tensor: BgTensorSpec(
    square: 1024,
    mean: [0.5, 0.5, 0.5],
    std: [1, 1, 1],
    divideByMax: true,
  ),
  output: BgOutputKind.minMax,
);

/// The known models.
const bgOnnxModels = [bgOnnxModnetFp16, bgOnnxU2netp, bgOnnxIsnet];

/// The web background removal engine ([BgOnnxWebRemover]): MODNet and
/// u2netp (or IS-Net) on onnxruntime-web, models fetched once and kept in
/// the browser.
library;

export 'package:tekartik_bg_removal/models.dart';

export 'src/model_loader.dart';
export 'src/ort.dart'
    show
        bgOrtWebAllScriptUrl,
        bgOrtWebLoad,
        bgOrtWebVersion,
        bgOrtWebWasmScriptUrl;
export 'src/web_remover.dart';

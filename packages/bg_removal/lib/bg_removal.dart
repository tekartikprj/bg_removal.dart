/// Background removal that keeps a person and what they carry: images and
/// masks, the engine interface ([BgRemover]) and the pipeline
/// ([bgRemoveBackground]). Pure Dart; the engines are in
/// `tekartik_bg_removal_mlkit` and `tekartik_bg_removal_onnx`.
library;

export 'src/image.dart';
export 'src/mask_ops.dart'
    show
        BgLabels,
        bgAlphaLevels,
        bgCombineAnchored,
        bgDilate,
        bgFeather,
        bgFillHoles,
        bgLabel,
        bgRemoveSmallRegions;
export 'src/options.dart';
export 'src/pipeline.dart';
export 'src/remover.dart';
export 'src/run.dart';

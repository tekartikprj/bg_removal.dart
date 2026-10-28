/// Background removal in Flutter: photos from files, bytes or `ui.Image`,
/// the pipeline in an isolate ([bgRemoveBackgroundFromFile]...), and a
/// cut-out view ([BgRgbaImageView]). Exports `tekartik_bg_removal`; the engines
/// are in `tekartik_bg_removal_mlkit` and `tekartik_bg_removal_onnx`.
library;

export 'package:tekartik_bg_removal/bg_removal.dart';

export 'src/photo.dart';
export 'src/rgba_image_view.dart';

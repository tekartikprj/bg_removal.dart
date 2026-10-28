import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:tekartik_bg_removal/bg_removal.dart';
import 'package:tekartik_bg_removal/models.dart';

import 'model_loader.dart';
import 'ort.dart';

/// The ONNX engine in the browser: a person model (MODNet) and a salient
/// model (u2netp or IS-Net) on onnxruntime-web.
///
/// The same models and results as `BgOnnxRemover` of
/// `tekartik_bg_removal_onnx`; either model can be null. The steps around
/// the model run on the page's thread (no isolates on the web), the model
/// itself in onnxruntime-web (wasm threads when the page is cross-origin
/// isolated, or WebGPU).
class BgOnnxWebRemover implements BgRemover {
  /// The person model, or null.
  final BgOnnxModel? person;

  /// The salient model, or null.
  final BgOnnxModel? salient;

  /// Where the model files come from.
  final BgWebModelLoader loader;

  /// onnxruntime-web execution providers, in order: `wasm` (the default),
  /// `webgpu` (needs [bgOrtWebAllScriptUrl]).
  final List<String> executionProviders;

  /// wasm threads, null for onnxruntime-web's default (half the cores, at
  /// most 4, when the page is cross-origin isolated; 1 otherwise).
  final int? numThreads;

  /// The onnxruntime-web script, loaded on [prepare] unless the page has
  /// it.
  final String ortScriptUrl;

  final _sessions = <String, OrtSession>{};

  /// The engine, MODNet + u2netp by default.
  BgOnnxWebRemover({
    this.person = bgOnnxModnetFp16,
    this.salient = bgOnnxU2netp,
    this.loader = const BgWebModelLoader(),
    this.executionProviders = const ['wasm'],
    this.numThreads,
    String? ortScriptUrl,
  }) : ortScriptUrl =
           ortScriptUrl ??
           (executionProviders.contains('webgpu')
               ? bgOrtWebAllScriptUrl
               : bgOrtWebWasmScriptUrl) {
    if (person == null && salient == null) {
      throw ArgumentError('a person or a salient model');
    }
  }

  List<BgOnnxModel> get _models => [?person, ?salient];

  @override
  String get name =>
      'onnx-web:${_models.map((m) => m.id).join('+')}'
      '${executionProviders.first == 'wasm' ? '' : ' (${executionProviders.first})'}';

  @override
  Future<BgRemoverStatus> getStatus() async =>
      _models.every((m) => _sessions.containsKey(m.id))
      ? BgRemoverStatus.ready
      : BgRemoverStatus.needsPrepare;

  @override
  Future<void> prepare({void Function(String status)? onStatus}) async {
    if (_models.every((m) => _sessions.containsKey(m.id))) {
      return;
    }
    onStatus?.call('loading onnxruntime-web');
    await bgOrtWebLoad(ortScriptUrl);
    final threads = numThreads;
    if (threads != null) {
      ortWasmEnv.numThreads = threads;
    }
    for (final model in _models) {
      if (_sessions.containsKey(model.id)) {
        continue;
      }
      final bytes = await loader.load(model, onStatus: onStatus);
      onStatus?.call('loading ${model.id}');
      final options = JSObject()
        ..['executionProviders'] = executionProviders
            .map((p) => p.toJS)
            .toList()
            .toJS
        ..['graphOptimizationLevel'] = 'all'.toJS;
      _sessions[model.id] = await OrtSession.create(bytes.toJS, options).toDart;
    }
  }

  @override
  Future<BgEngineMasks> segment(
    BgPhoto photo, {
    BgRemovalOptions options = const BgRemovalOptions(),
  }) async {
    await prepare();
    final person = this.person;
    final salient = this.salient;
    final runPerson =
        person != null &&
        (options.keep != BgKeep.foreground || salient == null);
    final runSalient =
        salient != null && (options.keep != BgKeep.person || person == null);
    final timings = <String, Duration>{};
    return BgEngineMasks(
      person: runPerson ? await _run(person, photo.image, timings) : null,
      foreground: runSalient ? await _run(salient, photo.image, timings) : null,
      timings: timings,
    );
  }

  Future<BgMask> _run(
    BgOnnxModel model,
    BgRgbaImage image,
    Map<String, Duration> timings,
  ) async {
    final session = _sessions[model.id]!;
    final (width, height) = model.tensor.sizeFor(image.width, image.height);
    final sw = Stopwatch()..start();
    final input = bgRgbaImageTensor(image, model.tensor, width, height);
    timings['${model.id}.prepare'] = sw.elapsed;
    sw.reset();
    final tensor = OrtTensor(
      'float32',
      input.toJS,
      [1.toJS, 3.toJS, height.toJS, width.toJS].toJS,
    );
    final feeds = JSObject()..[session.inputNames.toDart.first.toDart] = tensor;
    final outputs = await session.run(feeds).toDart;
    final output =
        outputs[session.outputNames.toDart.first.toDart]! as OrtTensor;
    final values = Float32List.fromList(output.data.toDart);
    tensor.dispose();
    for (final name in session.outputNames.toDart) {
      (outputs[name.toDart] as OrtTensor?)?.dispose();
    }
    timings['${model.id}.infer'] = sw.elapsed;
    sw.reset();
    final mask = bgOutputMask(
      values,
      width,
      height,
      model.output,
      image.width,
      image.height,
    );
    timings['${model.id}.post'] = sw.elapsed;
    return mask;
  }

  @override
  Future<void> close() async {
    for (final session in _sessions.values) {
      await session.release().toDart;
    }
    _sessions.clear();
  }
}

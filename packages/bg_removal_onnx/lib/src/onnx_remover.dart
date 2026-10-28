import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:tekartik_bg_removal/bg_removal.dart';

import 'package:tekartik_bg_removal/models.dart';
import 'model_cache.dart';

/// The ONNX engine: a person model (MODNet) and a salient model (u2netp or
/// IS-Net), on ONNX Runtime. Android and Linux (the web comes later).
///
/// Either model can be null: `BgOnnxRemover(salient: null)` is MODNet
/// alone. A model that [BgRemovalOptions.keep] does not need is not run.
class BgOnnxRemover implements BgRemover {
  /// The person model, or null.
  final BgOnnxModel? person;

  /// The salient model, or null.
  final BgOnnxModel? salient;

  /// Where the model files come from.
  final BgOnnxModelCache cache;

  /// Execution providers, in order: CPU (the default), XNNPACK, NNAPI
  /// (Android). The CPU is added last when missing.
  final List<OrtProvider> providers;

  /// Threads, null for the runtime default.
  final int? threads;

  final _sessions = <String, OrtSession>{};

  /// The engine, MODNet + u2netp by default.
  BgOnnxRemover({
    this.person = bgOnnxModnetFp16,
    this.salient = bgOnnxU2netp,
    BgOnnxModelCache? cache,
    this.providers = const [OrtProvider.CPU],
    this.threads,
  }) : cache = cache ?? BgOnnxModelCache() {
    if (person == null && salient == null) {
      throw ArgumentError('a person or a salient model');
    }
    if (person != null && person!.role != BgOnnxRole.person) {
      throw ArgumentError('${person!.id} is not a person model');
    }
    if (salient != null && salient!.role != BgOnnxRole.salient) {
      throw ArgumentError('${salient!.id} is not a salient model');
    }
  }

  List<BgOnnxModel> get _models => [?person, ?salient];

  @override
  String get name => 'onnx:${_models.map((m) => m.id).join('+')}';

  /// The provider list, CPU last.
  List<OrtProvider> get _providers => [
    ...providers.where((p) => p != OrtProvider.CPU),
    OrtProvider.CPU,
  ];

  @override
  Future<BgRemoverStatus> getStatus() async {
    if (kIsWeb) {
      return BgRemoverStatus.unsupported;
    }
    return _models.every((m) => _sessions.containsKey(m.id))
        ? BgRemoverStatus.ready
        : BgRemoverStatus.needsPrepare;
  }

  @override
  Future<void> prepare({void Function(String status)? onStatus}) async {
    if (kIsWeb) {
      throw UnsupportedError('$name: not on the web yet');
    }
    for (final model in _models) {
      if (_sessions.containsKey(model.id)) {
        continue;
      }
      final path = await cache.path(model, onStatus: onStatus);
      onStatus?.call('loading ${model.id}');
      _sessions[model.id] = await OnnxRuntime().createSession(
        path,
        options: OrtSessionOptions(
          providers: _providers,
          intraOpNumThreads: threads,
        ),
      );
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
    // Skip the model the result will not use.
    final runPerson =
        person != null &&
        (options.keep != BgKeep.foreground || salient == null);
    final runSalient =
        salient != null && (options.keep != BgKeep.person || person == null);
    final timings = <String, Duration>{};
    BgMask? personMask;
    BgMask? salientMask;
    if (runPerson) {
      personMask = await _run(person, photo.image, timings);
    }
    if (runSalient) {
      salientMask = await _run(salient, photo.image, timings);
    }
    return BgEngineMasks(
      person: personMask,
      foreground: salientMask,
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
    final input = await _tensor(image, model.tensor, width, height);
    timings['${model.id}.prepare'] = sw.elapsed;
    sw.reset();
    final value = await OrtValue.fromList(input, [1, 3, height, width]);
    final outputs = await session.run({session.inputNames.first: value});
    final output = outputs[session.outputNames.first]!;
    final list = await output.asFlattenedList();
    timings['${model.id}.infer'] = sw.elapsed;
    await value.dispose();
    for (final o in outputs.values) {
      await o.dispose();
    }
    sw.reset();
    final values = Float32List(list.length);
    for (var i = 0; i < values.length; i++) {
      values[i] = (list[i] as num).toDouble();
    }
    final mask = await _outputMask(
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
      await session.close();
    }
    _sessions.clear();
  }
}

// Top-level: the isolate closures only capture their arguments.

Future<Float32List> _tensor(
  BgRgbaImage image,
  BgTensorSpec spec,
  int width,
  int height,
) => bgRunInIsolate(() => bgRgbaImageTensor(image, spec, width, height));

Future<BgMask> _outputMask(
  Float32List values,
  int width,
  int height,
  BgOutputKind kind,
  int imageWidth,
  int imageHeight,
) => bgRunInIsolate(
  () => bgOutputMask(values, width, height, kind, imageWidth, imageHeight),
);

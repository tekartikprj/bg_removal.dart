// Bindings of the onnxruntime-web global (`ort`), loaded by a script tag.
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The onnxruntime-web version used by default.
const bgOrtWebVersion = '1.30.0';

/// The wasm build (CPU, 14 MB of wasm).
const bgOrtWebWasmScriptUrl =
    'https://cdn.jsdelivr.net/npm/onnxruntime-web@$bgOrtWebVersion/dist/ort.wasm.min.js';

/// The full build: WebGPU and wasm (28 MB of wasm).
const bgOrtWebAllScriptUrl =
    'https://cdn.jsdelivr.net/npm/onnxruntime-web@$bgOrtWebVersion/dist/ort.min.js';

@JS('ort')
external JSObject? get _ort;

@JS('ort.env.wasm')
external OrtWasmEnv get ortWasmEnv;

/// `ort.env.wasm`.
extension type OrtWasmEnv._(JSObject _) implements JSObject {
  /// Threads (set before the first session; needs cross-origin isolation).
  external int? numThreads;

  /// Where the wasm files are.
  external String? wasmPaths;
}

/// `ort.InferenceSession`.
@JS('ort.InferenceSession')
extension type OrtSession._(JSObject _) implements JSObject {
  /// Creates a session from the model bytes.
  external static JSPromise<OrtSession> create(
    JSUint8Array model, [
    JSObject options,
  ]);

  /// Input names.
  external JSArray<JSString> get inputNames;

  /// Output names.
  external JSArray<JSString> get outputNames;

  /// Runs the model.
  external JSPromise<JSObject> run(JSObject feeds);

  /// Frees the session.
  external JSPromise<JSAny?> release();
}

/// `ort.Tensor`.
@JS('ort.Tensor')
extension type OrtTensor._(JSObject _) implements JSObject {
  /// A float32 tensor.
  external factory OrtTensor(
    String type,
    JSFloat32Array data,
    JSArray<JSNumber> dims,
  );

  /// The values (CPU tensors).
  external JSFloat32Array get data;

  /// Frees the tensor.
  external void dispose();
}

final _loads = <String, Future<void>>{};

/// Loads the onnxruntime-web script from [scriptUrl] once (nothing to do
/// when the page already has `ort`).
Future<void> bgOrtWebLoad(String scriptUrl) {
  if (_ort != null) {
    return Future.value();
  }
  return _loads[scriptUrl] ??= () async {
    final script = web.HTMLScriptElement()
      ..src = scriptUrl
      ..crossOrigin = 'anonymous';
    final loaded = Completer<void>();
    script
      ..onload = ((web.Event _) => loaded.complete()).toJS
      ..onerror = ((web.Event _) => loaded.completeError(
        StateError('cannot load $scriptUrl'),
      )).toJS;
    web.document.head!.append(script);
    await loaded.future;
    // The wasm files sit next to the script.
    ortWasmEnv.wasmPaths = scriptUrl.substring(
      0,
      scriptUrl.lastIndexOf('/') + 1,
    );
  }();
}

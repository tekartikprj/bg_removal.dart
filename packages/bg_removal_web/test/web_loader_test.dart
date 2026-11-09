@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:tekartik_bg_removal_web/bg_removal_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

@JS('Object.defineProperty')
external void _defineProperty(JSObject target, String name, JSObject desc);

@JS('Object.getOwnPropertyDescriptor')
external JSObject? _getOwnPropertyDescriptor(JSObject target, String name);

/// Runs [body] without the Cache API (`caches`, a data: url cannot be
/// cached) and, when [webCrypto] is false, without `crypto.subtle`: a plain
/// http page (not https, not localhost) has neither.
Future<T> _withoutCache<T>(
  Future<T> Function() body, {
  required bool webCrypto,
}) async {
  final crypto =
      (globalContext['Crypto']! as JSObject)['prototype']! as JSObject;
  final window = globalContext;
  final subtle = _getOwnPropertyDescriptor(crypto, 'subtle')!;
  final caches = _getOwnPropertyDescriptor(window, 'caches')!;
  JSObject missing() => JSObject()
    ..['configurable'] = true.toJS
    ..['get'] = (() => null).toJS;
  if (!webCrypto) {
    _defineProperty(crypto, 'subtle', missing());
  }
  _defineProperty(window, 'caches', missing());
  try {
    return await body();
  } finally {
    _defineProperty(crypto, 'subtle', subtle);
    _defineProperty(window, 'caches', caches);
  }
}

void main() {
  test('a model loads on a plain http page', () async {
    final bytes = utf8.encode('not a model, 26 bytes long');
    final model = BgOnnxModel(
      id: 'tiny',
      description: 'tiny',
      role: BgOnnxRole.person,
      fileName: 'tiny.onnx',
      url: 'data:application/octet-stream;base64,${base64.encode(bytes)}',
      size: bytes.length,
      sha256:
          '69e94d6c78c27eec0e9a178684ea2bd7b35cc26ea7b44141cde21ff10bdf377d',
      licence: 'none',
      tensor: const BgTensorSpec(mean: [0, 0, 0], std: [1, 1, 1]),
      output: BgOutputKind.unit,
    );
    Future<List<int>> load() => const BgWebModelLoader().load(model);
    expect(await _withoutCache(load, webCrypto: true), bytes);
    expect(await _withoutCache(load, webCrypto: false), bytes);

    // Another file of the same size is still refused.
    final other = utf8.encode('not a model, 26 bytes LONG');
    final otherModel = BgOnnxModel(
      id: model.id,
      description: model.description,
      role: model.role,
      fileName: model.fileName,
      url: 'data:application/octet-stream;base64,${base64.encode(other)}',
      size: model.size,
      sha256: model.sha256,
      licence: model.licence,
      tensor: model.tensor,
      output: model.output,
    );
    await expectLater(
      _withoutCache(
        () => const BgWebModelLoader().load(otherModel),
        webCrypto: false,
      ),
      throwsStateError,
    );
  });

  test('a failed script load is tried again', () async {
    // Nothing listens on port 9 (discard): the script fails to load.
    const url = 'http://127.0.0.1:9/no_onnxruntime_here.js';
    var inserted = 0;
    final observer = web.MutationObserver(
      ((JSArray<web.MutationRecord> records, web.MutationObserver _) {
        for (final record in records.toDart) {
          for (var i = 0; i < record.addedNodes.length; i++) {
            final node = record.addedNodes.item(i);
            if (node.isA<web.HTMLScriptElement>() &&
                (node as web.HTMLScriptElement).src == url) {
              inserted++;
            }
          }
        }
      }).toJS,
    );
    observer.observe(
      web.document.head!,
      web.MutationObserverInit(childList: true),
    );
    try {
      await expectLater(bgOrtWebLoad(url), throwsStateError);
      // Offline at the first prepare, then back online: loaded again.
      await expectLater(bgOrtWebLoad(url), throwsStateError);
      // Mutation records are delivered in a microtask.
      await Future<void>.delayed(Duration.zero);
      expect(inserted, 2);
      expect(web.document.querySelectorAll('script[src="$url"]').length, 0);
    } finally {
      observer.disconnect();
    }
  });
}

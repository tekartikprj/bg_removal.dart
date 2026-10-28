import 'dart:js_interop';
import 'dart:typed_data';

import 'package:tekartik_bg_removal/models.dart';
import 'package:web/web.dart' as web;

/// The browser cache (Cache API) holding the model files.
const bgWebModelCacheName = 'tekartik_bg_removal_models';

/// Fetches model files once, checked by size and sha256, and keeps them in
/// the browser (Cache API, when the page is https or localhost).
class BgWebModelLoader {
  /// Models come from `<baseUrl>/<fileName>` when set (your own hosting),
  /// else from [BgOnnxModel.webUrl].
  final String? baseUrl;

  /// A loader.
  const BgWebModelLoader({this.baseUrl});

  /// The URL of [model].
  String url(BgOnnxModel model) {
    final baseUrl = this.baseUrl;
    return baseUrl == null ? model.webUrl : model.withBaseUrl(baseUrl).url;
  }

  /// The bytes of [model]; [onStatus] reports the download.
  Future<Uint8List> load(
    BgOnnxModel model, {
    void Function(String status)? onStatus,
  }) async {
    final url = this.url(model);
    final cache = await _cache();
    if (cache != null) {
      final cached = await cache.match(url.toJS).toDart;
      if (cached != null) {
        final bytes = (await cached.arrayBuffer().toDart).toDart.asUint8List();
        if (await _matches(bytes, model)) {
          return bytes;
        }
        await cache.delete(url.toJS).toDart;
      }
    }
    final bytes = await _fetch(url, model, onStatus);
    if (!await _matches(bytes, model)) {
      throw StateError(
        '${model.fileName}: ${bytes.length} bytes, not the expected file '
        '(${model.size} bytes, sha256 ${model.sha256})',
      );
    }
    if (cache != null) {
      await cache.put(url.toJS, web.Response(bytes.toJS)).toDart;
    }
    return bytes;
  }

  /// Whether [model] is in the browser cache.
  Future<bool> isCached(BgOnnxModel model) async {
    final cache = await _cache();
    if (cache == null) return false;
    return await cache.match(url(model).toJS).toDart != null;
  }

  Future<web.Cache?> _cache() async {
    try {
      return await web.window.caches.open(bgWebModelCacheName).toDart;
    } catch (_) {
      // No Cache API (http page, private mode): download each time.
      return null;
    }
  }
}

Future<Uint8List> _fetch(
  String url,
  BgOnnxModel model,
  void Function(String status)? onStatus,
) async {
  final response = await web.window.fetch(url.toJS).toDart;
  if (!response.ok) {
    throw StateError('${response.status} for $url');
  }
  final reader = response.body!.getReader() as web.ReadableStreamDefaultReader;
  final builder = BytesBuilder(copy: false);
  var lastPercent = -1;
  while (true) {
    final chunk = await reader.read().toDart;
    if (chunk.done) break;
    builder.add((chunk.value! as JSUint8Array).toDart);
    final percent = builder.length * 100 ~/ model.size;
    if (percent != lastPercent) {
      lastPercent = percent;
      onStatus?.call('${model.fileName} $percent %');
    }
  }
  return builder.takeBytes();
}

Future<bool> _matches(Uint8List bytes, BgOnnxModel model) async {
  if (bytes.length != model.size) {
    return false;
  }
  final digest = await web.window.crypto.subtle
      .digest('SHA-256'.toJS, bytes.toJS)
      .toDart;
  final hex = (digest! as JSArrayBuffer).toDart
      .asUint8List()
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return hex == model.sha256;
}

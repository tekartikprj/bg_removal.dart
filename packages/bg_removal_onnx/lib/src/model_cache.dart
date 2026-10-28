import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'package:tekartik_bg_removal/models.dart';

/// Downloads model files once, checked by size and sha256.
///
/// The files go to [dir] (default: `tekartik_bg_removal/models` in the
/// app's support folder). [localDirs] are looked at first, without a
/// download (a folder of `.onnx` files on Linux, for example).
class BgOnnxModelCache {
  /// The cache folder, null for the default.
  final String? dir;

  /// Folders to look at before downloading.
  final List<String> localDirs;

  /// A cache.
  BgOnnxModelCache({this.dir, this.localDirs = const []});

  Future<Directory> _dir() async => Directory(
    dir ??
        join(
          (await getApplicationSupportDirectory()).path,
          'tekartik_bg_removal',
          'models',
        ),
  );

  File? _local(BgOnnxModel model) {
    for (final localDir in localDirs) {
      final local = File(join(localDir, model.fileName));
      if (local.existsSync() && local.lengthSync() == model.size) {
        return local;
      }
    }
    return null;
  }

  /// Whether [model] is there, without a download.
  Future<bool> isCached(BgOnnxModel model) async {
    if (_local(model) != null) {
      return true;
    }
    final file = File(join((await _dir()).path, model.fileName));
    final checked = File('${file.path}.sha256');
    return file.existsSync() &&
        file.lengthSync() == model.size &&
        checked.existsSync() &&
        checked.readAsStringSync() == model.sha256;
  }

  /// The local path of [model], downloaded first if needed; [onStatus]
  /// reports the download progress.
  Future<String> path(
    BgOnnxModel model, {
    void Function(String status)? onStatus,
  }) async {
    final local = _local(model);
    if (local != null) {
      return local.path;
    }
    final dir = await _dir();
    final file = File(join(dir.path, model.fileName));
    if (await isCached(model)) {
      return file.path;
    }
    final checked = File('${file.path}.sha256');
    await dir.create(recursive: true);
    final part = File('${file.path}.part');
    final client = http.Client();
    try {
      final response = await client.send(
        http.Request('GET', Uri.parse(model.url)),
      );
      if (response.statusCode != 200) {
        throw HttpException(
          '${response.statusCode} for ${model.url}',
          uri: Uri.parse(model.url),
        );
      }
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      final sink = part.openWrite();
      var received = 0;
      var lastPercent = -1;
      await for (final chunk in response.stream) {
        hasher.add(chunk);
        sink.add(chunk);
        received += chunk.length;
        final percent = received * 100 ~/ model.size;
        if (percent != lastPercent) {
          lastPercent = percent;
          onStatus?.call('${model.fileName} $percent %');
        }
      }
      await sink.close();
      hasher.close();
      final digest = digestSink.value.toString();
      if (received != model.size || digest != model.sha256) {
        await part.delete();
        throw StateError(
          '${model.fileName}: got $received bytes, sha256 $digest, '
          'expected ${model.size} bytes, ${model.sha256}',
        );
      }
      await part.rename(file.path);
      await checked.writeAsString(model.sha256);
      return file.path;
    } finally {
      client.close();
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

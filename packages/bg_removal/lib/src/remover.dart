import 'image.dart';
import 'options.dart';

/// A photo to segment: its pixels, and its file when there is one (an
/// engine that reads files, such as ML Kit, can use it).
class BgPhoto {
  /// The pixels, orientation applied.
  final BgRgbaImage image;

  /// The encoded file the pixels come from, if any.
  final String? filePath;

  /// A photo.
  const BgPhoto(this.image, {this.filePath});

  /// Width.
  int get width => image.width;

  /// Height.
  int get height => image.height;
}

/// Whether an engine can run.
enum BgRemoverStatus {
  /// Ready: [BgRemover.segment] runs at once.
  ready,

  /// Supported, but [BgRemover.prepare] has work to do (a model to
  /// download or to load).
  needsPrepare,

  /// Not on this platform or device (or it crashed here before).
  unsupported,
}

/// What an engine sees in a photo. The masks have the photo's size.
class BgEngineMasks {
  /// The person, when the engine has a person model (MODNet).
  final BgMask? person;

  /// The foreground: salient objects (u2netp, IS-Net) or "all subjects"
  /// (ML Kit).
  final BgMask? foreground;

  /// Where the time went, by step (`<model>.infer`...).
  final Map<String, Duration> timings;

  /// A result.
  BgEngineMasks({this.person, this.foreground, this.timings = const {}}) {
    if (person == null && foreground == null) {
      throw ArgumentError('an engine gives a person or a foreground mask');
    }
  }

  /// The photo size (the masks' size).
  (int width, int height) get size {
    final mask = person ?? foreground!;
    return (mask.width, mask.height);
  }
}

/// A segmentation engine: one photo in, raw masks out. The pipeline
/// (`bgRemoveBackground`) turns them into a cut-out.
abstract class BgRemover {
  /// Short name, such as `mlkit` or `onnx:modnet+u2netp`.
  String get name;

  /// Whether it can run here, and whether [prepare] has work to do.
  Future<BgRemoverStatus> getStatus();

  /// Downloads and loads what the engine needs; [onStatus] reports
  /// progress. Throws when the engine cannot run.
  Future<void> prepare({void Function(String status)? onStatus});

  /// Segments [photo] (after [prepare]).
  Future<BgEngineMasks> segment(
    BgPhoto photo, {
    BgRemovalOptions options = const BgRemovalOptions(),
  });

  /// Releases the engine.
  Future<void> close();
}

/// The person mask of one engine with the foreground mask of another (the
/// ONNX MODNet person with the ML Kit subjects, for example).
class BgRemoverMerge implements BgRemover {
  /// Gives the person mask.
  final BgRemover person;

  /// Gives the foreground mask.
  final BgRemover foreground;

  /// A merge.
  BgRemoverMerge({required this.person, required this.foreground});

  @override
  String get name => '${foreground.name}+${person.name}';

  @override
  Future<BgRemoverStatus> getStatus() async {
    final statuses = [await person.getStatus(), await foreground.getStatus()];
    if (statuses.contains(BgRemoverStatus.unsupported)) {
      return BgRemoverStatus.unsupported;
    }
    return statuses.every((s) => s == BgRemoverStatus.ready)
        ? BgRemoverStatus.ready
        : BgRemoverStatus.needsPrepare;
  }

  @override
  Future<void> prepare({void Function(String status)? onStatus}) async {
    await person.prepare(onStatus: onStatus);
    await foreground.prepare(onStatus: onStatus);
  }

  @override
  Future<BgEngineMasks> segment(
    BgPhoto photo, {
    BgRemovalOptions options = const BgRemovalOptions(),
  }) async {
    final p = await person.segment(photo, options: options);
    final f = await foreground.segment(photo, options: options);
    return BgEngineMasks(
      person: p.person,
      foreground: f.foreground,
      timings: {...p.timings, ...f.timings},
    );
  }

  @override
  Future<void> close() async {
    await person.close();
    await foreground.close();
  }
}

/// The first engine of [removers] that prepares, then the next ones when a
/// segmentation fails: ML Kit on Android, then the ONNX pair.
class BgRemoverFallback implements BgRemover {
  /// The engines, best first.
  final List<BgRemover> removers;

  BgRemover? _current;
  var _index = 0;

  /// A fallback chain.
  BgRemoverFallback(this.removers) {
    if (removers.isEmpty) {
      throw ArgumentError('no engine');
    }
  }

  /// The engine in use, after [prepare].
  BgRemover? get current => _current;

  @override
  String get name => _current?.name ?? removers.map((r) => r.name).join('|');

  @override
  Future<BgRemoverStatus> getStatus() async {
    final current = _current;
    if (current != null) {
      return current.getStatus();
    }
    var result = BgRemoverStatus.unsupported;
    for (final remover in removers) {
      final status = await remover.getStatus();
      if (status == BgRemoverStatus.ready) {
        return status;
      }
      if (status == BgRemoverStatus.needsPrepare) {
        result = status;
      }
    }
    return result;
  }

  @override
  Future<void> prepare({void Function(String status)? onStatus}) async {
    if (_current != null) {
      return;
    }
    Object? lastError;
    for (; _index < removers.length; _index++) {
      final remover = removers[_index];
      if (await remover.getStatus() == BgRemoverStatus.unsupported) {
        continue;
      }
      try {
        await remover.prepare(onStatus: onStatus);
        _current = remover;
        return;
      } catch (e) {
        lastError = e;
        onStatus?.call('${remover.name}: $e');
      }
    }
    throw StateError('no engine could prepare (last error: $lastError)');
  }

  @override
  Future<BgEngineMasks> segment(
    BgPhoto photo, {
    BgRemovalOptions options = const BgRemovalOptions(),
  }) async {
    while (true) {
      await prepare();
      try {
        return await _current!.segment(photo, options: options);
      } catch (_) {
        if (_index + 1 >= removers.length) {
          rethrow;
        }
        _current = null;
        _index++;
      }
    }
  }

  @override
  Future<void> close() async {
    for (final remover in removers) {
      await remover.close();
    }
    _current = null;
    _index = 0;
  }
}

/// An engine that returns given masks, resized to the photo: for tests and
/// for UI work without a model.
class BgRemoverFake implements BgRemover {
  /// The person mask, if any.
  final BgMask? person;

  /// The foreground mask, if any.
  final BgMask? foreground;

  /// A fake engine.
  BgRemoverFake({this.person, this.foreground});

  @override
  String get name => 'fake';

  @override
  Future<BgRemoverStatus> getStatus() async => BgRemoverStatus.ready;

  @override
  Future<void> prepare({void Function(String status)? onStatus}) async {}

  @override
  Future<BgEngineMasks> segment(
    BgPhoto photo, {
    BgRemovalOptions options = const BgRemovalOptions(),
  }) async => BgEngineMasks(
    person: person?.resized(photo.width, photo.height),
    foreground: foreground?.resized(photo.width, photo.height),
  );

  @override
  Future<void> close() async {}
}

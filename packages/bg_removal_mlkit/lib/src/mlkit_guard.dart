import 'dart:io';

import 'package:synchronized/synchronized.dart';

/// The crash guard of the ML Kit engine: a file written before each ML Kit
/// call and deleted after it. A native crash kills the app before the
/// delete, so the file left behind says that ML Kit crashed; a Dart error
/// (a `PlatformException`) deletes it like a success.
///
/// The calls run one at a time: two calls in flight would share the file
/// (the first to end would delete the guard of the other).
class BgMlKitGuard {
  /// The guard file.
  final Future<File> Function() file;

  final _lock = Lock();

  /// A guard on [file].
  BgMlKitGuard(this.file);

  /// Runs [call] with the guard file holding [what].
  Future<T> run<T>(String what, Future<T> Function() call) =>
      _lock.synchronized(() async {
        final guard = await file();
        await guard.writeAsString(
          '$what, ${DateTime.now().toIso8601String()}',
          flush: true,
        );
        try {
          return await call();
        } finally {
          // clearCrash may have deleted it meanwhile.
          if (guard.existsSync()) {
            await guard.delete();
          }
        }
      });
}

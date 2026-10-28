import 'dart:typed_data';

/// What the bench needs from the platform: files on Android and Linux,
/// nothing on the web. Each app has its own.
abstract class BenchHost {
  /// One line about the device (system, cpus...).
  String get platform;

  /// Max resident memory of the process, MB, null when unknown.
  int? get maxRssMb;

  /// Writes a temporary file and returns its path, for the engines that
  /// read files (ML Kit); null without files (web).
  Future<String?> tempFile(String name, Uint8List bytes);

  /// Saves a run output (report, masks) at [path] in the run folder;
  /// nothing without files.
  Future<void> save(String path, Uint8List bytes);

  /// Where the run outputs go, null without files.
  String? get outDir;

  /// The report of a finished run (markdown): printed as `BENCH|` lines,
  /// and sent where the app's tool reads it.
  Future<void> publish(String markdown);
}

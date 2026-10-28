import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The app's package on Android.
const appPackage = 'com.tekartik.bg_removal_bench';

/// The app on a device over adb.
class AdbApp {
  /// The adb serial, null for the only device.
  final String? device;

  /// An app on [device] (default: `ANDROID_SERIAL`).
  AdbApp(String? device)
    : device = device ?? Platform.environment['ANDROID_SERIAL'];

  List<String> get _serial => [
    if (device != null) ...['-s', device!],
  ];

  /// Runs adb, returns its trimmed stdout.
  String adb(List<String> args) =>
      (Process.runSync('adb', [..._serial, ...args]).stdout as String).trim();

  /// `model, Android release, abi`.
  String describe() =>
      '${adb(['shell', 'getprop', 'ro.product.model'])}, '
      'Android ${adb(['shell', 'getprop', 'ro.build.version.release'])}, '
      '${adb(['shell', 'getprop', 'ro.product.cpu.abi'])}';

  /// Builds a release APK of [target] for the device's abi and installs it.
  Future<void> buildAndInstall(String target, List<String> defines) async {
    final abi = adb(['shell', 'getprop', 'ro.product.cpu.abi']);
    final platform = switch (abi) {
      'arm64-v8a' => 'android-arm64',
      'x86_64' => 'android-x64',
      _ => throw StateError('unsupported abi $abi'),
    };
    await run('flutter', [
      'build',
      'apk',
      '--release',
      '--split-per-abi',
      '--target-platform',
      platform,
      '-t',
      target,
      ...defines,
    ]);
    await run('adb', [
      ..._serial,
      'install',
      '-r',
      'build/app/outputs/flutter-apk/app-$abi-release.apk',
    ]);
  }

  /// Starts the app afresh, with an empty logcat.
  void start() {
    adb(['shell', 'am', 'force-stop', appPackage]);
    adb(['logcat', '-c']);
    adb(['shell', 'am', 'start', '-n', '$appPackage/.MainActivity']);
  }

  /// Whether the app process is alive.
  bool get isRunning => adb(['shell', 'pidof', appPackage]).isNotEmpty;

  /// The app's `print` lines starting with [prefix] (prefix removed).
  List<String> printed(String prefix) => [
    for (final line in const LineSplitter().convert(
      adb(['logcat', '-d', '-v', 'raw', 'flutter:I', '*:S']),
    ))
      if (line.startsWith(prefix)) line.substring(prefix.length),
  ];

  /// The head of the last native crash (signal, abort message, top frames).
  String lastCrash() {
    final lines = const LineSplitter().convert(
      adb(['logcat', '-d', '-b', 'crash', '-v', 'raw']),
    );
    final start = lines.lastIndexWhere((l) => l.startsWith('Fatal signal'));
    if (start < 0) return '';
    return [
      lines[start],
      for (final l in lines.skip(start))
        if (RegExp(r'^\s+#0[0-5] ').hasMatch(l)) l.trim(),
    ].join('\n');
  }

  /// Saves a screenshot to [path].
  Future<void> screenshot(String path) async {
    final result = await Process.run('adb', [
      ..._serial,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null);
    File(path).writeAsBytesSync(result.stdout as List<int>);
  }
}

/// A file stamp: `20261028_154500`.
String fileStamp() => DateTime.now()
    .toIso8601String()
    .substring(0, 19)
    .replaceAll(RegExp('[-:]'), '')
    .replaceAll('T', '_');

/// Runs [executable] with the console attached, throws on failure.
Future<void> run(String executable, List<String> args) async {
  stdout.writeln('\$ $executable ${args.join(' ')}');
  final process = await Process.start(
    executable,
    args,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, args, 'exit code $code', code);
  }
}

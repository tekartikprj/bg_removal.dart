// Takes the README screenshot: the sample photo with and without its
// background, on a phone over adb.
//
//   dart run tool/screenshot.dart [--device SERIAL] [--out FILE]
//
// Builds a release APK that opens the sample at start, installs it, waits
// for the cut-out (restarting the app once if ML Kit crashed it: the next
// start uses the ONNX engine), then saves the screen to
// ../../doc/screenshots/example.png (half size, no system bars).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart';
import 'package:process_run/shell.dart'
    show Shell, ShellOptions, runExecutableArguments;

const _package = 'com.tekartik.bg_removal_example';

Future<void> main(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf('--$name');
    return i < 0 || i + 1 >= args.length ? null : args[i + 1];
  }

  final device = option('device') ?? Platform.environment['ANDROID_SERIAL'];
  final out =
      option('out') ?? join('..', '..', 'doc', 'screenshots', 'example.png');
  final serial = [
    if (device != null) ...['-s', device],
  ];
  final adbShell = Shell(verbose: false, throwOnError: false);
  String adb(List<String> args) =>
      (adbShell.runExecutableArgumentsSync('adb', [...serial, ...args]).stdout
              as String)
          .trim();

  final abi = adb(['shell', 'getprop', 'ro.product.cpu.abi']);
  final platform = switch (abi) {
    'arm64-v8a' => 'android-arm64',
    'x86_64' => 'android-x64',
    _ => throw StateError('unsupported abi "$abi" (no device?)'),
  };
  await _run('flutter', [
    'build',
    'apk',
    '--release',
    '--split-per-abi',
    '--target-platform',
    platform,
    '--dart-define=EXAMPLE_SAMPLE=true',
  ]);
  await _run('adb', [
    ...serial,
    'install',
    '-r',
    'build/app/outputs/flutter-apk/app-$abi-release.apk',
  ]);
  String? done;
  for (var start = 0; start < 2 && done == null; start++) {
    adb(['shell', 'am', 'force-stop', _package]);
    adb(['logcat', '-c']);
    adb(['shell', 'am', 'start', '-n', '$_package/.MainActivity']);
    stdout.writeln('waiting for the cut-out...');
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final lines = const LineSplitter()
          .convert(adb(['logcat', '-d', '-v', 'raw', 'flutter:I', '*:S']))
          .where((l) => l.startsWith('EXAMPLE| '));
      if (lines.isNotEmpty) {
        done = lines.last.substring('EXAMPLE| '.length);
        break;
      }
      if (adb(['shell', 'pidof', _package]).isEmpty) {
        stdout.writeln('the app died (ML Kit?), restarting');
        break;
      }
    }
  }
  if (done == null || !done.startsWith('done')) {
    stderr.writeln('no cut-out: $done');
    exit(1);
  }
  // Let the cut-out paint.
  await Future<void>.delayed(const Duration(seconds: 2));
  final screenshot = await runExecutableArguments('adb', [
    ...serial,
    'exec-out',
    'screencap',
    '-p',
  ], stdoutEncoding: null);
  // Half size: enough for a README, a quarter of the bytes.
  final png = img.decodePng(
    Uint8List.fromList(screenshot.stdout as List<int>),
  )!;
  File(out)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(
      img.encodePng(img.copyResize(png, width: png.width ~/ 2)),
    );
  stdout.writeln('$done, screenshot: $out');
}

/// Runs [executable] with the terminal of this script, the command shown; a
/// non zero exit code throws.
Future<void> _run(String executable, List<String> args) => Shell(
  options: ShellOptions(
    mode: ProcessStartMode.inheritStdio,
    verbose: false,
    commandVerbose: true,
  ),
).runExecutableArguments(executable, args);

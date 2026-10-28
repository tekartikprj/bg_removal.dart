// Runs the phase 0 bench and saves its report in .local/bench/.
//
//   dart run tool/bench.dart android [options]   # the phone on adb
//   dart run tool/bench.dart linux [options]     # headless (xvfb-run)
//
// Options:
//   --methods a,b       methods (default: all but IS-Net; mlkit on android)
//   --provider P        ONNX provider: CPU (default), XNNPACK, NNAPI
//   --threads N         ONNX threads (default: the runtime's)
//   --models DIR        linux: a folder holding the .onnx files (no download)
//   --device SERIAL     android: the adb device (default: ANDROID_SERIAL)
//   --timing WxH        a timing pass on one WxH photo (e.g. 1600x1200)
//   --options JSON      the pipeline options (BgRemovalOptions json)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';

import 'src/adb_app.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || !['android', 'linux'].contains(args.first)) {
    stderr.writeln('usage: dart run tool/bench.dart android|linux [options]');
    exit(64);
  }
  final target = args.first;
  String? option(String name) {
    final i = args.indexOf('--$name');
    return i < 0 || i + 1 >= args.length ? null : args[i + 1];
  }

  final methods =
      option('methods') ??
      [
        if (target == 'android') ...['mlkit', 'mlkit+modnet'],
        'u2netp',
        'modnet',
        'modnet+u2netp',
      ].join(',');
  final defines = [
    '--dart-define=BENCH_AUTORUN=true',
    '--dart-define=BENCH_EXIT=true',
    '--dart-define=BENCH_METHODS=$methods',
    '--dart-define=BENCH_PROVIDER=${option('provider') ?? 'CPU'}',
    '--dart-define=BENCH_THREADS=${option('threads') ?? '0'}',
    '--dart-define=BENCH_TIMING=${option('timing') ?? ''}',
    '--dart-define=BENCH_OPTIONS=${option('options') ?? ''}',
  ];
  final stamp = fileStamp();
  final outDir = Directory(join('.local', 'bench'))
    ..createSync(recursive: true);
  final lines = target == 'android'
      ? await _android(
          defines,
          outDir,
          stamp,
          option('device') ?? Platform.environment['ANDROID_SERIAL'],
        )
      : await _linux(defines, option('models'));
  final report = File(join(outDir.path, '${stamp}_$target.md'));
  report.writeAsStringSync('${lines.join('\n')}\n');
  stdout
    ..writeln(lines.join('\n'))
    ..writeln('report: ${report.path}');
}

Future<List<String>> _linux(List<String> defines, String? modelsDir) async {
  await run('flutter', [
    'build',
    'linux',
    '--release',
    '-t',
    'lib/main_bench.dart',
    ...defines,
  ]);
  const binary = 'build/linux/x64/release/bundle/bg_removal_bench';
  final xvfb = Process.runSync('which', ['xvfb-run']).exitCode == 0;
  final process = await Process.start(
    xvfb ? 'xvfb-run' : binary,
    [
      if (xvfb) ...['-a', '-s', '-screen 0 1600x1200x24', binary],
    ],
    environment: {
      'BG_REMOVAL_MODELS': ?modelsDir,
      // Headless: X11 only.
      if (xvfb) 'WAYLAND_DISPLAY': '',
    },
  );
  final lines = <String>[];
  unawaited(process.stderr.drain<void>());
  await for (final line
      in process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    final i = line.indexOf('BENCH| ');
    if (i >= 0) {
      lines.add(line.substring(i + 7));
    }
  }
  await process.exitCode;
  return lines;
}

Future<List<String>> _android(
  List<String> defines,
  Directory outDir,
  String stamp,
  String? device,
) async {
  final app = AdbApp(device);
  await app.buildAndInstall('lib/main_bench.dart', defines);
  final described = app.describe();
  app.start();
  stdout.writeln('running on $described...');
  var lines = <String>[];
  final deadline = DateTime.now().add(const Duration(minutes: 20));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 5));
    lines = app.printed('BENCH| ');
    if (lines.any((l) => l.startsWith('out: ') || l.startsWith('error: '))) {
      break;
    }
    if (!app.isRunning) {
      lines
        ..add('error: the app died (a native crash):')
        ..add(app.lastCrash());
      break;
    }
  }
  await app.screenshot(join(outDir.path, '${stamp}_android.png'));
  return ['Device: $described', '', ...lines];
}

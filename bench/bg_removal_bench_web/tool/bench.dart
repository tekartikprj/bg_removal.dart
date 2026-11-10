// Runs the bench in headless Chrome and saves its report in .local/bench/.
//
//   dart run tool/bench.dart [options]
//
// Options:
//   --methods a,b       methods (default: u2netp,modnet,modnet+u2netp)
//   --provider P        wasm (default) or webgpu
//   --threads N         wasm threads (default: onnxruntime-web's)
//   --timing WxH        a timing pass on one WxH photo (e.g. 1600x1200)
//   --options JSON      the pipeline options (BgRemovalOptions json)
//   --models DIR        serve the .onnx files from DIR (no download)
//   --wasm              build with dart2wasm (default: dart2js)
//   --no-isolation      no COOP/COEP headers: single-threaded wasm
//   --chrome PATH       the browser (default: google-chrome)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:process_run/shell.dart'
    show Shell, ShellLinesController, ShellOptions;

Future<void> main(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf('--$name');
    return i < 0 || i + 1 >= args.length ? null : args[i + 1];
  }

  final wasm = args.contains('--wasm');
  final isolation = !args.contains('--no-isolation');
  final provider = option('provider') ?? 'wasm';
  final modelsDir = option('models');
  final chrome = option('chrome') ?? 'google-chrome';
  final stamp = DateTime.now()
      .toIso8601String()
      .substring(0, 19)
      .replaceAll(RegExp('[-:]'), '')
      .replaceAll('T', '_');

  await _run('flutter', [
    'build',
    'web',
    '--release',
    if (wasm) '--wasm',
    '-t',
    'lib/main_bench.dart',
    '--dart-define=BENCH_AUTORUN=true',
    '--dart-define=BENCH_REPORT_URL=/report',
    '--dart-define=BENCH_METHODS=${option('methods') ?? 'u2netp,modnet,modnet+u2netp'}',
    '--dart-define=BENCH_PROVIDER=$provider',
    '--dart-define=BENCH_THREADS=${option('threads') ?? '0'}',
    '--dart-define=BENCH_TIMING=${option('timing') ?? ''}',
    '--dart-define=BENCH_OPTIONS=${option('options') ?? ''}',
    if (modelsDir != null) '--dart-define=BENCH_MODELS_URL=/models/',
  ]);

  final report = Completer<String>();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final response = request.response;
    if (isolation) {
      // Cross-origin isolation: wasm threads (SharedArrayBuffer).
      response.headers
        ..set('Cross-Origin-Opener-Policy', 'same-origin')
        ..set('Cross-Origin-Embedder-Policy', 'credentialless');
    }
    final path = request.uri.path;
    if (request.method == 'POST' && path == '/report') {
      final body = await utf8.decodeStream(request);
      if (!report.isCompleted) report.complete(body);
      await response.close();
      return;
    }
    final file = path.startsWith('/models/') && modelsDir != null
        ? File(join(modelsDir, path.substring('/models/'.length)))
        : File(
            join(
              'build',
              'web',
              path == '/' ? 'index.html' : path.substring(1),
            ),
          );
    if (!file.existsSync()) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    response.headers.contentType = _contentType(file.path);
    await response.addStream(file.openRead());
    await response.close();
  });
  final url = 'http://127.0.0.1:${server.port}/';
  final version =
      (Shell(
                verbose: false,
                throwOnError: false,
              ).runExecutableArgumentsSync(chrome, ['--version']).stdout
              as String)
          .trim();
  final userDataDir = Directory.systemTemp.createTempSync('bg_bench_chrome');
  final outDir = Directory(join('.local', 'bench'))
    ..createSync(recursive: true);
  final log = File(join(outDir.path, '${stamp}_web_chrome.log')).openWrite();
  stdout.writeln('running in $version at $url...');
  final chromeOut = ShellLinesController(encoding: utf8);
  final chromeErr = ShellLinesController(encoding: utf8);
  final chromeStarted = Completer<Process>();
  // Not awaited: Chrome runs while the bench does. Its exit code comes with
  // its process (`onProcess`), the run ends with its output pipes, which its
  // helpers can hold a while.
  final chromeRun =
      Shell(
        stdout: chromeOut.sink,
        stderr: chromeErr.sink,
        verbose: false,
        throwOnError: false,
      ).runExecutableArguments(chrome, [
        '--headless=new',
        // CanvasKit needs WebGL: software rendering.
        '--use-angle=swiftshader',
        '--enable-unsafe-swiftshader',
        if (provider == 'webgpu') '--enable-unsafe-webgpu',
        '--no-first-run',
        '--no-default-browser-check',
        '--enable-logging=stderr',
        '--v=0',
        '--user-data-dir=${userDataDir.path}',
        url,
      ], onProcess: chromeStarted.complete);
  unawaited(
    chromeRun.then<void>(
      (_) {},
      onError: (Object e, StackTrace st) {
        // It could not start.
        if (!chromeStarted.isCompleted) chromeStarted.completeError(e, st);
      },
    ),
  );
  final process = await chromeStarted.future;
  chromeOut.stream.listen((_) {});
  final stderrDone = chromeErr.stream.listen((line) {
    log.writeln(line);
    // The page's progress and errors.
    if (line.contains('CONSOLE') && !line.contains('BENCH|')) {
      stdout.writeln('  ${line.length > 200 ? line.substring(0, 200) : line}');
    }
  }).asFuture<void>();
  String markdown;
  try {
    markdown = await report.future.timeout(const Duration(minutes: 30));
  } on TimeoutException {
    markdown = 'error: no report after 30 minutes (see the chrome log)';
  }
  process.kill();
  await process.exitCode;
  chromeOut.close();
  chromeErr.close();
  await stderrDone.catchError((_) {});
  await log.close();
  await server.close(force: true);
  userDataDir.deleteSync(recursive: true);

  final build =
      'Browser: $version, headless, ${wasm ? 'dart2wasm' : 'dart2js'}, '
      '${isolation ? 'cross-origin isolated' : 'not isolated'}';
  final lines = [build, '', markdown];
  final file = File(join(outDir.path, '${stamp}_web.md'))
    ..writeAsStringSync('${lines.join('\n')}\n');
  stdout
    ..writeln(lines.join('\n'))
    ..writeln('report: ${file.path}');
}

ContentType _contentType(String path) => switch (extension(path)) {
  '.html' => ContentType.html,
  '.js' || '.mjs' => ContentType('application', 'javascript', charset: 'utf-8'),
  '.json' => ContentType.json,
  '.wasm' => ContentType('application', 'wasm'),
  '.png' => ContentType('image', 'png'),
  '.jpg' => ContentType('image', 'jpeg'),
  '.css' => ContentType('text', 'css', charset: 'utf-8'),
  '.ttf' || '.otf' => ContentType('font', 'ttf'),
  _ => ContentType.binary,
};

/// Runs [executable] with the terminal of this script, the command shown; a
/// non zero exit code throws.
Future<void> _run(String executable, List<String> args) => Shell(
  options: ShellOptions(
    mode: ProcessStartMode.inheritStdio,
    verbose: false,
    commandVerbose: true,
  ),
).runExecutableArguments(executable, args);

// Takes the README screenshot of the web example: the sample photo with and
// without its background, in headless Chrome.
//
//   dart run tool/screenshot.dart [--chrome PATH] [--out FILE]
//
// Builds the app opening the sample at start, serves it cross-origin
// isolated (wasm threads), waits for the page to POST /done, then captures
// the page (DevTools protocol) to ../../doc/screenshots/example_web.png.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';

Future<void> main(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf('--$name');
    return i < 0 || i + 1 >= args.length ? null : args[i + 1];
  }

  final chrome = option('chrome') ?? 'google-chrome';
  final out =
      option('out') ??
      join('..', '..', 'doc', 'screenshots', 'example_web.png');
  await _run('flutter', [
    'build',
    'web',
    '--release',
    '--dart-define=EXAMPLE_SAMPLE=true',
    '--dart-define=EXAMPLE_DONE_URL=/done',
  ]);

  final done = Completer<String>();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final response = request.response;
    response.headers
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Cross-Origin-Embedder-Policy', 'credentialless');
    final path = request.uri.path;
    if (request.method == 'POST' && path == '/done') {
      final body = await utf8.decodeStream(request);
      if (!done.isCompleted) done.complete(body);
      await response.close();
      return;
    }
    final file = File(
      join('build', 'web', path == '/' ? 'index.html' : path.substring(1)),
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

  final userDataDir = Directory.systemTemp.createTempSync('bg_example_chrome');
  final process = await Process.start(chrome, [
    '--headless=new',
    // CanvasKit needs WebGL: software rendering.
    '--use-angle=swiftshader',
    '--enable-unsafe-swiftshader',
    '--no-first-run',
    '--no-default-browser-check',
    '--window-size=1100,760',
    '--force-device-scale-factor=1',
    '--hide-scrollbars',
    '--remote-debugging-port=0',
    '--user-data-dir=${userDataDir.path}',
    'http://127.0.0.1:${server.port}/',
  ]);
  unawaited(process.stdout.drain<void>());
  // "DevTools listening on ws://127.0.0.1:<port>/devtools/browser/<id>"
  final devTools = Completer<int>();
  process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      final match = RegExp(
        r'DevTools listening on ws://127\.0\.0\.1:(\d+)/',
      ).firstMatch(line);
      if (match != null && !devTools.isCompleted) {
        devTools.complete(int.parse(match.group(1)!));
      }
    },
  );
  try {
    final port = await devTools.future.timeout(const Duration(seconds: 30));
    stdout.writeln('waiting for the cut-out...');
    final result = await done.future.timeout(const Duration(minutes: 5));
    // Let the cut-out paint.
    await Future<void>.delayed(const Duration(seconds: 2));
    final png = await _capture(port);
    File(out)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png);
    stdout.writeln('$result, screenshot: $out');
  } finally {
    process.kill();
    await process.exitCode;
    await server.close(force: true);
    // Chrome's helpers can still write to the profile for a moment.
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      userDataDir.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      stderr.writeln('could not delete ${userDataDir.path}: $e');
    }
  }
}

/// The page's screenshot through the DevTools protocol.
Future<List<int>> _capture(int port) async {
  final client = HttpClient();
  final request = await client.getUrl(
    Uri.parse('http://127.0.0.1:$port/json/list'),
  );
  final targets =
      jsonDecode(await utf8.decodeStream(await request.close())) as List;
  client.close();
  final page = targets.cast<Map<String, Object?>>().firstWhere(
    (t) => t['type'] == 'page',
  );
  final socket = await WebSocket.connect(
    page['webSocketDebuggerUrl']! as String,
  );
  socket.add(
    jsonEncode({
      'id': 1,
      'method': 'Page.captureScreenshot',
      'params': {'format': 'png'},
    }),
  );
  await for (final message in socket) {
    final json = jsonDecode(message as String) as Map<String, Object?>;
    if (json['id'] == 1) {
      await socket.close();
      final result = json['result']! as Map<String, Object?>;
      return base64Decode(result['data']! as String);
    }
  }
  throw StateError('no screenshot');
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

Future<void> _run(String executable, List<String> args) async {
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

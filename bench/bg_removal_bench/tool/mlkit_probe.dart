// Tries ML Kit Subject Segmentation in several ways on the phone, restarting
// the app after each native crash, and saves the results in .local/bench/.
//
//   dart run tool/mlkit_probe.dart [--device SERIAL]
import 'dart:io';

import 'package:path/path.dart';

import 'src/adb_app.dart';

Future<void> main(List<String> args) async {
  final i = args.indexOf('--device');
  final app = AdbApp(i < 0 || i + 1 >= args.length ? null : args[i + 1]);
  final stamp = fileStamp();
  await app.buildAndInstall('lib/main_mlkit_probe.dart', [
    '--dart-define=PROBE_BUILD=$stamp',
  ]);
  final device = app.describe();
  stdout.writeln('probing on $device...');
  final crashes = <String>[];
  var lines = <String>[];
  // One start per case at most, plus the first.
  for (var start = 0; start < 10; start++) {
    app.start();
    final deadline = DateTime.now().add(const Duration(minutes: 8));
    await Future<void>.delayed(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      lines = app.printed('PROBE| ');
      if (lines.contains('done') || !app.isRunning) break;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    // Read again: the last lines may come after the last poll.
    lines = app.printed('PROBE| ');
    for (final line in lines) {
      stdout.writeln('  $line');
    }
    if (lines.contains('done')) break;
    final crash = app.lastCrash();
    final running = lines.lastWhere(
      (l) => l.endsWith(': running'),
      orElse: () => '?',
    );
    crashes.add('### $running\n\n```\n$crash\n```');
    stdout.writeln('the app died, restarting');
  }
  final summary = lines.skipWhile((l) => !l.startsWith('results')).toList();
  final report = [
    '# ML Kit Subject Segmentation probe',
    '',
    'Device: $device, build $stamp',
    '',
    ...summary,
    if (crashes.isNotEmpty) ...['', '## Crashes', '', ...crashes],
  ].join('\n');
  final out = File(join('.local', 'bench', '${stamp}_mlkit_probe.md'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('$report\n');
  stdout
    ..writeln(report)
    ..writeln('report: ${out.path}');
}

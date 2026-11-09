import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:tekartik_bg_removal_mlkit/src/mlkit_guard.dart';

void main() {
  late Directory dir;
  late File file;
  late BgMlKitGuard guard;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bg_removal_mlkit_guard');
    file = File(join(dir.path, 'guard.txt'));
    guard = BgMlKitGuard(() async => file);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('the guard is there during the call only', () async {
    expect(await guard.run('segment', () async => file.existsSync()), isTrue);
    expect(file.existsSync(), isFalse);
  });

  test('a Dart error is not a crash', () async {
    await expectLater(
      guard.run(
        'segment',
        () async => throw PlatformException(code: 'InputImageConverterError'),
      ),
      throwsA(isA<PlatformException>()),
    );
    // Left behind, the next launch would take it for a native crash.
    expect(file.existsSync(), isFalse);
  });

  test('two calls in flight', () async {
    final first = Completer<void>();
    final firstRun = guard.run('first', () => first.future);
    // The second call still has its guard after the first one ended.
    final secondRun = guard.run('second', () async {
      await firstRun;
      return file.existsSync();
    });
    first.complete();
    expect(await secondRun, isTrue);
    expect(file.existsSync(), isFalse);
  });
}

import 'dart:isolate';

/// Runs [computation] in a new isolate (`Isolate.run`); inline on the web.
///
/// [computation] must only capture data that can be sent: images, masks,
/// options. A closure created in a method captures `this`: build it in a
/// top-level function.
Future<R> bgRunInIsolate<R>(R Function() computation) =>
    Isolate.run(computation);

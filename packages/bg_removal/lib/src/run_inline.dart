/// Runs [computation] in a new isolate (`Isolate.run`); inline on the web.
Future<R> bgRunInIsolate<R>(R Function() computation) async => computation();

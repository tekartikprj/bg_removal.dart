// The web (dart2js and dart2wasm) has no isolates to run in: inline there.
// Not `dart.library.isolate`: dart2wasm has the library, not its isolates.
export 'run_isolate.dart' if (dart.library.js_interop) 'run_inline.dart';

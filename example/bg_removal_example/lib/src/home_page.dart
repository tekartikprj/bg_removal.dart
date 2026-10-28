import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tekaly_file_download/download_file.dart';
import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';
import 'package:tekartik_bg_removal_mlkit/bg_removal_mlkit.dart';
import 'package:tekartik_bg_removal_onnx/bg_removal_onnx.dart';

/// Opens the sample photo at start (`--dart-define=EXAMPLE_SAMPLE=true`),
/// for screenshots.
const exampleSample = bool.fromEnvironment('EXAMPLE_SAMPLE');

/// The sample photo (CC BY 2.0, John Benson, Wikimedia Commons).
const sampleAsset = 'assets/sample.jpg';

/// The photo, its cut-out, and the buttons.
class HomePage extends StatefulWidget {
  /// The home page.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ML Kit on Android (Google Play services), MODNet + u2netp on ONNX
  // Runtime when it cannot run (or crashed the app last time).
  final _remover = BgRemoverFallback([BgMlKitRemover(), BgOnnxRemover()]);
  late final Future<void> _ready;
  var _status = 'Preparing the engine...';
  var _busy = false;
  Uint8List? _photo;
  BgRemovalResult? _result;
  Duration? _time;

  @override
  void initState() {
    super.initState();
    // Awaited before each photo; its error shows in the status line.
    _ready = _prepare()..ignore();
    if (exampleSample) {
      // Screenshots: no system bars (notification icons).
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive));
      unawaited(_open(_sampleBytes));
    }
  }

  Future<void> _prepare() async {
    try {
      await _remover.prepare(
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      _setStatus('Ready (${_remover.name})');
    } catch (e) {
      _setStatus('No engine: $e');
      rethrow;
    }
  }

  void _setStatus(String status) {
    if (mounted) setState(() => _status = status);
  }

  @override
  void dispose() {
    unawaited(_remover.close());
    super.dispose();
  }

  Future<Uint8List> _sampleBytes() async =>
      (await rootBundle.load(sampleAsset)).buffer.asUint8List();

  Future<void> _pick(ImageSource source) => _open(() async {
    // 1600 px is plenty for a cut-out, and keeps the engine under a second.
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    return file?.readAsBytes();
  });

  Future<void> _open(Future<Uint8List?> Function() load) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await load();
      if (bytes == null) return;
      setState(() {
        _photo = bytes;
        _result = null;
      });
      await _ready;
      _setStatus('Removing the background...');
      final sw = Stopwatch()..start();
      final result = await bgRemoveBackgroundFromBytes(_remover, bytes);
      setState(() {
        _result = result;
        _time = sw.elapsed;
        _status = 'Done';
      });
      // For tools (screenshots): the run is over.
      // ignore: avoid_print
      print('EXAMPLE| done ${result.engine} ${sw.elapsedMilliseconds} ms');
    } catch (e) {
      _setStatus('Error: $e');
      // ignore: avoid_print
      print('EXAMPLE| error $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download({required bool webp}) async {
    final cutout = _result!.cutout;
    _setStatus('Encoding...');
    final data = webp ? await _encodeWebp(cutout) : await _encodePng(cutout);
    _setStatus('Done');
    await downloadFile(
      DownloadFileInfo(filename: 'cutout.${webp ? 'webp' : 'png'}', data: data),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    final result = _result;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Background removal')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                result == null
                    ? _status
                    : '${result.engine}, ${_time!.inMilliseconds} ms',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: photo == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Take or pick a photo of a person: they stay, '
                          'with what they carry, the rest goes.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _Panel(
                            title: 'Original',
                            child: Image.memory(photo, fit: BoxFit.contain),
                          ),
                        ),
                        Expanded(
                          child: _Panel(
                            title: 'Without background',
                            child: result == null
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : BgRgbaImageView(result.cutout),
                          ),
                        ),
                      ],
                    ),
            ),
            if (result != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _download(webp: true),
                      icon: const Icon(Icons.download),
                      label: const Text('WebP'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _download(webp: false),
                      icon: const Icon(Icons.download),
                      label: const Text('PNG'),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _open(_sampleBytes),
                    child: const Text('Sample'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(6),
    child: Column(
      children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Expanded(child: Center(child: child)),
      ],
    ),
  );
}

// Top-level: the isolate closures only capture the image.
Future<Uint8List> _encodePng(BgRgbaImage image) =>
    bgRunInIsolate(() => bgEncodePng(image));

Future<Uint8List> _encodeWebp(BgRgbaImage image) =>
    bgRunInIsolate(() => bgEncodeWebp(image));

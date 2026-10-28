import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tekaly_file_download/download_file.dart';
import 'package:tekartik_bg_removal_flutter/bg_removal_flutter.dart';

/// The sample photo (CC BY 2.0, John Benson, Wikimedia Commons).
const exampleSampleAsset =
    'packages/bg_removal_example_common/assets/sample.jpg';

/// Takes or picks a photo, removes its background with [remover] (the
/// person and what they carry stay), shows both, and saves the cut-out.
class BgRemovalExamplePage extends StatefulWidget {
  /// The engine: the page prepares it at start and closes it at the end.
  final BgRemover remover;

  /// Shows a camera button (Android); the web picks files.
  final bool camera;

  /// Opens the sample photo at start (screenshots).
  final bool openSample;

  /// Called after each cut-out (tools).
  final void Function(BgRemovalResult result, Duration time)? onDone;

  /// The page.
  const BgRemovalExamplePage({
    super.key,
    required this.remover,
    this.camera = true,
    this.openSample = false,
    this.onDone,
  });

  @override
  State<BgRemovalExamplePage> createState() => _BgRemovalExamplePageState();
}

class _BgRemovalExamplePageState extends State<BgRemovalExamplePage> {
  late final Future<void> _ready;
  var _status = 'Preparing the engine...';
  var _busy = false;
  Uint8List? _photo;
  BgRemovalResult? _result;
  Duration? _time;

  BgRemover get _remover => widget.remover;

  @override
  void initState() {
    super.initState();
    // Awaited before each photo; its error shows in the status line.
    _ready = _prepare()..ignore();
    if (widget.openSample) {
      unawaited(_open(_sampleBytes));
    }
  }

  Future<void> _prepare() async {
    try {
      await _remover.prepare(onStatus: _setStatus);
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
      (await rootBundle.load(exampleSampleAsset)).buffer.asUint8List();

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
      // Paint the status first: on the web the work runs on this thread.
      await WidgetsBinding.instance.endOfFrame;
      final sw = Stopwatch()..start();
      final result = await bgRemoveBackgroundFromBytes(_remover, bytes);
      final time = sw.elapsed;
      setState(() {
        _result = result;
        _time = time;
        _status = 'Done';
      });
      widget.onDone?.call(result, time);
    } catch (e) {
      _setStatus('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download({required bool webp}) async {
    final cutout = _result!.cutout;
    _setStatus('Encoding...');
    await WidgetsBinding.instance.endOfFrame;
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
                  if (widget.camera)
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Camera'),
                    ),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text(kIsWeb ? 'Open' : 'Gallery'),
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

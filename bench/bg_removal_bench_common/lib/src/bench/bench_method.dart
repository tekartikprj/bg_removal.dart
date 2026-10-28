import 'package:tekartik_bg_removal/bg_removal.dart';

/// A way to get the final mask from one or two engines: the person of one,
/// the foreground of the other, through the pipeline
/// ([bgFinalMask]).
class BenchMethod {
  /// Short id.
  final String id;

  /// The engine giving the person mask, if any.
  final String? person;

  /// The engine giving the foreground mask, if any.
  final String? foreground;

  /// A method.
  const BenchMethod(this.id, {this.person, this.foreground});

  /// The engines it needs.
  List<String> get models => [?person, ?foreground];

  /// The final mask from the engines' masks.
  BgMask mask(Map<String, BgMask> masks, BgRemovalOptions options) =>
      bgFinalMask(
        BgEngineMasks(
          person: person == null ? null : masks[person],
          foreground: foreground == null ? null : masks[foreground],
        ),
        options,
      );

  /// The engine of the method, for the public API: one engine, or the
  /// person of one with the foreground of the other.
  BgRemover remover(Map<String, BgRemover> engines) {
    final person = this.person;
    final foreground = this.foreground;
    if (person != null && foreground != null) {
      return BgRemoverMerge(
        person: engines[person]!,
        foreground: engines[foreground]!,
      );
    }
    return engines[person ?? foreground]!;
  }
}

/// The methods compared by the bench.
const benchMethods = [
  BenchMethod('mlkit', foreground: 'mlkit'),
  BenchMethod('mlkit+modnet', person: 'modnet', foreground: 'mlkit'),
  BenchMethod('u2netp', foreground: 'u2netp'),
  BenchMethod('modnet', person: 'modnet'),
  BenchMethod('modnet+u2netp', person: 'modnet', foreground: 'u2netp'),
  BenchMethod('modnet+isnet', person: 'modnet', foreground: 'isnet'),
];

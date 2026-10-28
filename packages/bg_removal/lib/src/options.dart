/// What to keep.
enum BgKeep {
  /// The person and what they carry or hold: bags, but also a cup, a phone,
  /// an umbrella (the default).
  ///
  /// With a person mask and a foreground mask, the regions of the
  /// foreground that touch the person are kept with it; with one of them
  /// only, that one is the result.
  personAndCarried,

  /// The person only (needs an engine with a person mask, such as MODNet).
  person,

  /// Every foreground subject (the salient or "all subjects" mask).
  foreground,
}

/// How a photo becomes a cut-out. The defaults are the measured ones (the
/// bench of `bg_removal_bench`): change them to fine tune.
class BgRemovalOptions {
  /// What to keep.
  final BgKeep keep;

  /// How far, as a share of the photo's long side, a foreground region can
  /// be from the person and still be kept with it (a bag held at arm's
  /// length).
  final double anchorGrow;

  /// The alpha (0-255) from which a pixel is "in" for the region steps:
  /// anchoring, small regions, holes, crop box.
  final int threshold;

  /// Alpha at most this becomes 0 (faint halos go), 0 = off.
  final int transparentBelow;

  /// Alpha at least this becomes 255 (a nearly solid subject becomes
  /// solid), 255 = off.
  final int opaqueAbove;

  /// Regions smaller than this share of the photo are removed (specks), 0
  /// = off. 0.005 is a good start; mind small people far away.
  final double minRegion;

  /// Holes inside the subject smaller than this share of the photo are
  /// filled, 0 = off.
  final double fillHoles;

  /// The edge is softened by this many pixels (box blur), 0 = off.
  final int feather;

  /// The engine works on the photo scaled down to this long side, then the
  /// mask is scaled up: faster on big photos. Null = the photo as is.
  final int? maxSegmentSize;

  /// The cut-out is cropped to the subject, plus [cropMargin].
  final bool crop;

  /// Pixels around the subject when cropping.
  final int cropMargin;

  /// The cut-out is scaled down to this long side, null = as is.
  final int? maxOutputSize;

  /// Options.
  const BgRemovalOptions({
    this.keep = BgKeep.personAndCarried,
    this.anchorGrow = 0.01,
    this.threshold = 128,
    this.transparentBelow = 0,
    this.opaqueAbove = 255,
    this.minRegion = 0,
    this.fillHoles = 0,
    this.feather = 0,
    this.maxSegmentSize,
    this.crop = false,
    this.cropMargin = 16,
    this.maxOutputSize,
  });

  /// From [toJson] (missing keys keep their default).
  factory BgRemovalOptions.fromJson(Map<String, Object?> json) {
    const d = BgRemovalOptions();
    T get<T>(String key, T defaultValue) {
      final value = json[key];
      if (value == null) return defaultValue;
      if (T == double) return (value as num).toDouble() as T;
      if (T == int) return (value as num).toInt() as T;
      return value as T;
    }

    final keep = json['keep'] as String?;
    return BgRemovalOptions(
      keep: keep == null ? d.keep : BgKeep.values.byName(keep),
      anchorGrow: get('anchorGrow', d.anchorGrow),
      threshold: get('threshold', d.threshold),
      transparentBelow: get('transparentBelow', d.transparentBelow),
      opaqueAbove: get('opaqueAbove', d.opaqueAbove),
      minRegion: get('minRegion', d.minRegion),
      fillHoles: get('fillHoles', d.fillHoles),
      feather: get('feather', d.feather),
      maxSegmentSize: (json['maxSegmentSize'] as num?)?.toInt(),
      crop: get('crop', d.crop),
      cropMargin: get('cropMargin', d.cropMargin),
      maxOutputSize: (json['maxOutputSize'] as num?)?.toInt(),
    );
  }

  /// As json, every value.
  Map<String, Object?> toJson() => {
    'keep': keep.name,
    'anchorGrow': anchorGrow,
    'threshold': threshold,
    'transparentBelow': transparentBelow,
    'opaqueAbove': opaqueAbove,
    'minRegion': minRegion,
    'fillHoles': fillHoles,
    'feather': feather,
    'maxSegmentSize': maxSegmentSize,
    'crop': crop,
    'cropMargin': cropMargin,
    'maxOutputSize': maxOutputSize,
  };

  /// A copy with the given values changed.
  BgRemovalOptions copyWith({
    BgKeep? keep,
    double? anchorGrow,
    int? threshold,
    int? transparentBelow,
    int? opaqueAbove,
    double? minRegion,
    double? fillHoles,
    int? feather,
    int? maxSegmentSize,
    bool? crop,
    int? cropMargin,
    int? maxOutputSize,
  }) => BgRemovalOptions(
    keep: keep ?? this.keep,
    anchorGrow: anchorGrow ?? this.anchorGrow,
    threshold: threshold ?? this.threshold,
    transparentBelow: transparentBelow ?? this.transparentBelow,
    opaqueAbove: opaqueAbove ?? this.opaqueAbove,
    minRegion: minRegion ?? this.minRegion,
    fillHoles: fillHoles ?? this.fillHoles,
    feather: feather ?? this.feather,
    maxSegmentSize: maxSegmentSize ?? this.maxSegmentSize,
    crop: crop ?? this.crop,
    cropMargin: cropMargin ?? this.cropMargin,
    maxOutputSize: maxOutputSize ?? this.maxOutputSize,
  );

  @override
  String toString() => 'BgRemovalOptions(${toJson()})';
}

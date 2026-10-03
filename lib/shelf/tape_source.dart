import 'package:flutter/foundation.dart';

import 'labels/tape_label_data.dart';

/// Which atlas a label is for: the shelf's spine strip or the inspect
/// view's full sleeve (which also prints banner and background).
enum LabelUse { shelf, hero }

/// Label data for one tape plus a stable key describing it.
///
/// [TapeLabelData.cacheKey] includes each image's identity hash, which
/// changes every time an image is re-resolved; [key] instead names the
/// artwork by URL, so composed art can be cached across re-resolutions.
class LabelSnapshot {
  LabelSnapshot(this.data, this.key);

  final TapeLabelData data;
  final String key;

  /// Releases every image this snapshot owns (all of [data]'s artwork).
  void dispose() {
    data.poster?.dispose();
    data.logo?.dispose();
    data.banner?.dispose();
    data.background?.dispose();
  }
}

/// Where the shelf gets what it prints on each tape. Notifies when
/// anything that would change a label (title, watch state, artwork)
/// arrives.
abstract class TapeSource implements Listenable {
  /// Identity of the label [labelData] would build right now for [use].
  /// Cheap and synchronous; changes exactly when the printed label would
  /// (including when any of its artwork finishes loading).
  String labelKey(String titleId, {LabelUse use = LabelUse.shelf});

  /// Builds the label for [titleId], loading the title and its artwork as
  /// needed but giving up on them after [patience] (the label then prints
  /// without them and [labelKey] changes when they arrive). Null when
  /// nothing is known about the title yet. The caller owns the snapshot and
  /// must [LabelSnapshot.dispose] it.
  Future<LabelSnapshot?> labelData(String titleId,
      {LabelUse use = LabelUse.shelf, Duration patience});

  /// Spoken description of the tape ("Dark, show, watching, 5 of 12
  /// episodes").
  String semanticsLabel(String titleId);

  /// Starts loading what [titleIds] will need, without waiting.
  void prefetch(Iterable<String> titleIds);
}

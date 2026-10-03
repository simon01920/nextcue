import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'shelf_layout.dart';
import 'shelf_renderer.dart';
import 'shelf_view.dart';

/// One tape standing on its own: its shelf plate composited with its spine
/// art on a transparent ground (the sprite that lifts out of the shelf).
/// Sized by its width; the height follows the plate.
class TapeView extends StatefulWidget {
  const TapeView({
    super.key,
    required this.titleId,
    this.pose = TapePose.upright,
  });

  final String titleId;
  final TapePose pose;

  @override
  State<TapeView> createState() => _TapeViewState();
}

class _TapeViewState extends State<TapeView> {
  ShelfRenderer? _r;
  ui.Image? _sprite;
  String? _key; // what _sprite shows
  String? _pending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = ShelfScope.of(context);
    if (!identical(r, _r)) {
      _r?.removeListener(_changed);
      _r = r..addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _r?.removeListener(_changed);
    _sprite?.dispose();
    super.dispose();
  }

  Future<void> _compose(ShelfBay bay, int rowWidthPx, String key) async {
    _pending = key;
    final s = await _r!.tapeSprite(bay, 0, rowWidthPx);
    if (!mounted || _pending != key) {
      s?.$1.dispose();
      return;
    }
    setState(() {
      _sprite?.dispose();
      _sprite = s?.$1;
      _key = key;
      _pending = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _r!;
    final layout = r.layout;
    return LayoutBuilder(builder: (context, box) {
      if (layout == null) return const SizedBox.shrink();
      final plate = layout.plates[layout.packedFor(widget.titleId)]!;
      final aspect = plate.size.width / plate.size.height;
      final w = box.maxWidth.isFinite ? box.maxWidth : 86.0;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final rowWidthPx =
          (w * dpr * layout.bayPx.width / plate.size.width).round();
      final bay = layout.layoutBay(0, [ShelfTape(widget.titleId, widget.pose)], '');
      final key = '${bay.key}@$rowWidthPx|${r.source.labelKey(widget.titleId)}';
      if (key != _key && key != _pending) _compose(bay, rowWidthPx, key);
      return Semantics(
        image: true,
        label: r.source.semanticsLabel(widget.titleId),
        child: SizedBox(
          width: w,
          height: w / aspect,
          child: _sprite == null
              ? null
              : RawImage(
                  image: _sprite,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
        ),
      );
    });
  }
}

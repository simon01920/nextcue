# Tape label composer — spec

The 3D plates (Blender) leave every printed surface of the VHS sleeve and
cassette blank; at runtime Flutter paints one **label atlas** per title and the
fragment shader maps it onto the plate pixels through the UV pass. This file is
the contract for that composer.

## Atlas layouts (source of truth: `assets/plates/manifest.json`)

Both layouts are generated from `blender/nc/atlas.py`. Regions are normalised
`x, y, w, h` in **image space** (origin top-left, y down) plus their size in mm.

| Layout | Canvas (mm) | Regions | Used by |
|---|---|---|---|
| `spine` | 48 × 190.5 | `spine` (28 × 190.5), `front_strip` (20 × 190.5, the left 20 mm of the front cover next to the fold) | every tape on a shelf |
| `hero` | 256 × 256 | `back`, `spine`, `front` (unfolded back \| spine \| front, art may run across folds), `cassette_face` (79 × 43), `cassette_spine` (147 × 19) | the one tape being inspected |

Orientation as printed on the real object:
* **Spine** text reads **top-to-bottom** (rotate +90°), like the user's reference app.
* **Front** is upright; its left edge is the spine fold. `front_strip` in the
  shelf layout must equal the left 20 mm of the hero front.
* **Back** is upright; its right edge is the spine fold.
* Cassette labels are upright landscape stickers (paper, matte).

## Inputs

```dart
enum TapeStateKind { notStarted, watching, completed, newEpisode }

class TapeState {
  final TapeStateKind kind;
  final double progress;        // 0..1 (watched / aired)
  final int watched;            // episodes watched
  final int total;              // aired episodes (0 for movies)
  final String? nextCode;       // e.g. "S02 E05" for watching / newEpisode
}

class TapeLabelData {
  final String titleId;         // deterministic style seed, e.g. "series-81189"
  final String title;           // may be long, may contain Slovak/Czech diacritics
  final String? year;           // "2014"
  final bool isMovie;
  final ui.Image? poster;       // portrait poster (~680×1000), may be null
  final ui.Image? logo;         // transparent clear logo, optional
  final String? synopsis;
  final List<String> genres;
  final String? network;        // "AMC", "Netflix"…
  final String? runtime;        // "47 min" / "2h 12m"
  final TapeState state;
}
```

## Outputs

```dart
class LabelComposer {
  /// Shelf atlas: width px given, height follows the 48:190.5 canvas.
  Future<ui.Image> composeShelf(TapeLabelData d, {int widthPx = 224});
  /// Hero atlas: square, all five regions.
  Future<ui.Image> composeHero(TapeLabelData d, {int sizePx = 1536});
}
```

Rasterise with `PictureRecorder` + `Picture.toImage` (raster thread). The spine
in both outputs must come from the **same painter** so the hand-off from shelf to
inspect view is seamless.

## Visual direction

1980s–90s rental-store VHS, printed on board under a semi-gloss varnish (the 3D
plate adds the real gloss and lighting — the composer paints *flat print*; no fake
highlights or drop shadows on the art itself, except for the stickers' own small
shadows).

**Spine styles** — at least six, chosen deterministically from `titleId`, each
with deterministic sub-variation (stripe colours, band heights, studio mark
position, catalogue number). Palette comes from the poster's dominant colours
when a poster is present, otherwise from a curated hashed palette. Examples:
black spine with large condensed title and a coloured band; poster-art spine
(vertical crop under a dark gradient) with the title in a colour box; white
minimal spine with rules; bold colour-block spine; rental spine with diagonal
stripe header; gradient "synth" band with a chrome-styled title. A shelf of 30
must look *collected, not cloned*.

**Title fit (spine)** — never overflows. Order: largest size that fits the
available length → shrink down to a minimum → tighten tracking → break into two
lines (two parallel vertical lines) at the word boundary nearest the middle →
ellipsis as the last resort. Uppercase with locale-correct case mapping
(`ľ`→`Ľ`, `ť`→`Ť`). Fonts: `Anton` (display) and `Figtree` (all weights) are
bundled and cover every Slovak/Czech glyph — use only these.

**Front cover** — poster cropped to the region (cover fit, top-biased) and
graded so it reads *printed*: gentle contrast curve, slight warmth, subtle print
grain/halftone, faint vignette. Thin studio band at the top
("NEXTCUE HOME VIDEO"), bottom strip with a format block ("VHS · HI-FI STEREO")
and a rating box. If a clear logo exists, place it in the lower third; if there
is no poster, render a handsome typographic cover instead (title, year, genres
on a designed background) — never a blank or grey box.

**Back cover** — synopsis (auto-fitted, then ellipsis), meta line
(year · genres · network · runtime), three "still" frames (crops of the poster
or abstract frames when absent), a deterministic barcode from `titleId`, small
legal text, "BE KIND, PLEASE REWIND".

**Cassette labels** — paper stickers: `cassette_face` with ruled lines, title,
studio mark and a small state stamp; `cassette_spine` with title and episode
counter.

**State language** (on the spine, mirrored on the hero spine and cassette):
* `notStarted` — a "NEW" price-gun sticker near the top (the 3D shelf also shows
  these tapes still shrink-wrapped).
* `watching` — a tape-counter sticker (`▶ 05/12` in LCD-style digits) plus a thin
  progress rule along the spine edge.
* `completed` — a round **"BE KIND, REWIND"** sticker.
* `newEpisode` — a red starburst "NEW EP" sticker (the shelf also pulls the tape
  out a little).

Stickers are slightly rotated, have their own paper texture and a tiny shadow.

**Wear** — deterministic per `titleId` (level 0–1): scuffs where the print
rubbed off along the fold edges and corners (lighter board showing through),
slight fading. Subtle; never covering the title.

## Constraints

* Compose time target: shelf atlas < 30 ms, hero atlas < 120 ms (mid-range).
* No new dependencies. No network access in the composer itself.
* Text never overflows any region (assert in tests).
* Accessibility is handled by the shelf widget, not the composer.

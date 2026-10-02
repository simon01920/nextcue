# Plates — the contract between Blender and the app

The shelf and the tape inspect view are drawn from **plates**: images
rendered offline by `blender/build.py` and composited at runtime with
per-title label artwork by a fragment shader. This file is the contract;
`tools/plates/composite.py` is its executable reference (numpy), and
`shaders/plate.frag` must produce the same pixels.

## Files

`assets/plates/manifest.json` (version 2):

```jsonc
{
  "version": 2,
  "atlas": {               // label-artwork canvases, mm, image space (y down)
    "hero":  { "canvas_mm": [256, 256], "regions": { "back": {x,y,w,h,mm}, "spine", "front",
                                                     "cassette_face", "cassette_spine" } },
    "spine": { "canvas_mm": [48, 190.5], "regions": { "spine", "front_strip" } },
    "tag":   { "canvas_mm": [352, 19],  "regions": { "card" } },
    "sleeve_mm": [107, 190.5, 28]
  },
  "groups": { "shelf": {…layout…}, "hero": {…layout…} },
  "plates": {
    "shelf/tape_a": {
      "name": "tape_a",
      "frame": [1116, 690],          // full render frame of the group, px
      "crop": [472, 0, 86, 690],     // where this image sits in that frame: x, y, w, h
      "size": [86, 690],             // == crop w, h
      "color": "shelf/tape_a_color.webp",
      "uv":    "shelf/tape_a_uv.png",    // only plates that carry labels
      "uv2":   "shelf/tape_a_uv2.png",
      "atlas": "spine",              // which artwork canvas the UVs address
      "tint":  [1.03, 1.0, 0.95],    // colour of the label light
      "slot": 5, …                   // group-specific metadata
    }
  }
}
```

Region rectangles are fractions of their canvas (`x, y, w, h`), with `mm`
for reference. Paint label artwork into exactly these rectangles.

## Per-pixel encoding

| image | R | G | B | A |
|---|---|---|---|---|
| `*_color.webp` | beauty RGB | | | coverage (straight alpha) |
| `*_uv.png`  | U high byte | V high byte | **D** (label light × coverage) | – |
| `*_uv2.png` | U low byte | V low byte | 0 | – |

* `U = (R_hi·256 + R_lo) / 65535`, `V = (G_hi·256 + G_lo) / 65535`: image-space
  coordinates in the atlas (0,0 = top-left).
* `D` is how much light the label surface receives, as an 8-bit value,
  **already multiplied by the label's coverage** of the pixel (0 off labels,
  soft at anti-aliased label edges).
* In the colour plate, label surfaces are rendered as black ink under their
  varnish, so it carries only their gloss, the shell, shadows and so on.
* UVs are dilated 4 px past label edges, so interpolating UVs across an edge
  never mixes in zeros.

## Compositing

Premultiplied:

```
out.rgb = C.rgb·C.a + T(uv) · D · tint
out.a   = C.a
```

`T` is the artwork (sRGB-encoded, as painted). The beauty, `D` and the art
are all display-referred, so the product is done in display space. That is
the same space Blender's tone mapping produced the plate in.

### Sampling (important)

The hi/lo byte pairs must **never be filtered**: bilinear filtering between
`(1, 255)` and `(2, 0)` gives garbage. Set the data samplers to
`FilterQuality.none` and filter by hand:

1. For the fragment's position `p` in plate pixels, take the 4 texel
   centres around `p - 0.5` and fetch `uv`/`uv2` with nearest sampling
   (`texture(s, (floor(q) + 0.5) / size)`).
2. Reconstruct the 4 UVs and 4 D values, then interpolate them
   bilinearly with the fragment's sub-texel weights. Interpolate the **UV**,
   not the colours: the art is then sampled at screen resolution, so labels
   stay sharp even when a plate is magnified.
3. Sample the art once at that UV with bilinear filtering
   (`FilterQuality.low`; `medium` when it has mipmaps).
4. Sample the colour plate bilinearly.

## Shelf group (`groups.shelf`)

All shelf plates share one frame: one **bay** (divider centre to divider
centre) × one **row band** (from the bottom of this row's rail to the
bottom of the next one's), at `px_per_mm` = 3.

```
bay_px [1116, 690]   slots 12   slot_px 86   slot0_left_px 42
inner_px [27, 1089]  (between the dividers' inner faces)
plate_slot 5         (the slot the tape plates were rendered in)
```

A plate is drawn at `crop.xy + ((target_slot − plate.slot) · slot_px, 0)`
inside the bay. Rows stack edge to edge at 690 px; clip each row to its band.

Draw order per bay:

1. `bay_{0,1,2}`, opaque. Pick by bay index, e.g. `bays[i % 3]`.
2. `tape_end_shadow` at the last upright tape's slot, only when the bay
   is not full and the last tape does not lean. Clip to `inner_px`.
3. Upright tapes, left to right: `tape_a..d` (pick per title ID, which also
   varies the height and how far each tape is pushed in), or `tape_sealed`
   for titles not started yet (shrink-wrapped).
4. For each tape pulled forward (watching): `tape_pulled_shadow`, then
   `tape_pulled` at its slot. These come after all the uprights.
5. `tape_lean`: when a bay holds 2 to `lean_max_tapes` tapes, the last one
   leans on its neighbour and occupies 2 slots. Its `slot` is the first
   slot after the last upright. Clip to `inner_px`.
6. `rail` (atlas `tag`): the section card, e.g. "DRAMA · 12".

Pixel density: the art for a tape can be painted at
`spine canvas mm × 3 px/mm × (on-screen scale)`, which is 144 px wide at
1 : 1.

## Hero group (`groups.hero`)

* `rot_00 … rot_35`: the sleeve turning in 10° steps on a transparent
  studio floor, with a shadow-catcher contact shadow. Frame 0 is the spine
  (as on the shelf), 9 the front cover, 18 the open side (showing the
  cassette's spine sticker), 27 the back. All are `size` = 640 × 900 in
  the same camera; `available` lists the frames present (quick builds
  render every fourth).
* `front_hi`: frame 9 at 2× (1280 × 1800) for the settled view.
* `cassette_p000 … p100`: the cassette face-up, with reels wound to 0, 25,
  50, 75 and 100 % watched (the supply reel empties to the left, the
  take-up reel fills on the right). Atlas `hero` (regions
  `cassette_face`, `cassette_spine`).
* `floor_center_px`, `top_center_px`: where the sleeve stands in the
  frame, for the shelf → inspect hand-off animation.

## Memory and size budget

Decoded, every plate is RGBA (4 bytes per pixel) per image, colour + `uv` +
`uv2`. Shelf plates in total are about 22 MB decoded and stay resident.
A hero frame (640 × 900 × 3 images) is **6.9 MB** decoded, so never decode
the whole rotation: keep a window around the current frame (e.g. ±2, about
35 MB), prefetch in the drag direction, and release frames you leave. Or
composite a frame once (shader → `toImage`, 2.3 MB) and drop its three
source images. `front_hi` is 4× a frame (27.6 MB as three images), so
composite it once and keep only the result.

Hero UVs are stored at 13 bits (the low 3 bits of each low byte are zero),
about 0.1 px of label art. Shelf UVs keep 16 bits. On disk the plates come
to about 6 MB in total (README has the exact figure).

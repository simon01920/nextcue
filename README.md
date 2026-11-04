# NextCue — TV and Movie Tracker

Flutter app (Android, iOS, web) for tracking shows and movies, with a
photographic VHS shelf for your collection. Package name: `showtrack`.

## Run the app

```bash
flutter pub get
flutter run -d chrome --dart-define=TVDB_API_KEY=<your key>
```

Without `TVDB_API_KEY` the app falls back to keyless AniList data (and the
shelf prints tapes from AniList covers and banners). Never commit the key.
Tests and static analysis:

```bash
flutter analyze
flutter test
```

## The VHS shelf: how it is made

The tapes, the shelf and the inspect view are **not** a 3D engine at
runtime. They are **plates**: images rendered offline in Blender with
Cycles, which a fragment shader (`shaders/plate.frag`) composites at runtime
with each title's own artwork from TVDB:

* **front cover**: the poster
* **spine**: the clear logo, or the fitted title
* **back cover**: the background (fanart)
* **cassette spine sticker**: the wide banner
* **cassette face sticker**: the logo over the background

Every printed surface is rendered blank in the plates, together with two
data images: where each pixel lands on the artwork sheet (16-bit UVs) and
how much light it receives. So the art is lit, curved and occluded exactly
like the 3D object, at the cost of a few texture fetches per pixel. All
label art in `renders/` is placeholder art drawn by our own scripts.

* Contract between Blender and the app: [`docs/PLATES.md`](docs/PLATES.md)
* Label design system: [`docs/LABELS.md`](docs/LABELS.md)
* Audit, risks and the rendering decision (plates vs. real-time GLB):
  [`docs/AUDIT.md`](docs/AUDIT.md)

Why plates: the same pixels on Impeller, Skia and CanvasKit (web has no
`flutter_gpu`), path-traced light and contact shadows that a phone could
not render in real time, and a scrolling cost of drawing a few images.

### In the app

* **Profile → Favourites shelf**: your favourites (15 free / 30 premium),
  and **Collection** opens every tracked title as shelf sections
  (watching, not started, completed, stopped). It scales to 500 tapes;
  bays compose lazily as they scroll in.
* **State on the tape:**
  * not started: shrink-wrapped, with a NEW sticker
  * watching: a tape counter on the spine, and the current tape stands
    pulled forward
  * completed: a Be Kind Rewind sticker
  * new episode: a NEW EP starburst
* **Tap a tape**: it lifts out and turns to its front cover. Drag to turn
  it all the way round. The cassette's reels show how far you are, and
  one tap marks the next episode watched.
* Runtime code: `lib/shelf/`.
  * Shader: `shaders/plate.frag`.
  * Labels: `lib/shelf/labels/`.
  * TVDB artwork: `lib/shelf/tape_catalog.dart`, which loads the poster,
    clear logo, banner and background per title at bounded sizes.

Screenshots before and after the remodel: `docs/audit/before-*.png` and
`docs/audit/after-*.png`. To regenerate them, serve a release web build and
run the CDP harness:

```bash
node tools/shoot/serve.mjs build/web 8199
```

```bash
node tools/shoot/shoot.mjs tools/shoot/scenarios/after_shelf.json
```

### Benchmark

```bash
flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart --target=integration_test/shelf_benchmark_test.dart -d <device>
```

The results are in `docs/AUDIT.md` §6. On the Android emulator the shelf
adds 1.7–3.4 ms of raster time per frame over a plain list of the same
images. The emulator itself can't reach 60 fps even on that plain list.
60 fps on a physical mid-range phone has not been measured yet.

## Rebuild every 3D asset

Blender 5.x (developed on 5.2.0; target 5.1.2, scripts adapt). Everything
is generated from the Python in `blender/`: no downloaded models, textures
or HDRIs.

```powershell
powershell -ExecutionPolicy Bypass -File blender/build.ps1
```

```bash
blender --background --factory-startup --python blender/build.py --
```

Options (after `--`): `--only shelf hero glb renders`, `--quick` (low samples,
for look-dev), `--no-glb`, `--no-plates`, `--no-renders`,
`--preview cassette sleeve shelf glb` (look-dev shots to `renders/_preview`).
A full rebuild takes about 25 minutes on an RTX 2070 SUPER (OptiX).

The beauty renders need the generated sample art first, and the turntable
frames are encoded afterwards (Python 3 with numpy and Pillow):

```bash
python tools/plates/composite.py samples
python tools/plates/turntable.py
```

`python tools/plates/composite.py shelf|hero` composites plates with test
art using the exact shader maths. It is the reference used to QA plates.

### Scripts

| Script | Produces |
|---|---|
| `blender/build.py` | entry point; steps `shelf`, `hero`, `glb`, `renders` |
| `blender/nc/` | shared: scene/Cycles setup, quad-lattice modelling helpers (`geo`), procedural materials with the beauty / label-light / UV pass switch (`mats`), light rigs (`rig`), atlas layouts (`atlas`), plate renderer and packer (`plates`), exact PNG writer (`png`) |
| `blender/assets/cassette.py` | VHS cassette, 188 × 104 × 25 mm: shell with recesses, window, door, write-protect tab, screws, reels whose packs follow watch progress, stickers |
| `blender/assets/sleeve.py` | cardboard slipcase with board thickness, bowed covers, crushed corners, printed ends; shrink-wrap film |
| `blender/assets/shelf.py` | walnut shelf bays: plank, back panel, dividers, aluminium rail with section card, LED strip |
| `blender/assets/shelf_plates.py` | shelf plates (bays, rail, packed/sealed/pulled/leaning tapes, shadows) |
| `blender/assets/hero_plates.py` | inspect view: 36-frame rotation, 2× front, cassette at 0–100 % |
| `blender/assets/dvd.py` | Amaray-style DVD keep case with clear overwrap |
| `blender/assets/export_glb.py` | GLBs with baked base colour, ORM (baked AO) and normal maps |
| `blender/assets/beauty.py` | portfolio stills and turntable frames |

### Assets

| Asset | Faces (quads) | Textures | Size |
|---|---|---|---|
| `assets/3d/vhs_cassette.glb` | 49 080 (93 %) | 2048² base/ORM, 1024² normal | 6.8 MB |
| `assets/3d/vhs_sleeve.glb` (with cassette) | 52 420 (94 %) | 2048² | 7.9 MB |
| `assets/3d/shelf_bay.glb` | 1 069 (98 %) | 2048² | 0.7 MB |
| `assets/3d/dvd_case.glb` | 1 770 (99 %) | 1024² | 0.4 MB |
| `assets/plates/shelf/` | 13 plates | | 0.44 MB |
| `assets/plates/hero/` | 42 plates | | 5.1 MB |

The non-quads are bevel corner fills and cylinder caps. Label material slots
(`COVER_ART`, `LABEL_SPINE`, `COVER_BACK`, `LABEL_FRONT`, `LABEL_TAPE_SPINE`,
`LABEL_SHELF_TAG`) keep their atlas UV map, so any viewer can bind artwork to
them.

### Generated images

The pipeline uses **no** downloaded or AI-generated images. Images drawn by
our own code:

| Image | Made by | Used for |
|---|---|---|
| `sample_hero.png` | `tools/plates/composite.py samples` | label art in beauty renders |
| `sample_spines.png` (4 × 4 spines) | same | per-tape art in the shelf-wall render |
| `sample_dvd.png` | same | DVD beauty render |
| `print_placeholder.png` (4 × 4 px) | `export_glb.py` | neutral texture on GLB label slots |

These 4 images live in `blender/_cache/` and are not shipped. Paper grain and
speckle for the labels are generated at runtime by `LabelPrint`. Baked GLB
textures and the plates are renders of the procedural materials, not inputs.

TVDB key: copy `.env.example` to `.env`, fill it in, and run `flutter run --dart-define-from-file=.env`. `.env` is git-ignored.

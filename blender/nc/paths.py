"""Repository paths and build arguments shared by every script."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # showtrack-app/
BLENDER_DIR = ROOT / "blender"
CACHE = BLENDER_DIR / "_cache"                      # raw EXR passes (ignored)
GLB_DIR = ROOT / "assets" / "3d"                    # committed GLBs
PLATE_DIR = ROOT / "assets" / "plates"              # committed app plates
RENDERS = ROOT / "renders"                          # turntables, beauty shots

TARGET_BLENDER = (5, 1, 2)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Arguments after Blender's ``--`` separator."""
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(prog="blender/build.py")
    ap.add_argument("--only", nargs="*", default=None,
                    help="asset names to build (default: all)")
    ap.add_argument("--quick", action="store_true",
                    help="low samples / small sizes for look-dev iterations")
    ap.add_argument("--no-glb", action="store_true")
    ap.add_argument("--no-renders", action="store_true",
                    help="skip turntables and beauty shots")
    ap.add_argument("--no-plates", action="store_true")
    ap.add_argument("--preview", nargs="*", default=None,
                    help="render named preview shots only (look-dev)")
    ap.add_argument("--force", action="store_true",
                    help="ignore the content-hash cache")
    ap.add_argument("--clay", action="store_true",
                    help="previews: override every material with grey clay")
    ap.add_argument("--sample-art", default=None,
                    help="atlas image shown on label surfaces in showcase renders")
    return ap.parse_args(argv)


def ensure_dirs() -> None:
    for d in (CACHE, GLB_DIR, PLATE_DIR, RENDERS):
        d.mkdir(parents=True, exist_ok=True)

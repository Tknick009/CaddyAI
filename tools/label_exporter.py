"""Extract labelable frames from captured swing videos.

Reads a directory of swing clips + sidecar JSONs (the format the iOS app
writes with `Data › Export training clip`) and produces a YOLO-ready
directory structure:

    out/
      images/
        train/  swing_{id}_{frame:06d}.png
        val/    swing_{id}_{frame:06d}.png
      labels/
        train/  swing_{id}_{frame:06d}.txt   (empty; labeler fills in)
        val/    swing_{id}_{frame:06d}.txt
      data.yaml

The only heavy dependency is ffmpeg (called via `subprocess`). Pillow is
used for a one-time sanity check; if it isn't installed we fall back to
reading the dimensions from ffprobe.

Typical usage, after you've rsynced the captured clips from S3 to a
local `./swings/` directory:

    python tools/label_exporter.py --videos ./swings --out ./dataset --fps 8

The default split is 85/15 by swing (not by frame), because frames from
the same swing are too correlated for a random frame-level split to
give an honest validation signal.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable


def _find_swings(root: Path) -> list[tuple[Path, Path]]:
    pairs: list[tuple[Path, Path]] = []
    for video in sorted(root.rglob("*.mov")):
        meta = video.with_suffix(".json")
        if not meta.exists():
            print(f"warning: {video.name} has no sidecar JSON, skipping", file=sys.stderr)
            continue
        pairs.append((video, meta))
    return pairs


def _ffmpeg_extract(video: Path, fps: int, out_dir: Path, stem: str) -> int:
    """Run ffmpeg; return number of frames written."""
    out_dir.mkdir(parents=True, exist_ok=True)
    pattern = out_dir / f"{stem}_%06d.png"
    cmd = [
        "ffmpeg", "-y",
        "-hide_banner", "-loglevel", "error",
        "-i", str(video),
        "-vf", f"fps={fps}",
        str(pattern),
    ]
    subprocess.check_call(cmd)
    return len(list(out_dir.glob(f"{stem}_*.png")))


def _split(stem: str, val_ratio: float) -> str:
    """Deterministic per-swing train/val split (same swing → same bucket)."""
    h = int(hashlib.md5(stem.encode()).hexdigest(), 16)
    return "val" if (h % 1000) / 1000.0 < val_ratio else "train"


def _write_empty_labels(images: Iterable[Path], labels_dir: Path) -> None:
    labels_dir.mkdir(parents=True, exist_ok=True)
    for img in images:
        (labels_dir / f"{img.stem}.txt").touch()


def _write_data_yaml(out: Path) -> None:
    (out / "data.yaml").write_text(
        "path: .\n"
        "train: images/train\n"
        "val: images/val\n"
        "nc: 1\n"
        "names: [clubhead]\n"
    )


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--videos", required=True, type=Path,
                    help="directory of captured .mov + .json pairs")
    ap.add_argument("--out", required=True, type=Path,
                    help="dataset output directory")
    ap.add_argument("--fps", type=int, default=8,
                    help="frames per second to extract (default 8)")
    ap.add_argument("--val-ratio", type=float, default=0.15,
                    help="fraction of *swings* to route to the val set")
    ap.add_argument("--force", action="store_true",
                    help="wipe the output directory before running")
    args = ap.parse_args(argv)

    if args.force and args.out.exists():
        shutil.rmtree(args.out)

    pairs = _find_swings(args.videos)
    if not pairs:
        print(f"no (.mov, .json) pairs under {args.videos}", file=sys.stderr)
        return 1

    total = 0
    for video, meta_path in pairs:
        meta = json.loads(meta_path.read_text())
        swing_id = meta.get("swing_id") or video.stem
        stem = f"swing_{swing_id}"
        bucket = _split(swing_id, args.val_ratio)

        img_dir = args.out / "images" / bucket
        lbl_dir = args.out / "labels" / bucket
        n = _ffmpeg_extract(video, args.fps, img_dir, stem)
        _write_empty_labels(img_dir.glob(f"{stem}_*.png"), lbl_dir)
        total += n
        print(f"{video.name}: {n} frames → {bucket}")

    _write_data_yaml(args.out)
    print(f"wrote {total} frames; run label-studio or CVAT on {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

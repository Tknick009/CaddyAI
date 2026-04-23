"""Exercise the pure-Python helpers in `tools/label_exporter.py`.

The end-to-end ffmpeg path needs a real video and ffmpeg on PATH, so
we don't call `main()` here — we cover the stable library surface that
decides split buckets and emits the training metadata.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[2]
_TOOL = _ROOT / "tools" / "label_exporter.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("label_exporter", _TOOL)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules["label_exporter"] = mod
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def test_split_is_deterministic():
    le = _load_module()
    # Same swing id → same bucket, across calls.
    assert le._split("abc123", 0.15) == le._split("abc123", 0.15)
    assert le._split("def456", 0.15) == le._split("def456", 0.15)


def test_split_respects_val_ratio():
    le = _load_module()
    swings = [f"swing-{i:04d}" for i in range(1000)]
    val = sum(1 for s in swings if le._split(s, 0.15) == "val")
    # Hash-based split should land near the target; allow a wide band
    # so we don't flake on implementation details.
    assert 100 < val < 200


def test_write_data_yaml(tmp_path):
    le = _load_module()
    le._write_data_yaml(tmp_path)
    yaml = (tmp_path / "data.yaml").read_text()
    assert "nc: 1" in yaml
    assert "clubhead" in yaml
    assert "images/train" in yaml
    assert "images/val" in yaml


def test_write_empty_labels_matches_image_stems(tmp_path):
    le = _load_module()
    images = tmp_path / "imgs"
    labels = tmp_path / "lbls"
    images.mkdir()
    (images / "swing_a_000001.png").write_bytes(b"stub")
    (images / "swing_a_000002.png").write_bytes(b"stub")
    le._write_empty_labels(images.glob("*.png"), labels)
    out = sorted(p.name for p in labels.glob("*.txt"))
    assert out == ["swing_a_000001.txt", "swing_a_000002.txt"]
    for p in labels.glob("*.txt"):
        assert p.read_text() == ""


def test_find_swings_skips_clips_without_metadata(tmp_path):
    le = _load_module()
    (tmp_path / "a.mov").write_bytes(b"stub")
    (tmp_path / "a.json").write_text('{"swing_id": "a", "fps": 120}')
    (tmp_path / "b.mov").write_bytes(b"stub")   # no JSON — should be skipped
    pairs = le._find_swings(tmp_path)
    assert len(pairs) == 1
    assert pairs[0][0].name == "a.mov"

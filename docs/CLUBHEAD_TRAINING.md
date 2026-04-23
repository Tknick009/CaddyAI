# Training the club-head detector

This document covers the end-to-end pipeline for the CoreML model the
iOS app loads as `ClubHeadDetector.mlmodelc`. Training it is entirely
offline — none of this runs on a user's phone.

Contents

1. What the model is
2. Data collection
3. Labeling
4. Training (YOLOv8 → CoreML)
5. Dropping the model into the app
6. Evaluating in-app
7. Known failure modes

---

## 1. What the model is

A single-class object detector (`clubhead`) that takes one 720×720 RGB
video frame and returns 0 or more bounding boxes around the club-head
in that frame. We deliberately keep it small (< 6 MB `.mlmodelc`) so it
runs at 60–120 fps on an iPhone 13 and later via the Neural Engine.

Architecture: YOLOv8-n with the detection head pruned to a single
class. Input 720×720 is chosen to balance recall (need to see the
club-head when it's a small blur near impact) against Neural Engine
throughput.

**Fallback**: if the model isn't bundled, the app switches to
`VNTrackObjectRequest` seeded by the user tapping the club-head on the
first frame. That works fine for analysis but requires a tap; the ML
detector is the "no setup" path.

## 2. Data collection

Minimum useful dataset: **~800 labelled frames** across ~50 swings.
Diversity beats volume here — we need the detector to see the club-head
at many angles/positions, not the same address position 800 times.

Targets:

- 25+ right-handed, 25+ left-handed swings
- Both down-the-line and face-on angles
- Indoors (simulator / hitting bay) **and** outdoors (range / course)
- Daylight and artificial light
- Variety of clubs (driver, long iron, mid iron, wedge) — wedge heads
  look meaningfully different from a driver head and the detector has
  to generalize
- A few deliberately-bad swings (chunks, tops) — the detector shouldn't
  break when the motion isn't "textbook"

The **in-app data-collection tool** (`Data › Export training clip`)
saves the raw HEVC video plus a sidecar JSON with capture metadata:

```json
{
  "swing_id": "…",
  "fps": 120,
  "handedness": "right",
  "viewpoint": "dtl",
  "club_kind": "iron",
  "device_model": "iPhone 15 Pro"
}
```

Upload the `.mov` + `.json` pair to S3; the scripts below read that
layout.

## 3. Labeling

We use the open-source `label-studio` container with the YOLO output
format. Script `tools/label_exporter.py` (in this repo) walks a tree of
captured swings and produces:

- frame PNGs at configurable sampling rate (5–10 fps is plenty — we
  don't need every frame labelled; the spatial variety is what matters)
- one empty `.txt` per frame in YOLO format so label-studio picks them
  up

```bash
python tools/label_exporter.py \
  --videos s3://caddyai-training/swings/ \
  --out   ./dataset \
  --fps   8
```

Expect a human labeler to hit about 180 frames/hour on average.
Budget: 4-6 hours for v0 (800 frames).

## 4. Training

```bash
pip install ultralytics coremltools pillow
```

Directory layout after labeling:

```
dataset/
  images/{train,val}/*.png
  labels/{train,val}/*.txt
  data.yaml
```

Train with:

```bash
yolo detect train \
  data=dataset/data.yaml \
  model=yolov8n.pt \
  imgsz=720 \
  epochs=60 \
  batch=32 \
  name=clubhead_v0
```

Export to CoreML with a float16 half-precision weights and non-maximum
suppression baked in:

```bash
yolo export \
  model=runs/detect/clubhead_v0/weights/best.pt \
  format=coreml \
  half=True \
  nms=True \
  imgsz=720
```

You should see `best.mlpackage/` pop out next to `best.pt`. Rename:

```bash
mv runs/detect/clubhead_v0/weights/best.mlpackage ClubHeadDetector.mlpackage
```

Smoke-check the export:

```bash
python -c "
import coremltools as ct
m = ct.models.MLModel('ClubHeadDetector.mlpackage')
print(m.get_spec().description)
"
```

The `labels` field should list exactly `['clubhead']`.

## 5. Dropping the model into the app

```bash
cp -R ClubHeadDetector.mlpackage ios/CaddyAI/Resources/
```

Then update `ios/CaddyAI/project.yml` to include the folder in the app
target's `resources:` block (XcodeGen regenerates the project).

`ClubHeadMLDetector` loads it at startup; the app behaves identically
to before except `ClubHeadSession.mode` starts in `.automatic` instead
of falling back to seeded tracking.

## 6. Evaluating in-app

We keep a tiny XCTest that feeds a hand-picked fixture swing through
the pipeline and asserts the detector returns ≥ 1 box per keyframe
(address / top / impact / finish). See
`Tests/CaddyAICoreTests/ClubHeadTrackingTests.swift`.

For harder regression testing, use the backend `/coach/swing/history`
endpoint — every swing stores its metrics including `club_head_speed_mph`
and `club_path_deg`. Spot-check against a launch monitor ground truth
once you have one recorded.

## 7. Known failure modes & remediation

| Symptom                                          | Usual cause                                            | Fix                                                 |
| ------------------------------------------------ | ------------------------------------------------------ | --------------------------------------------------- |
| Detector loses club-head at impact (peak motion) | Motion blur; training data lacked enough fast samples  | Label ~20 more impact-adjacent frames with heavy blur |
| Miss rate high outdoors                          | Training data was mostly indoor simulator              | Expand outdoor sampling                              |
| Confuses club-head with golfer's feet / tee peg  | Single-class detector, shape overlap                   | Add negative examples, or promote to 2-class (`clubhead`, `tee`) and ignore `tee` in the app |
| False positives on background clutter            | Underfit — too few epochs or too small a model         | Increase to `yolov8s` (~12 MB `.mlmodelc`) and retrain |

# Architecture

## High level

```
┌────────────────────┐          ┌──────────────────────┐
│ Garmin watch       │  BLE     │ iOS app (SwiftUI)    │
│ (Connect IQ app)   │ ───────▶ │  • Swing capture     │
│ broadcasts shots   │          │  • On-device pose    │
└────────────────────┘          │  • Bag + Caddy UI    │
                                │  • Rounds / history  │
┌────────────────────┐  CSV /   │                      │
│ Launch monitor     │  API     │                      │
│ (R10, Mevo, SkyTrak│ ───────▶ │                      │
│  Rapsodo, …)       │          │                      │
└────────────────────┘          └─────────┬────────────┘
                                          │ HTTPS JSON
                                          ▼
                                ┌──────────────────────┐
                                │ FastAPI backend      │
                                │  /coach/swing        │
                                │  /caddy/recommend    │
                                │  /launch-monitor/…   │
                                │  /rounds             │
                                │  /garmin/oauth/…     │
                                └─────────┬────────────┘
                                          │
                      ┌───────────────────┼──────────────────┐
                      ▼                   ▼                  ▼
                ┌──────────┐       ┌────────────┐     ┌──────────────┐
                │ OpenAI   │       │ Garmin     │     │ Postgres /   │
                │ LLM      │       │ Connect    │     │ SQLite       │
                │          │       │ OAuth API  │     │ (shot hist)  │
                └──────────┘       └────────────┘     └──────────────┘
```

## Swing analysis pipeline

1. `SwingCaptureView` records at 120 fps using `AVCaptureSession` configured
   with `AVCaptureDevice.Format` that supports high‑frame‑rate capture.
2. For each frame, `VNDetectHumanBodyPoseRequest` extracts 17 joints +
   confidence. Frames below a confidence threshold are dropped.
3. Joints are smoothed (simple 3‑frame moving average) and normalized to
   pelvis‑centered coordinates.
4. The swing is auto‑segmented by tracking wrist Y‑position:
   - **Address** — initial rest
   - **Takeaway start** — wrist first moves above shoulders' Y
   - **Top** — wrist peaks, lead arm angular velocity ≈ 0
   - **Impact** — wrist returns to near‑address Y with maximum angular
     velocity
   - **Finish** — wrist peaks on follow‑through side
5. From the segmented time‑series, `SwingAnalyzer` computes
   `SwingMetrics` (see `CaddyAICore/Models.swift`): tempo ratio
   (backswing\:downswing), peak shoulder turn (deg), peak hip turn (deg),
   X‑factor (shoulder − hip at top), lateral sway (cm), head movement
   (cm), early extension (hip Z delta at impact vs address), swing
   plane angle (deg), weight transfer %, and a `confidence` 0..1.
6. The phone POSTs those metrics to `POST /coach/swing`. The backend
   builds a structured prompt and returns a `CoachingReport` with
   `summary`, `likely_ball_flight`, `root_causes[]`, `drills[]`.

The actual *video* is never sent to the backend — only derived metrics.
This is both a privacy and a cost win.

## Caddy pipeline

1. On course, the iOS app captures `ShotContext`:
   - `target_distance_yards` (from GPS rangefinder in the app, or user input)
   - `wind_speed_mph`, `wind_direction_deg` (from weather API or watch)
   - `lie` (`fairway | rough | bunker | tee | recovery`)
   - `elevation_change_ft`
   - `pin_position` (optional, `front | middle | back`)
   - `shot_shape_preference` (optional, `straight | draw | fade`)
2. `Bag` lists the clubs the user is carrying; each club has a
   `PersonalDistance` (`typical_yards`, `stddev_yards`, `sample_size`)
   learned from shot history.
3. `POST /caddy/recommend` applies rule‑based logic (see
   `backend/app/services/caddy.py`):
   - Adjust target distance for wind (rule of thumb: 1% per 1 mph
     headwind/tailwind), elevation (1 yard per 1 ft), lie penalty.
   - Select the club whose `typical_yards` most closely matches the
     **play distance** under normal swing, biased toward club‑up in
     trouble.
   - Return `primary`, `alt`, and `commentary` explaining the pick.

## Garmin watch (Connect IQ)

The `watch-connectiq/` Monkey C app registers a BLE GATT server on a
custom service UUID. When the Garmin golf app finishes a shot, our
Connect IQ side app reads `Activity.Info` + `Position.Info` (or hooks
into the Golf app's shot‑detected event) and writes a JSON payload
(`{club, distance_yards, lat, lon, ts}`) to a BLE characteristic. The
iOS app is the GATT central; on notify, it appends a `Shot` to the
current `Round`.

This path is **scaffolded but not fully implemented** in v1 — see
[`watch-connectiq/README.md`](../watch-connectiq/README.md).

## Data model

See [`backend/app/models/schemas.py`](../backend/app/models/schemas.py)
(Pydantic) and [`ios/CaddyAI/Sources/CaddyAICore/Models.swift`](../ios/CaddyAI/Sources/CaddyAICore/Models.swift)
(Swift `Codable`). They use snake_case JSON on the wire.

Key entities:

- `Club` — one physical club: `{id, kind, loft_deg, name}`
- `Bag` — ordered list of `Club`s + personal distances
- `PersonalDistance` — `{club_id, typical_yards, stddev_yards, sample_size}`
- `Shot` — one recorded shot: `{id, club_id, distance_yards, result, ts, source}`
- `Round` — a game: `{id, course, date, shots[]}`
- `SwingMetrics` — output of the pose pipeline
- `CoachingReport` — LLM output
- `ShotContext` / `CaddyRecommendation`

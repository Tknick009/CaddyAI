# CaddyAI

A virtual AI caddy for golf. CaddyAI has two jobs:

1. **Off the course — Swing Analysis.** Record your swing, run it through on‑device
   Apple Vision body‑pose estimation, extract a handful of biomechanical
   metrics (tempo, shoulder/hip turn, sway, swing plane, weight transfer),
   and send those metrics to an LLM to produce plain‑English coaching —
   *"Your hips are stalling at impact, which is why you flip the club and
   hook it"*.
2. **On the course — Caddy.** Pull shot + round data from your Garmin watch
   (live via BLE) and/or from a launch monitor (Garmin R10, Rapsodo MLM2PRO,
   SkyTrak, Mevo/Mevo+), learn your real per‑club distances, then give you
   club + shot‑shape recommendations for the shot in front of you given
   wind, lie, and pin.

## Status

**v1 scaffold.** This repo contains:

| Piece | Where | Status |
| --- | --- | --- |
| iOS app (SwiftUI) | [`ios/`](ios/) | Scaffold + core swing/caddy/bag flows |
| Swing metrics engine (pure Swift) | [`ios/CaddyAI/Sources/CaddyAICore`](ios/CaddyAI/Sources/CaddyAICore) | Unit‑tested |
| Backend (FastAPI) | [`backend/`](backend/) | LLM coach + caddy recommender + launch‑monitor import |
| Connect IQ watch companion | [`watch-connectiq/`](watch-connectiq/) | Monkey C skeleton + BLE broadcast plan |
| Architecture & roadmap | [`docs/`](docs/) | See `ARCHITECTURE.md`, `ROADMAP.md` |

See [docs/ROADMAP.md](docs/ROADMAP.md) for what's done vs. what's next.

## Quick start

### Backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -e '.[dev]'
export OPENAI_API_KEY=sk-...        # optional; falls back to a mock coach
uvicorn app.main:app --reload
```

Swagger UI at <http://localhost:8000/docs>.

### iOS app

Requires macOS with Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd ios/CaddyAI
brew install xcodegen
xcodegen generate
open CaddyAI.xcodeproj
```

Point the app at your backend in `Settings` (defaults to `http://localhost:8000`).

### Core package tests (cross‑platform)

The swing‑metrics engine is a pure Swift package and can be tested on Linux:

```bash
cd ios/CaddyAI
swift test
```

## Architecture (one‑paragraph version)

The iOS app captures a swing video with `AVFoundation`, runs
`VNDetectHumanBodyPoseRequest` per frame, and feeds the joint time‑series into
`SwingAnalyzer` (pure Swift, in `CaddyAICore`), which returns a `SwingMetrics`
struct. Those metrics are POSTed to `POST /coach/swing` on the FastAPI
backend, which prompts OpenAI and returns a structured `CoachingReport`.
The Caddy screen takes `ShotContext` (distance, wind, lie, elevation, pin)
plus your `Bag` and POSTs to `POST /caddy/recommend`, which applies a
rule‑based engine using learned per‑club distances from Garmin / launch
monitor shot history.

For the full story see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

MIT. See [LICENSE](LICENSE).

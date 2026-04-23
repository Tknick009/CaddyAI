# Roadmap

## v1 — Scaffold (this PR)

- [x] Monorepo layout: `ios/`, `backend/`, `watch-connectiq/`, `docs/`
- [x] Shared data model (Pydantic + Swift Codable)
- [x] Pure‑Swift swing metrics engine with unit tests (runnable on Linux CI)
- [x] FastAPI backend: `/coach/swing`, `/caddy/recommend`,
      `/launch-monitor/import`, `/bag`, `/rounds`, `/garmin/oauth/callback`
- [x] Launch monitor CSV parsers: Garmin R10, Rapsodo MLM2PRO, SkyTrak, Mevo+
- [x] Rule‑based caddy recommender (wind + elevation + lie adjustments)
- [x] LLM coach with OpenAI and deterministic fallback
- [x] iOS SwiftUI screens (Home / Swing / Review / Caddy / Bag / Rounds /
      Settings) — wired to the backend
- [x] Connect IQ companion app skeleton (manifest + `App` + BLE service stub)
- [x] CI on Ubuntu runs backend pytest + Swift core tests

## v2 — Pose accuracy

- [x] 3D pose analyzer (`SwingAnalyzer3D`) — real turn, plane, attack
      angle, pelvis slide/tilt, kinematic-sequencing metrics
- [x] iOS 17+ `VNDetectHumanBodyPose3DRequest` wrapper (`PoseEstimator3D`)
- [x] Multi-angle fusion: record face-on **and** down-the-line 2D
      captures and fuse each metric from the viewpoint that measures it
      honestly (`MultiAngleSwingAnalyzer`)
- [x] Coach system-prompt + mock heuristics understand attack-angle,
      kinematic-sequencing, and pelvis-slide faults
- [ ] Finish Connect IQ BLE broadcast + iOS GATT central handshake
- [ ] Garmin Connect OAuth + round/shot sync (post‑round fallback when the
      watch app isn't installed)
- [ ] Replace in‑memory stores with SQLite/Postgres + Alembic migrations
- [ ] Shot dispersion + strokes‑gained analytics per club
- [ ] Smart caddy: use course GPS + hazard database (OSM Golf) to account
      for doglegs, lay‑up distances, and pin‑side trouble
- [ ] Swing side‑by‑side compare vs. pro reference library

## v3 — Nice‑to‑haves

- [ ] Club‑head tracking (requires 240 fps + chroma‑keyed or ArUco marker
      sticker on the club)
- [ ] Putting stroke analyzer (separate pose + face‑on camera mode)
- [ ] Auto round journal (PDF export)
- [ ] Apple Watch native companion (no Garmin)

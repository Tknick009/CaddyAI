# AGENTS.md — guidance for AI coding agents (Devin, Claude, etc.)

This repo has three parallel codebases. When making changes, please respect the
boundaries:

## Layout

```
CaddyAI/
├── ios/                     # SwiftUI iOS app + pure‑Swift core package
│   └── CaddyAI/
│       ├── project.yml                # XcodeGen spec — regenerate .xcodeproj from this
│       ├── Package.swift              # SwiftPM manifest for CaddyAICore
│       ├── Sources/
│       │   ├── CaddyAI/               # App target (SwiftUI views, AVFoundation, Vision)
│       │   └── CaddyAICore/           # Pure Swift, no UIKit — testable on Linux
│       └── Tests/CaddyAICoreTests/    # XCTest for the core package
├── backend/                 # FastAPI + OpenAI proxy
│   ├── pyproject.toml
│   ├── app/
│   │   ├── main.py
│   │   ├── routers/         # HTTP surface
│   │   ├── services/        # coach, caddy, launch monitor parsing
│   │   └── models/          # Pydantic schemas (shared DTOs)
│   └── tests/               # pytest
├── watch-connectiq/         # Garmin Connect IQ companion app (Monkey C)
└── docs/                    # architecture + roadmap
```

## Rules of thumb

- **Keep swing math in `CaddyAICore`, not the iOS app target.** If it can be
  unit‑tested without UIKit, it belongs there. This keeps our Linux CI useful.
- **Keep DTOs in sync.** Pydantic schemas in `backend/app/models/` and Swift
  `Codable` structs in `CaddyAICore/Models.swift` must match on the wire
  (snake_case JSON). If you change one, change the other and update tests.
- **No secrets in code.** `OPENAI_API_KEY`, `GARMIN_CLIENT_ID`, etc. are read
  from environment variables. The iOS app never holds the OpenAI key —
  it always goes through the backend proxy.
- **Pre‑commit:** none configured yet. If you add one, install hooks with
  `pre-commit install` and document in README.

## Tests

- `cd ios/CaddyAI && swift test` — core swing‑metrics tests (runs on Linux).
- `cd backend && pytest` — backend tests (runs in CI).
- iOS UI / integration tests require macOS + Xcode and are not in CI.

## CI

`.github/workflows/ci.yml` runs backend pytest and Swift core tests on Ubuntu.
Don't disable either without a very good reason.

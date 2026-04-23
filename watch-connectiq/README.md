# CaddyAI — Garmin Connect IQ companion (watch app)

**Status: skeleton / planning doc.** This directory will hold the Monkey C
source for a Connect IQ "watch app" (widget-style) that runs alongside
Garmin's built-in golf app and forwards shot events to the CaddyAI iOS
app over Bluetooth LE.

## Why

Live shot data from the watch — club, distance, location — is the killer
feature for the on-course caddy. Garmin does not expose this to third
parties via Connect IQ's public APIs directly; there are two viable paths:

1. **Passive** (what this skeleton does): listen to `Activity.Info`,
   `Position.Info`, and the watch's golf data fields. When the user
   records a shot on the Garmin golf app, we pick up the GPS point and
   club, compute distance on the next "next shot" event, and broadcast.
2. **Post-round sync** (easier but delayed): drop the Connect IQ app
   entirely and use the **Garmin Health / Activity API** (OAuth 2.0
   / PartnerAuth) to fetch completed rounds from Garmin Connect. This
   path is implemented as a stub in the backend at `/garmin/oauth/*`.

For best UX we want both. Path (1) powers the caddy in real-time; path
(2) reconciles any missed shots after the round.

## Prerequisites

- Install the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
  on macOS (or in a VM).
- Apply for a Garmin Connect IQ developer ID.
- Pair a supported watch (Approach S62/S70, fēnix 7/8, epix 2, Venu 3,
  or Forerunner 965).

## Building (once the sources are fleshed out)

```bash
cd watch-connectiq
monkeyc -d fenix8 -f monkey.jungle -o bin/caddyai.prg -y <signing-key>.der
```

## BLE GATT contract (already implemented on the iOS side)

| Item | UUID |
| --- | --- |
| Service | `CADDA100-0000-4F6C-AB9D-CADDY0000001` |
| Shot characteristic (notify) | `CADDA101-0000-4F6C-AB9D-CADDY0000001` |

Payload of each notification: UTF-8 JSON matching
`CaddyAICore.Shot` (snake_case). Example:

```json
{
  "id": "b8a...",
  "club_id": "7i",
  "distance_yards": 152.3,
  "carry_yards": null,
  "ts": "2026-04-23T14:12:05Z",
  "source": "garmin_watch",
  "result": "unknown"
}
```

## Directory layout

```
watch-connectiq/
├── manifest.xml        # CIQ app manifest (version, permissions, devices)
├── monkey.jungle       # build spec
├── source/
│   ├── CaddyAIApp.mc   # entry point; registers data fields + BLE server
│   ├── ShotDetector.mc # hooks Activity.Info + Position.Info
│   └── BLEService.mc   # GATT server with one notify characteristic
└── resources/
    └── strings.xml
```

See `manifest.xml`, `monkey.jungle`, and the `.mc` stubs below. They're
syntactically plausible but NOT yet tested on a real watch.
